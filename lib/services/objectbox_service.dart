import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/objectbox_model.dart';

/// Service to read ObjectBox data from data.mdb directly,
/// with NO dependency on objectbox-model.json.
class ObjectBoxService {
  Future<ObjectBoxModel> openDatabase(String dbPath) async {
    final dir = Directory(dbPath);
    if (!await dir.exists()) {
      throw Exception('Database directory not found: $dbPath');
    }
    final dataFile = File(p.join(dbPath, 'data.mdb'));
    if (!await dataFile.exists()) {
      throw Exception('data.mdb not found in $dbPath');
    }
    final bytes = await dataFile.readAsBytes();
    return _ObxParser(bytes).discoverModel();
  }

  Future<Map<String, int>> getDbFileInfo(String dbPath) async {
    final dir = Directory(dbPath);
    final info = <String, int>{};
    if (!await dir.exists()) return info;
    await for (final entity in dir.list()) {
      if (entity is File) info[p.basename(entity.path)] = await entity.length();
    }
    return info;
  }

  Future<List<EntityRow>> readEntityData(
    String dbPath,
    EntityInfo entity,
  ) async {
    final dataFile = File(p.join(dbPath, 'data.mdb'));
    if (!await dataFile.exists()) {
      throw Exception('data.mdb not found in $dbPath');
    }
    final bytes = await dataFile.readAsBytes();
    return _ObxParser(bytes).readEntityData(entity);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LMDB / ObjectBox parser
//
// Verified on-disk format (ObjectBox LMDB fork):
//   Page header (16 bytes): pgno(8) + pad(2) + flags(2)@10 + lower(2)@12 +
//   upper(2)@14. flags: 0x01=branch, 0x02=leaf, 0x04=overflow, 0x08=meta.
//
//   Leaf node:   dsizeLo(2) + dsizeHi(2) + nodeFlags(2) + ksize(2) + key + value
//                nodeFlags & 0x1 (F_BIGDATA): value is an 8-byte overflow page
//                number; payload = dsize bytes contiguous from ovfPage*PS+16
//                (single header for the whole overflow run).
//   Branch node: childPgno(6 bytes LE) + ksize(2) + key.
//
//   Keys are big-endian. Schema entries use small integer keys (1..N).
//   Data entry key (8 bytes BE): [0x18][entityId<<2 (2B)][objectId (4B)].
//   Index entries use 12/16-byte keys with empty values (ignored here).
// ═══════════════════════════════════════════════════════════════════════════

class _ObxParser {
  late final Uint8List _data;
  late final ByteData _bd;
  late int _pageSize;
  late int _numPages;
  late int _magicOffset;
  List<_RawEntry>? _entriesCache;

  static const int _pBranch = 0x01;
  static const int _pLeaf = 0x02;

  _ObxParser(Uint8List rawBytes) {
    _data = rawBytes;
    _bd = ByteData.sublistView(_data);
    _magicOffset = 0;
    if (_data.length >= 20 && _bd.getUint32(16, Endian.little) == 0xBEEFC0DE) {
      _magicOffset = 16;
    }

    // ObjectBox keeps the 16-byte file prefix inside page 0, so page boundaries
    // are still aligned to the raw file, not to the LMDB magic offset.
    final pageSizeOffset = _magicOffset == 16 ? 40 : 24;
    _pageSize = _data.length > pageSizeOffset + 4
        ? _bd.getUint32(pageSizeOffset, Endian.little)
        : 4096;
    if (_pageSize < 512 || _pageSize > 65536) _pageSize = 4096;
    _numPages = _data.length ~/ _pageSize;
  }

  bool get isValid =>
      _data.length >= _pageSize &&
      _magicOffset + 4 <= _data.length &&
      _bd.getUint32(_magicOffset, Endian.little) == 0xBEEFC0DE;

  // ═══════════════════════ Model Discovery ═══════════════════════

  ObjectBoxModel discoverModel() {
    if (!isValid) return ObjectBoxModel.discovered([]);

    final entitiesById = <int, _ParsedEntity>{};
    for (final entry in _walkEntries()) {
      // Schema entries: 8-byte big-endian small-integer keys (>= 1),
      // excluding 0x18-prefixed data keys and 12/16-byte index keys.
      if (entry.isDataKey || entry.key.length != 8) continue;
      final schemaKey = entry.keyBigEndian;
      if (schemaKey <= 0 || schemaKey > 0xFFFF) continue;
      final parsed = _parseSchemaValue(entry.value, schemaKey);
      if (parsed == null || parsed.name.isEmpty) continue;
      if (parsed.name.length < 2 || !_isPrintable(parsed.name)) continue;
      entitiesById[schemaKey] = parsed;
    }
    return _buildModel(entitiesById.values.toList());
  }

  ObjectBoxModel _buildModel(List<_ParsedEntity> entities) {
    entities.sort((a, b) => a.id.compareTo(b.id));
    final model = ObjectBoxModel.discovered([]);
    for (final e in entities) {
      final entityInfo = EntityInfo.discovered(e.name);
      entityInfo.id = e.id.toString();
      entityInfo.properties.clear();
      for (final f in e.properties) {
        entityInfo.properties.add(
          PropertyInfo(
            id: f.propId.toString(),
            uid: 0,
            name: f.name,
            type: f.obxType,
            flags: f.isId ? 1 : 0,
            propertyId: f.propId,
          ),
        );
      }
      model.entities.add(entityInfo);
    }
    return model;
  }

  // ═══════════════════════ Entity Data ═══════════════════════

  List<EntityRow> readEntityData(EntityInfo entity) {
    if (!isValid) return [];
    final targetEntityId = int.tryParse(entity.id) ?? 0;
    if (targetEntityId <= 0) return [];

    final rows = <EntityRow>[];
    for (final entry in _walkEntries()) {
      // Entity ownership comes from the composite key itself — no guessing
      // by FlatBuffer field count, no cross-entity dedup.
      if (!entry.isDataKey) continue;
      if (entry.entityId != targetEntityId) continue;
      if (entry.objectId == 0) continue;

      final row = _parseDataValue(entry.value, entry.objectId, entity);
      if (row != null) rows.add(row);
    }
    rows.sort((a, b) => a.id.compareTo(b.id));
    return rows;
  }

  // ═══════════════════════ B+tree Walking ═══════════════════════

  /// All entries of the active MAIN database, collected by walking the
  /// B+tree from the root recorded in the newest meta page. Stale pages
  /// left behind by copy-on-write are never touched, so there are no
  /// ghost entries and no need for freelist filtering or dedup.
  List<_RawEntry> _walkEntries() {
    final cached = _entriesCache;
    if (cached != null) return cached;
    final entries = <_RawEntry>[];
    final root = _mainRootPgno();
    if (root > 0) {
      _walkPage(root, entries, <int>{}, 0);
    }
    _entriesCache = entries;
    return entries;
  }

  int _mainRootPgno() {
    // Pick the meta page with the higher transaction id.
    final txn0 = _metaTxnId(0);
    final txn1 = _metaTxnId(_pageSize);
    final metaOff = txn1 > txn0 ? _pageSize : 0;
    // MDB_meta: mm_dbs[1] (MAIN DB) starts at +16+24+48; md_root at +40.
    final rootOff = metaOff + 16 + 24 + 48 + 40;
    if (rootOff + 8 > _data.length) return -1;
    final root = _bd.getUint64(rootOff, Endian.little);
    return (root > 0 && root < _numPages) ? root : -1;
  }

  int _metaTxnId(int metaOff) {
    if (metaOff + 152 > _data.length) return 0;
    if (_bd.getUint32(metaOff + 16, Endian.little) != 0xBEEFC0DE) return 0;
    // MDB_meta::mm_txnid at +16+24+48+48+8 = +144
    return _bd.getUint64(metaOff + 144, Endian.little);
  }

  void _walkPage(int pgno, List<_RawEntry> out, Set<int> visited, int depth) {
    if (pgno <= 1 || pgno >= _numPages) return;
    if (!visited.add(pgno) || depth > 10) return;
    final off = pgno * _pageSize;
    if (off + 16 > _data.length) return;

    final flags = _bd.getUint16(off + 10, Endian.little);
    final lower = _bd.getUint16(off + 12, Endian.little);
    if (lower < 16 || lower > _pageSize) return;
    final numPtrs = (lower - 16) ~/ 2;
    if (numPtrs > 1000) return;

    if (flags & _pBranch != 0) {
      for (var i = 0; i < numPtrs; i++) {
        final ptr = _bd.getUint16(off + 16 + i * 2, Endian.little);
        if (ptr < 16 || ptr + 8 > _pageSize) continue;
        // Branch node: child page number in the first 6 bytes (LE).
        var child = 0;
        for (var b = 0; b < 6; b++) {
          child |= _data[off + ptr + b] << (8 * b);
        }
        _walkPage(child, out, visited, depth + 1);
      }
    } else if (flags & _pLeaf != 0) {
      for (var i = 0; i < numPtrs; i++) {
        final ptr = _bd.getUint16(off + 16 + i * 2, Endian.little);
        if (ptr < 16 || ptr + 8 > _pageSize) continue;
        final node = off + ptr;
        final dsize =
            _bd.getUint16(node, Endian.little) |
            (_bd.getUint16(node + 2, Endian.little) << 16);
        final nodeFlags = _bd.getUint16(node + 4, Endian.little);
        final ksize = _bd.getUint16(node + 6, Endian.little);
        if (node + 8 + ksize > off + _pageSize) continue;
        final key = Uint8List.sublistView(_data, node + 8, node + 8 + ksize);

        Uint8List? value;
        if (nodeFlags & 0x1 != 0) {
          // F_BIGDATA: value is the 8-byte first overflow page number.
          if (node + 8 + ksize + 8 > off + _pageSize) continue;
          final ovfPgno = _bd.getUint64(node + 8 + ksize, Endian.little);
          value = _readOverflowValue(ovfPgno, dsize);
        } else {
          if (node + 8 + ksize + dsize > off + _pageSize) continue;
          value = Uint8List.sublistView(
            _data,
            node + 8 + ksize,
            node + 8 + ksize + dsize,
          );
        }
        if (value != null) out.add(_RawEntry(key, value));
      }
    }
  }

  /// Read a big value from an overflow page run. The whole run shares one
  /// 16-byte page header, so the payload is contiguous from the first page.
  Uint8List? _readOverflowValue(int startPgno, int totalLen) {
    if (startPgno <= 1 || startPgno >= _numPages || totalLen <= 0) return null;
    final start = startPgno * _pageSize + 16;
    if (start + totalLen > _data.length) return null;
    return Uint8List.sublistView(_data, start, start + totalLen);
  }

  // ═══════════════════════ Schema Parsing ═══════════════════════

  _ParsedEntity? _parseSchemaValue(Uint8List value, int entityId) {
    final r = _FbReader(value);
    final table = r.rootTable();
    if (table == null) return null;

    String? entityName;
    List<_ParsedProperty> properties = [];

    // ObjectBox Entity FlatBuffer field layout (from actual data analysis):
    //   Modern schema: field[3] = name, field[4] = properties vector
    //   Older schema:  field[1] = name, field[2] = properties vector
    for (final nameFieldIndex in const [3, 1]) {
      if (entityName != null && entityName.isNotEmpty) break;
      final addr = r.fieldAddr(table, nameFieldIndex);
      if (addr != null) {
        final name = r.readString(addr);
        if (name != null && name.isNotEmpty) entityName = name;
      }
    }

    for (final propsFieldIndex in const [4, 2]) {
      if (properties.isNotEmpty) break;
      final addr = r.fieldAddr(table, propsFieldIndex);
      if (addr != null) {
        properties = _parsePropertiesVector(r, addr);
      }
    }

    if (entityName == null || entityName.isEmpty) {
      for (var fi = 0; fi < table.numFields; fi++) {
        final addr = r.fieldAddr(table, fi);
        if (addr == null) continue;
        final candidate = r.readString(addr);
        if (candidate != null &&
            candidate.length > 2 &&
            _isPrintable(candidate)) {
          entityName = candidate;
          break;
        }
      }
    }

    if (entityName == null || entityName.isEmpty) {
      final strings = _extractPrintableStrings(value, 0, value.length, 2);
      if (strings.isEmpty) return null;
      entityName = strings.first;
    }

    return _ParsedEntity(entityId, entityName, properties);
  }

  List<_ParsedProperty> _parsePropertiesVector(_FbReader r, int fieldAddr) {
    final result = <_ParsedProperty>[];

    if (fieldAddr + 4 > r.length) return result;
    final vecOff = r.bd.getUint32(fieldAddr, Endian.little);
    if (vecOff < 4 || vecOff > 1000000) return result;

    final vecAddr = fieldAddr + vecOff;
    if (vecAddr + 4 > r.length) return result;

    final vecLen = r.bd.getUint32(vecAddr, Endian.little);
    if (vecLen <= 0 || vecLen > 1000) return result;

    for (var i = 0; i < vecLen; i++) {
      final elemOffAddr = vecAddr + 4 + i * 4;
      if (elemOffAddr + 4 > r.length) break;

      final elemOff = r.bd.getUint32(elemOffAddr, Endian.little);
      if (elemOff == 0) continue;

      final propTableAddr = elemOffAddr + elemOff;
      if (propTableAddr + 4 > r.length) continue;

      final prop = _parsePropertyTable(r, propTableAddr, i);
      if (prop != null) result.add(prop);
    }

    return result;
  }

  _ParsedProperty? _parsePropertyTable(
    _FbReader r,
    int tableStart,
    int propIndex,
  ) {
    final table = r.tableAt(tableStart);
    if (table == null) return null;

    String? name;
    int obxType = 0;
    int flags = 0;
    int propertyId = propIndex + 1; // default: sequential

    // ObjectBox Property FlatBuffer field layout (from actual data analysis):
    //   Modern schema: field[1] = id (IdUid), field[6] = name, field[7] = type
    //   Older schema:  field[0] = id (IdUid), field[1] = name, field[2] = type

    // Property ID from IdUid (int64: lower 32 bits = local ID).
    for (final idFieldIndex in const [1, 0]) {
      if (propertyId != propIndex + 1) break; // already found
      final addr = r.fieldAddr(table, idFieldIndex);
      if (addr != null && addr + 8 <= r.length) {
        final idUid = r.bd.getUint64(addr, Endian.little);
        final localId = idUid & 0xFFFFFFFF;
        if (localId > 0 && localId < 100000) {
          propertyId = localId;
        }
      }
    }

    // Name: field[6] (modern), then field[1] (older)
    for (final nameFieldIndex in const [6, 1]) {
      if (name != null && name.isNotEmpty) break;
      final addr = r.fieldAddr(table, nameFieldIndex);
      if (addr != null) {
        name = r.readString(addr, maxLen: 1000);
      }
    }

    // Type: field[7] (modern, low byte of uint64), then field[2] (older, int32)
    final typeAddr7 = r.fieldAddr(table, 7);
    if (typeAddr7 != null && typeAddr7 < r.length) {
      obxType = r.data[typeAddr7];
    }
    if (obxType == 0) {
      final typeAddr2 = r.fieldAddr(table, 2);
      if (typeAddr2 != null && typeAddr2 + 4 <= r.length) {
        final candidateType = r.bd.getInt32(typeAddr2, Endian.little);
        // Only accept if it looks like a valid OBXPropertyType (1-15)
        if (candidateType >= 1 && candidateType <= 15) {
          obxType = candidateType;
        }
      }
    }

    // Flags: field[3] (older schema)
    final flagsAddr = r.fieldAddr(table, 3);
    if (flagsAddr != null && flagsAddr + 4 <= r.length) {
      flags = r.bd.getInt32(flagsAddr, Endian.little);
    }

    if (name == null || name.isEmpty) return null;

    return _ParsedProperty(
      propId: propertyId,
      name: name,
      obxType: obxType,
      isId: name == 'id' || (flags & 1) != 0,
    );
  }

  // ═══════════════════════ Data Value Parsing ═══════════════════════

  EntityRow? _parseDataValue(Uint8List value, int objectId, EntityInfo entity) {
    final r = _FbReader(value);
    final table = r.rootTable();
    if (table == null) return null;

    final values = <String, dynamic>{'id': objectId};
    final props = List<PropertyInfo>.from(entity.properties);

    // Build a lookup map: FlatBuffer field index → PropertyInfo.
    // In ObjectBox, data FlatBuffer field index = property ID - 1.
    // field[0] is always the object ID, so non-id properties start from
    // field[1] with property ID = fieldIndex + 1.
    final propByFieldIndex = <int, PropertyInfo>{};
    for (final prop in props) {
      final fieldIdx = prop.propertyId > 0 ? prop.propertyId - 1 : -1;
      if (fieldIdx >= 0 && !prop.isId) {
        propByFieldIndex[fieldIdx] = prop;
      }
    }

    // If no property IDs available (all propertyId == 0), fall back to
    // sequential mapping for backward compatibility.
    final useSequentialMapping = propByFieldIndex.isEmpty;

    for (var fi = 0; fi < table.numFields; fi++) {
      final fieldAddr = r.fieldAddr(table, fi);
      if (fieldAddr == null) continue;

      final PropertyInfo prop;
      if (useSequentialMapping) {
        // Legacy sequential mapping
        if (fi < props.length) {
          prop = props[fi];
          if (prop.isId) continue; // id already extracted from key
        } else {
          while (props.length <= fi) {
            props.add(
              PropertyInfo.discovered(props.length, PropertyType.unknown),
            );
          }
          prop = props[fi];
        }
      } else {
        // Property ID-based mapping
        final mapped = propByFieldIndex[fi];
        if (mapped != null) {
          prop = mapped;
        } else {
          // field[0] is the id property (already handled above)
          // Other unmapped fields (gaps from deleted properties) are skipped
          continue;
        }
      }

      final val = _readFieldValue(r, fieldAddr, prop.type);
      if (val != null) {
        values[prop.name] = val;
        if (prop.type == PropertyType.unknown.value) {
          // Update the property in the entity's list for future reference
          final idx = props.indexWhere((p) => p.name == prop.name);
          if (idx >= 0) {
            props[idx] = PropertyInfo.discovered(idx, _inferPropertyType(val));
          }
        }
      }
    }

    return EntityRow(id: objectId, values: values);
  }

  PropertyType _inferPropertyType(dynamic value) {
    if (value is bool) return PropertyType.discoveredBool;
    if (value is int) return PropertyType.discoveredLong;
    if (value is double) return PropertyType.discoveredDouble;
    if (value is String) return PropertyType.discoveredString;
    return PropertyType.unknown;
  }

  /// Read a field value using the known [propertyType] from schema.
  /// When the type is unknown (discovered mode), falls back to heuristics.
  dynamic _readFieldValue(_FbReader r, int addr, [int? propertyType]) {
    // ObjectBox PropertyType values aligned with OBXPropertyType from C API:
    //   1=bool, 2=byte, 3=short, 4=char, 5=int,
    //   6=long, 7=float, 8=double, 9=string, 10=date,
    //   11=relation, 12=dateNano, 13=flex,
    //   22=boolVector, 23=byteVector, 24=shortVector, 25=charVector,
    //   26=intVector, 27=longVector, 28=floatVector, 29=doubleVector,
    //   30=stringVector, 31=dateVector, 32=dateNanoVector
    final pt = propertyType ?? 0;
    switch (pt) {
      case 1: // bool
        if (addr + 1 > r.length) return null;
        return r.data[addr] != 0;
      case 2: // byte
        if (addr + 1 > r.length) return null;
        return r.data[addr];
      case 3: // short (int16)
        if (addr + 2 > r.length) return null;
        return r.bd.getInt16(addr, Endian.little);
      case 4: // char (16-bit character)
        if (addr + 2 > r.length) return null;
        return r.bd.getUint16(addr, Endian.little);
      case 5: // int (int32)
        if (addr + 4 > r.length) return null;
        return r.bd.getInt32(addr, Endian.little);
      case 6: // long (int64)
        if (addr + 8 > r.length) return null;
        return r.bd.getInt64(addr, Endian.little);
      case 7: // float
        if (addr + 4 > r.length) return null;
        return r.bd.getFloat32(addr, Endian.little);
      case 8: // double
        if (addr + 8 > r.length) return null;
        return r.bd.getFloat64(addr, Endian.little);
      case 9: // string
        return r.readString(addr);
      case 10: // date (ms since epoch, int64)
        if (addr + 8 > r.length) return null;
        return r.bd.getInt64(addr, Endian.little);
      case 11: // relation (int64 target ID)
        if (addr + 8 > r.length) return null;
        return r.bd.getInt64(addr, Endian.little);
      case 12: // dateNano (ns since epoch, int64)
        if (addr + 8 > r.length) return null;
        return r.bd.getInt64(addr, Endian.little);
      case 13: // flex (FlexBuffer encoded)
        return _readFlexBufferField(r, addr);
      // Vector types: stored as FlatBuffer vector with length prefix
      case 22: // boolVector
        return _readFbVector<bool>(r, addr, 1, (a) => r.data[a] != 0);
      case 23: // byteVector
        return _readFbVector<int>(r, addr, 1, (a) => r.data[a]);
      case 24: // shortVector
        return _readFbVector<int>(
          r,
          addr,
          2,
          (a) => r.bd.getInt16(a, Endian.little),
        );
      case 25: // charVector
        return _readFbVector<int>(
          r,
          addr,
          2,
          (a) => r.bd.getUint16(a, Endian.little),
        );
      case 26: // intVector
        return _readFbVector<int>(
          r,
          addr,
          4,
          (a) => r.bd.getInt32(a, Endian.little),
        );
      case 27: // longVector
        return _readFbVector<int>(
          r,
          addr,
          8,
          (a) => r.bd.getInt64(a, Endian.little),
        );
      case 28: // floatVector
        return _readFbVector<double>(
          r,
          addr,
          4,
          (a) => r.bd.getFloat32(a, Endian.little),
        );
      case 29: // doubleVector
        return _readFbVector<double>(
          r,
          addr,
          8,
          (a) => r.bd.getFloat64(a, Endian.little),
        );
      case 30: // stringVector
        return _readFbStringVector(r, addr);
      case 31: // dateVector (list of int64 ms timestamps)
        return _readFbVector<int>(
          r,
          addr,
          8,
          (a) => r.bd.getInt64(a, Endian.little),
        );
      case 32: // dateNanoVector (list of int64 ns timestamps)
        return _readFbVector<int>(
          r,
          addr,
          8,
          (a) => r.bd.getInt64(a, Endian.little),
        );
    }

    // Unknown type – heuristic fallback
    // 1) Try long (int64) — most common scalar in ObjectBox
    try {
      if (addr + 8 <= r.length) {
        final v = r.bd.getInt64(addr, Endian.little);
        if (v != 0 && v != 0x7FFFFFFFFFFFFFFF && v != -1) {
          return v;
        }
      }
    } catch (_) {}

    // 2) Try string
    try {
      final str = r.readString(addr);
      if (str != null && str.isNotEmpty) return str;
    } catch (_) {}

    // 3) Try double
    try {
      if (addr + 8 <= r.length) {
        final v = r.bd.getFloat64(addr, Endian.little);
        if (v.isFinite && v.abs() > 1e-10 && v.abs() < 1e20) return v;
      }
    } catch (_) {}

    // 4) Try int32
    try {
      if (addr + 4 <= r.length) return r.bd.getInt32(addr, Endian.little);
    } catch (_) {}

    // 5) Try bool
    try {
      if (addr + 1 <= r.length) {
        final b = r.data[addr];
        if (b <= 1) return b == 1;
      }
    } catch (_) {}

    return null;
  }

  // ═══════════════════════ Helpers ═══════════════════════

  /// Read a FlatBuffer vector of numeric values.
  List<T>? _readFbVector<T>(
    _FbReader r,
    int fieldAddr,
    int elementSize,
    T Function(int addr) readElement,
  ) {
    if (fieldAddr + 4 > r.length) return null;
    final vecOff = r.bd.getUint32(fieldAddr, Endian.little);
    if (vecOff < 4 || vecOff > 1000000) return null;
    final vecAddr = fieldAddr + vecOff;
    if (vecAddr + 4 > r.length) return null;
    final vecLen = r.bd.getUint32(vecAddr, Endian.little);
    if (vecLen > 1000000) return null; // sanity check
    final result = <T>[];
    final dataStart = vecAddr + 4;
    for (var i = 0; i < vecLen; i++) {
      final elemAddr = dataStart + i * elementSize;
      if (elemAddr + elementSize > r.length) break;
      result.add(readElement(elemAddr));
    }
    return result;
  }

  /// Read a FlatBuffer vector of strings.
  List<String>? _readFbStringVector(_FbReader r, int fieldAddr) {
    if (fieldAddr + 4 > r.length) return null;
    final vecOff = r.bd.getUint32(fieldAddr, Endian.little);
    if (vecOff < 4 || vecOff > 1000000) return null;
    final vecAddr = fieldAddr + vecOff;
    if (vecAddr + 4 > r.length) return null;
    final vecLen = r.bd.getUint32(vecAddr, Endian.little);
    if (vecLen > 100000) return null;
    final result = <String>[];
    // String vector: each element is a uint32 offset to a FlatBuffer string
    for (var i = 0; i < vecLen; i++) {
      final elemOffAddr = vecAddr + 4 + i * 4;
      if (elemOffAddr + 4 > r.length) break;
      final str = r.readString(elemOffAddr);
      if (str != null && str.isNotEmpty) result.add(str);
    }
    return result;
  }

  /// Read a Flex type field (OBXPropertyType_Flex = 13).
  dynamic _readFlexBufferField(_FbReader r, int fieldAddr) {
    if (fieldAddr + 4 > r.length) return null;
    final vecOff = r.bd.getUint32(fieldAddr, Endian.little);
    if (vecOff < 4 || vecOff > 1000000) return null;
    final dataAddr = fieldAddr + vecOff;
    if (dataAddr + 4 > r.length) return null;
    // Flex fields are stored as a byte vector in FlatBuffer
    final vecLen = r.bd.getUint32(dataAddr, Endian.little);
    if (vecLen <= 0 || vecLen > 1000000) return null;
    final dataStart = dataAddr + 4;
    if (dataStart + vecLen > r.length) return null;
    // Try to parse as FlexBuffer
    try {
      return _parseFlexBuffer(r, dataStart, vecLen);
    } catch (_) {
      // Fallback: return as hex string
      final bytes = r.data.sublist(dataStart, dataStart + vecLen);
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  /// Minimal FlexBuffer parser supporting common types.
  dynamic _parseFlexBuffer(_FbReader r, int start, int length) {
    if (length < 2) return null;
    // The last byte encodes type and indirect width
    final lastByte = r.data[start + length - 1];
    final typeNibble = lastByte >> 2;
    final width = (lastByte & 3) + 1; // 1, 2, 4, or 8 bytes

    // FlexBuffer types
    const int fbtNull = 0;
    const int fbtInt = 1;
    const int fbtUInt = 2;
    const int fbtFloat = 3;
    const int fbtString = 5;
    const int fbtMap = 9;
    const int fbtVector = 10;
    const int fbtBool = 26;

    switch (typeNibble) {
      case fbtNull:
        return null;
      case fbtInt:
        return _readFlexInt(r, start + length - 1 - width, width);
      case fbtUInt:
        return _readFlexUInt(r, start + length - 1 - width, width);
      case fbtFloat:
        if (width == 4) {
          return r.bd.getFloat32(start + length - 1 - width, Endian.little);
        } else if (width == 8) {
          return r.bd.getFloat64(start + length - 1 - width, Endian.little);
        }
        return null;
      case fbtString:
        final strLen = _readFlexUInt(r, start + length - 1 - width * 2, width);
        final strStart = start + length - 1 - width * 2 - strLen;
        if (strStart >= start && strStart + strLen <= start + length) {
          return utf8.decode(
            r.data.sublist(strStart, strStart + strLen),
            allowMalformed: true,
          );
        }
        return null;
      case fbtBool:
        return r.data[start + length - 1 - 1] != 0;
      case fbtVector:
      case fbtMap:
        final sizeAddr = start + length - 1 - width;
        final size = _readFlexUInt(r, sizeAddr, width);
        if (typeNibble == fbtVector) {
          return '<$size items>';
        } else {
          return '<$size keys>';
        }
      default:
        // Unsupported FlexBuffer type, return hex
        final bytes = r.data.sublist(start, start + length);
        return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  int _readFlexInt(_FbReader r, int addr, int width) {
    switch (width) {
      case 1:
        return r.data[addr].toSigned(8);
      case 2:
        return r.bd.getInt16(addr, Endian.little);
      case 4:
        return r.bd.getInt32(addr, Endian.little);
      case 8:
        return r.bd.getInt64(addr, Endian.little);
      default:
        return 0;
    }
  }

  int _readFlexUInt(_FbReader r, int addr, int width) {
    switch (width) {
      case 1:
        return r.data[addr];
      case 2:
        return r.bd.getUint16(addr, Endian.little);
      case 4:
        return r.bd.getUint32(addr, Endian.little);
      case 8:
        return r.bd.getUint64(addr, Endian.little);
      default:
        return 0;
    }
  }

  bool _isPrintable(String s) {
    return s.runes.every(
      (r) => (r >= 0x20 && r <= 0x7E) || (r >= 0x4E00 && r <= 0x9FFF),
    );
  }

  List<String> _extractPrintableStrings(
    Uint8List buf,
    int start,
    int end,
    int minLen,
  ) {
    final strings = <String>[];
    final pending = <int>[];
    for (var i = start; i < end && i < buf.length; i++) {
      final b = buf[i];
      if (b >= 32 && b < 127 || b >= 0x80) {
        pending.add(b);
      } else {
        if (pending.length >= minLen) {
          try {
            final s = utf8.decode(pending, allowMalformed: true);
            if (s.trim().isNotEmpty && _isMostlyPrintable(s)) {
              strings.add(s.trim());
            }
          } catch (_) {}
        }
        pending.clear();
      }
    }
    if (pending.length >= minLen) {
      try {
        final s = utf8.decode(pending, allowMalformed: true);
        if (s.trim().isNotEmpty && _isMostlyPrintable(s)) {
          strings.add(s.trim());
        }
      } catch (_) {}
    }
    return strings;
  }

  bool _isMostlyPrintable(String s) {
    if (s.isEmpty) return false;
    final printable = s.runes
        .where((r) => r >= 0x20 && r <= 0x7E || r >= 0x4E00 && r <= 0x9FFF)
        .length;
    return printable >= s.length * 0.4;
  }
}

// ═══════════════════════ Data Structures ═══════════════════════

/// A single key/value pair from the LMDB B+tree.
class _RawEntry {
  final Uint8List key;
  final Uint8List value;
  _RawEntry(this.key, this.value);

  /// Key interpreted as a big-endian unsigned integer.
  int get keyBigEndian {
    var v = 0;
    for (final b in key) {
      v = (v << 8) | b;
    }
    return v;
  }

  /// Data entry keys are 8 bytes and start with the 0x18 marker:
  ///   [0x18][entityId<<2 (2 bytes BE)][objectId (4 bytes BE)]
  bool get isDataKey => key.length == 8 && key[0] == 0x18;

  int get entityId => isDataKey ? (((key[2] << 8) | key[3]) >> 2) : 0;

  int get objectId => isDataKey
      ? ((key[4] << 24) | (key[5] << 16) | (key[6] << 8) | key[7])
      : 0;
}

/// FlatBuffer reader bound to a single value buffer.
class _FbReader {
  final Uint8List data;
  final ByteData bd;
  _FbReader(this.data) : bd = ByteData.sublistView(data);

  int get length => data.length;

  _FbTable? rootTable() {
    if (length < 8) return null;
    final rootOff = bd.getUint32(0, Endian.little);
    if (rootOff == 0 || rootOff >= length) return null;
    return tableAt(rootOff);
  }

  _FbTable? tableAt(int tableStart) {
    if (tableStart < 0 || tableStart + 4 > length) return null;
    final vtableSOff = bd.getInt32(tableStart, Endian.little);
    if (vtableSOff == 0) return null;
    // FlatBuffer allows negative vtableSOff (vtable after table in memory)
    final vtableStart = tableStart - vtableSOff;
    if (vtableStart < 0 || vtableStart + 4 > length) return null;
    final vtableSize = bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 4 || vtableSize > 512) return null;
    return _FbTable(tableStart, vtableStart, (vtableSize - 4) ~/ 2);
  }

  /// Absolute address of field [index] within [table], or null when the
  /// field is absent (default value) or out of bounds.
  int? fieldAddr(_FbTable table, int index) {
    if (index < 0 || index >= table.numFields) return null;
    final off = bd.getUint16(table.vtableStart + 4 + index * 2, Endian.little);
    if (off == 0) return null;
    final addr = table.tableStart + off;
    if (addr >= length) return null;
    return addr;
  }

  /// Read a FlatBuffer string: uint32 relative offset at [addr] pointing to
  /// [length(4)][bytes...].
  String? readString(int addr, {int maxLen = 10000}) {
    if (addr + 4 > length) return null;
    final strOff = bd.getUint32(addr, Endian.little);
    if (strOff == 0) return null;
    final strAddr = addr + strOff;
    if (strAddr + 4 > length) return null;
    final strLen = bd.getUint32(strAddr, Endian.little);
    if (strLen < 0 || strLen > maxLen || strAddr + 4 + strLen > length) {
      return null;
    }
    if (strLen == 0) return ''; // empty string is valid
    try {
      final str = utf8.decode(
        data.sublist(strAddr + 4, strAddr + 4 + strLen),
        allowMalformed: true,
      );
      return str.isNotEmpty ? str : null;
    } catch (_) {
      return null;
    }
  }
}

class _FbTable {
  final int tableStart;
  final int vtableStart;
  final int numFields;
  _FbTable(this.tableStart, this.vtableStart, this.numFields);
}

class _ParsedEntity {
  final int id;
  final String name;
  final List<_ParsedProperty> properties;
  _ParsedEntity(this.id, this.name, this.properties);
}

class _ParsedProperty {
  final int propId;
  final String name;
  final int obxType;
  final bool isId;
  _ParsedProperty({
    required this.propId,
    required this.name,
    required this.obxType,
    required this.isId,
  });
}
