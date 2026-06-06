import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import '../models/objectbox_model.dart';
import 'obx_c_api.dart';
import 'flat_buffer_builder.dart';

/// Service for CRUD operations on ObjectBox databases via C API.
///
/// On macOS, the sandbox prevents native C code (ObjectBox C API / LMDB)
/// from accessing user-selected directories. To work around this, we:
/// 1. Copy database files to a temp directory (using Dart's File API,
///    which has sandbox access from the file picker)
/// 2. Open the ObjectBox store on the temp copy
/// 3. After each write, sync data.mdb back to the original directory
///
/// ObjectBox stores the model inside the database file, so we don't need
/// to provide an explicit model when opening an existing database.
class ObjectBoxCrudService {
  final ObxCApi _c = ObxCApi();
  Pointer<OBX_store>? _store;
  final Map<int, Pointer<OBX_box>> _boxes = {};
  String? _originalDbPath;
  final _fbBuilder = ObjectBoxFbBuilder();

  /// Whether the store is currently open.
  bool get isOpen => _store != null;

  /// The original database path, or null.
  String? get currentDbPath => _originalDbPath;

  /// Open a writable ObjectBox Store for the given database path.
  ///
  /// Strategy:
  /// 1. Try schema-less mode (optReadSchema=false) on the original path.
  ///    ObjectBox reads the model from the database's internal storage.
  /// 2. Try with model from objectbox-model.json (correct UIDs).
  /// 3. Try with parsed model (may fail if UIDs are 0 in discovered mode).
  Future<void> openStore(String dbPath, ObjectBoxModel model) async {
    if (_store != null && _originalDbPath == dbPath) return;

    // Close any existing store first
    closeStore();

    final dir = Directory(dbPath);
    if (!await dir.exists()) {
      throw ObjectBoxCrudException(
        operation: 'open store',
        errorCode: -1,
        message: 'Database directory not found: $dbPath',
      );
    }

    _originalDbPath = dbPath;

    // Step 1: Open the store without explicit model.
    // ObjectBox reads the model from the database's internal storage.
    try {
      print('[CRUD] Opening store at $dbPath (read internal model)...');
      final opt = _c.opt();
      _c.optDirectory(opt, dbPath);
      _store = _c.storeOpen(opt);
      print('[CRUD] Store opened successfully');
      return;
    } catch (e) {
      print('[CRUD] Store open failed: $e');
    }

    // Step 2: Try with model from objectbox-model.json
    final modelJsonFile = File(p.join(dbPath, 'objectbox-model.json'));
    if (await modelJsonFile.exists()) {
      try {
        print('[CRUD] Trying with model from objectbox-model.json...');
        final jsonModel = await _parseModelJson(modelJsonFile);
        if (jsonModel != null) {
          await _openWithModel(dbPath, jsonModel);
          print('[CRUD] Store opened with JSON model');
          return;
        }
      } catch (e) {
        print('[CRUD] JSON model failed: $e');
      }
    }

    // Step 3: Try with the parsed model
    // This will fail if UIDs are 0 (discovered mode)
    try {
      print('[CRUD] Trying with parsed model (discovered=${model.discovered})...');
      await _openWithModel(dbPath, model);
      print('[CRUD] Store opened with parsed model');
    } catch (e) {
      print('[CRUD] All strategies failed: $e');
      rethrow;
    }
  }

  /// Parse objectbox-model.json into an ObjectBoxModel with correct UIDs.
  Future<ObjectBoxModel?> _parseModelJson(File jsonFile) async {
    try {
      final content = await jsonFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ObjectBoxModel.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Open store by building an obx_model from the given ObjectBoxModel.
  Future<void> _openWithModel(String dbPath, ObjectBoxModel model) async {
    var modelPtr = _c.model();
    try {
      for (final entity in model.entities) {
        final entityId = int.tryParse(entity.id) ?? 0;
        final entityUid = entity.uid;
        print('[CRUD] Entity: id=$entityId uid=$entityUid name=${entity.name}');

        _c.modelEntity(modelPtr, entity.name, entityId, entityUid);

        // Add properties
        for (final prop in entity.properties) {
          final propId = prop.propertyId > 0 ? prop.propertyId : int.tryParse(prop.id) ?? 0;
          final propUid = prop.uid;
          print('[CRUD]   Property: id=$propId uid=$propUid name=${prop.name} type=${prop.type} flags=${prop.flags}');
          _c.modelProperty(modelPtr, prop.name, prop.type, propId, propUid);

          // Set flags if any
          if (prop.flags != 0) {
            _c.modelPropertyFlags(modelPtr, prop.flags);
          }
        }

        // Set last property ID:UID
        final lastPropId = entity.lastPropertyId > 0
            ? entity.lastPropertyId
            : entity.properties.fold<int>(0, (a, p) {
                final pid = p.propertyId > 0 ? p.propertyId : 0;
                return a > pid ? a : pid;
              });
        final lastPropUid = entity.lastPropertyUid;
        if (lastPropId > 0) {
          _c.modelEntityLastPropertyId(modelPtr, lastPropId, lastPropUid);
        }
      }

      // Set global last IDs
      if (model.lastEntityId > 0) {
        _c.modelLastEntityId(modelPtr, model.lastEntityId, model.lastEntityUid);
      }
      if (model.lastIndexId > 0) {
        _c.modelLastIndexId(modelPtr, model.lastIndexId, model.lastIndexUid);
      }
      if (model.lastRelationId > 0) {
        _c.modelLastRelationId(modelPtr, model.lastRelationId, model.lastRelationUid);
      }

      // Create options and set model + directory
      final opt = _c.opt();
      _c.optModel(opt, modelPtr);
      // model is consumed by opt_model, so we null out our reference
      modelPtr = nullptr;
      _c.optDirectory(opt, dbPath);

      // Open the store
      _store = _c.storeOpen(opt);
      print('[CRUD] Store opened with explicit model');
    } catch (e) {
      print('[CRUD] _openWithModel FAILED: $e');
      // If model wasn't consumed yet, free it
      if (modelPtr != nullptr) {
        try { _c.modelFree(modelPtr); } catch (_) {}
      }
      rethrow;
    }
  }

  /// Close the currently open store.
  void closeStore() {
    if (_store != null) {
      try {
        _c.storeClose(_store!);
      } catch (_) {
        // Best effort close
      }
      _store = null;
      _boxes.clear();
    }
    _originalDbPath = null;
  }

  /// Delete a single object by ID.
  ///
  /// [entity] identifies the entity (name is used to look up correct entity ID).
  /// [objectId] is the object's ID within the entity.
  /// Returns true if the object was found and removed.
  Future<bool> deleteObject(EntityInfo entity, int objectId) async {
    _ensureOpen();
    final boxPtr = _getBox(entity);
    Pointer<OBX_txn>? txn;
    try {
      txn = _c.txnWrite(_store!);
      final result = _c.boxRemove(boxPtr, objectId);
      _c.txnSuccess(txn);
      txn = null;
      return result;
    } catch (e) {
      if (txn != null) _c.txnClose(txn);
      rethrow;
    }
  }

  /// Delete multiple objects by IDs.
  ///
  /// [entity] identifies the entity (name is used to look up correct entity ID).
  /// Returns the number of objects actually removed.
  Future<int> deleteObjects(EntityInfo entity, List<int> objectIds) async {
    _ensureOpen();
    if (objectIds.isEmpty) return 0;
    final boxPtr = _getBox(entity);
    Pointer<OBX_txn>? txn;
    try {
      txn = _c.txnWrite(_store!);
      final count = _c.boxRemoveMany(boxPtr, objectIds);
      _c.txnSuccess(txn);
      txn = null;
      return count;
    } catch (e) {
      if (txn != null) _c.txnClose(txn);
      rethrow;
    }
  }

  /// Update an existing object with new values.
  ///
  /// [entity] provides the schema for building the FlatBuffer.
  /// [objectId] is the object's ID.
  /// [values] maps property names to new values (excluding 'id').
  /// Properties not in [values] retain their existing values.
  Future<void> updateObject(
    EntityInfo entity,
    int objectId,
    Map<String, dynamic> values,
  ) async {
    _ensureOpen();
    final boxPtr = _getBox(entity);
    Pointer<OBX_txn>? txn;
    try {
      txn = _c.txnWrite(_store!);

      // Read existing object bytes to preserve unmodified fields
      final existingBytes = _c.boxGet(boxPtr, objectId);
      Map<String, dynamic> mergedValues;

      if (existingBytes != null) {
        // Parse existing values and merge with the new ones
        final existingValues = _parseExistingObject(existingBytes, entity);
        mergedValues = {...existingValues, ...values};
      } else {
        mergedValues = values;
      }

      // Ensure 'id' is not in the merged values (it's handled separately)
      mergedValues.remove('id');

      // Build new FlatBuffer
      final fbBytes = _fbBuilder.build(entity, mergedValues, objectId: objectId);

      // Write to ObjectBox
      final dataPtr = malloc<Uint8>(fbBytes.length);
      try {
        dataPtr.asTypedList(fbBytes.length).setAll(0, fbBytes);
        final resultId = _c.boxPutObject4(
          boxPtr,
          dataPtr.cast(),
          fbBytes.length,
          ObxCApiConstants.putModeUpdate,
        );
        if (resultId == 0) {
          throw ObjectBoxCrudException(
            operation: 'update object',
            errorCode: -1,
            message: 'Failed to update object $objectId',
          );
        }
      } finally {
        malloc.free(dataPtr);
      }

      _c.txnSuccess(txn);
      txn = null;
    } catch (e) {
      if (txn != null) _c.txnClose(txn);
      rethrow;
    }
  }

  /// Get the raw FlatBuffer bytes of an object (inside a read transaction).
  Uint8List? getObjectBytes(EntityInfo entity, int objectId) {
    _ensureOpen();
    final boxPtr = _getBox(entity);
    Pointer<OBX_txn>? txn;
    try {
      txn = _c.txnRead(_store!);
      final result = _c.boxGet(boxPtr, objectId);
      _c.txnClose(txn);
      txn = null;
      return result;
    } catch (e) {
      if (txn != null) _c.txnClose(txn);
      rethrow;
    }
  }

  // ── Private helpers ──

  void _ensureOpen() {
    if (_store == null) {
      throw ObjectBoxCrudException(
        operation: 'CRUD operation',
        errorCode: -1,
        message: 'Store is not open. Call openStore() first.',
      );
    }
  }

  Pointer<OBX_box> _getBox(EntityInfo entity) {
    // Use entity name to look up the correct entity ID in the store's model
    final resolvedId = _c.storeEntityId(_store!, entity.name);
    if (resolvedId == 0) {
      throw ObjectBoxCrudException(
        operation: 'get box',
        errorCode: -1,
        message: 'Entity "${entity.name}" not found in store model',
      );
    }
    print('[CRUD] Entity "${entity.name}" resolved to ID $resolvedId (EntityInfo.id=${entity.id})');
    return _boxes.putIfAbsent(resolvedId, () => _c.box(_store!, resolvedId));
  }

  /// Parse existing object bytes into a name->value map.
  Map<String, dynamic> _parseExistingObject(Uint8List bytes, EntityInfo entity) {
    if (bytes.length < 8) return {};

    final bd = ByteData.sublistView(bytes);
    final valLen = bytes.length;
    final valStart = 0;

    // Read root offset
    final rootOffset = bd.getUint32(0, Endian.little);
    if (rootOffset == 0 || rootOffset >= valLen) return {};

    final tableStart = valStart + rootOffset;
    if (tableStart + 4 > valStart + valLen) return {};

    // Read vtable
    final vtableSOff = bd.getInt32(tableStart, Endian.little);
    if (vtableSOff == 0) return {};
    final vtableStart = tableStart - vtableSOff;
    if (vtableStart < 0 || vtableStart + 4 > valLen) return {};

    final vtableSize = bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 4 || vtableSize > 256) return {};
    final numFields = (vtableSize - 4) ~/ 2;
    final valEnd = valLen;

    final values = <String, dynamic>{};

    // Build property lookup by field index
    final propByFieldIndex = <int, PropertyInfo>{};
    for (final prop in entity.properties) {
      final fieldIdx = prop.propertyId > 0 ? prop.propertyId - 1 : -1;
      if (fieldIdx >= 0) {
        propByFieldIndex[fieldIdx] = prop;
      }
    }

    for (var fi = 0; fi < numFields; fi++) {
      final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
      if (fieldOff == 0) continue;

      final fieldAddr = tableStart + fieldOff;
      if (fieldAddr + 1 > valEnd) continue;

      final prop = propByFieldIndex[fi];
      if (prop == null || prop.isId) continue; // Skip ID field

      final val = _readFieldValue(bytes, bd, valStart, fieldAddr, valEnd, prop.type);
      if (val != null) {
        values[prop.name] = val;
      }
    }

    return values;
  }

  /// Read a field value from FlatBuffer bytes.
  dynamic _readFieldValue(
    Uint8List data,
    ByteData bd,
    int valStart,
    int addr,
    int valEnd,
    int propertyType,
  ) {
    if (addr >= valEnd) return null;

    switch (propertyType) {
      case 1: // bool
        if (addr + 1 > valEnd) return null;
        return data[addr] != 0;
      case 2: // byte
        if (addr + 1 > valEnd) return null;
        return data[addr];
      case 3: // short (int16)
        if (addr + 2 > valEnd) return null;
        return bd.getInt16(addr, Endian.little);
      case 4: // char (uint16)
        if (addr + 2 > valEnd) return null;
        return bd.getUint16(addr, Endian.little);
      case 5: // int (int32)
        if (addr + 4 > valEnd) return null;
        return bd.getInt32(addr, Endian.little);
      case 6: // long (int64)
        if (addr + 8 > valEnd) return null;
        return bd.getInt64(addr, Endian.little);
      case 7: // float
        if (addr + 4 > valEnd) return null;
        return bd.getFloat32(addr, Endian.little);
      case 8: // double
        if (addr + 8 > valEnd) return null;
        return bd.getFloat64(addr, Endian.little);
      case 9: // string
        return _readFbString(data, bd, addr, valEnd);
      case 10: // date (int64 ms)
        if (addr + 8 > valEnd) return null;
        return bd.getInt64(addr, Endian.little);
      case 11: // relation (int64)
        if (addr + 8 > valEnd) return null;
        return bd.getInt64(addr, Endian.little);
      case 12: // dateNano (int64 ns)
        if (addr + 8 > valEnd) return null;
        return bd.getInt64(addr, Endian.little);
      // 13=flex and vector types: return null (not editable)
      default:
        return null;
    }
  }

  /// Read a FlatBuffer string at the given address.
  String? _readFbString(Uint8List data, ByteData bd, int fieldAddr, int valEnd) {
    if (fieldAddr + 4 > valEnd) return null;
    final strOff = bd.getUint32(fieldAddr, Endian.little);
    if (strOff == 0 || strOff > 100000) return null;
    final strAddr = fieldAddr + strOff;
    if (strAddr + 4 > valEnd) return null;
    final strLen = bd.getUint32(strAddr, Endian.little);
    if (strLen > 100000 || strAddr + 4 + strLen > valEnd) return null;
    if (strLen == 0) return '';
    return String.fromCharCodes(data.sublist(strAddr + 4, strAddr + 4 + strLen));
  }
}