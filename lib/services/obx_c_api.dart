import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:objectbox/src/native/bindings/objectbox_c.dart';

export 'package:objectbox/src/native/bindings/objectbox_c.dart';

/// Wrapper around ObjectBox C API for CRUD operations.
///
/// Loads the same native library as `objectbox_flutter_libs` and creates
/// an [ObjectBoxC] instance to access all C function bindings.
class ObxCApi {
  late final ObjectBoxC _c;

  ObxCApi() {
    final DynamicLibrary lib;
    if (Platform.isWindows) {
      lib = DynamicLibrary.open('objectbox.dll');
    } else {
      // macOS/Linux: objectbox_flutter_libs already loaded the library
      lib = DynamicLibrary.process();
    }
    _c = ObjectBoxC(lib);
  }

  ObjectBoxC get c => _c;

  // ── Store lifecycle ──

  /// Open a store with the given options.
  Pointer<OBX_store> storeOpen(Pointer<OBX_store_options> opt) {
    final store = c.store_open(opt);
    _checkPtr(store, 'failed to open store');
    return store;
  }

  /// Close a previously opened store.
  void storeClose(Pointer<OBX_store> store) {
    final code = c.store_close(store);
    _checkCode(code, 'failed to close store');
  }

  // ── Options ──

  Pointer<OBX_store_options> opt() {
    final ptr = c.opt();
    _checkPtr(ptr, 'failed to create options');
    return ptr;
  }

  void optDirectory(Pointer<OBX_store_options> opt, String dir) {
    final cStr = dir.toNativeUtf8();
    try {
      _checkCode(c.opt_directory(opt, cStr.cast()), 'failed to set directory');
    } finally {
      malloc.free(cStr);
    }
  }

  void optModel(Pointer<OBX_store_options> opt, Pointer<OBX_model> model) {
    _checkCode(c.opt_model(opt, model), 'failed to set model');
  }

  void optModelBytes(Pointer<OBX_store_options> opt, Uint8List bytes) {
    final ptr = malloc<Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      _checkCode(
        c.opt_model_bytes(opt, ptr, bytes.length),
        'failed to set model bytes',
      );
    } finally {
      malloc.free(ptr);
    }
  }

  /// Open store in schema-less mode (no model validation).
  /// This allows opening an existing database without providing a model.
  void optReadSchema(Pointer<OBX_store_options> opt, bool value) {
    c.opt_read_schema(opt, value);
  }

  /// Open store in read-only mode.
  void optReadOnly(Pointer<OBX_store_options> opt, bool value) {
    c.opt_read_only(opt, value);
  }

  // ── Model building ──

  Pointer<OBX_model> model() {
    final ptr = c.model();
    _checkPtr(ptr, 'failed to create model');
    return ptr;
  }

  void modelEntity(Pointer<OBX_model> model, String name, int id, int uid) {
    final cStr = name.toNativeUtf8();
    try {
      _checkCode(
        c.model_entity(model, cStr.cast(), id, uid),
        'failed to add entity to model',
      );
    } finally {
      malloc.free(cStr);
    }
  }

  void modelEntityLastPropertyId(
    Pointer<OBX_model> model,
    int id,
    int uid,
  ) {
    _checkCode(
      c.model_entity_last_property_id(model, id, uid),
      'failed to set entity last property id',
    );
  }

  void modelProperty(
    Pointer<OBX_model> model,
    String name,
    int type,
    int id,
    int uid,
  ) {
    final cStr = name.toNativeUtf8();
    try {
      _checkCode(
        c.model_property(model, cStr.cast(), type, id, uid),
        'failed to add property to model',
      );
    } finally {
      malloc.free(cStr);
    }
  }

  void modelPropertyFlags(Pointer<OBX_model> model, int flags) {
    _checkCode(
      c.model_property_flags(model, flags),
      'failed to set property flags',
    );
  }

  void modelLastEntityId(Pointer<OBX_model> model, int id, int uid) {
    c.model_last_entity_id(model, id, uid);
  }

  void modelLastIndexId(Pointer<OBX_model> model, int id, int uid) {
    c.model_last_index_id(model, id, uid);
  }

  void modelLastRelationId(Pointer<OBX_model> model, int id, int uid) {
    c.model_last_relation_id(model, id, uid);
  }

  void modelEntityFlags(Pointer<OBX_model> model, int flags) {
    _checkCode(
      c.model_entity_flags(model, flags),
      'failed to set entity flags',
    );
  }

  void modelFree(Pointer<OBX_model> model) {
    c.model_free(model);
  }

  // ── Box operations ──

  /// Create a write transaction. Must call txnSuccess() or txnClose() when done.
  Pointer<OBX_txn> txnWrite(Pointer<OBX_store> store) {
    final ptr = c.txn_write(store);
    _checkPtr(ptr, 'failed to create write transaction');
    return ptr;
  }

  /// Create a read transaction. Must call txnClose() when done.
  Pointer<OBX_txn> txnRead(Pointer<OBX_store> store) {
    final ptr = c.txn_read(store);
    _checkPtr(ptr, 'failed to create read transaction');
    return ptr;
  }

  /// Commit and close a write transaction.
  void txnSuccess(Pointer<OBX_txn> txn) {
    _checkCode(c.txn_success(txn), 'failed to commit transaction');
  }

  /// Close (abort) a transaction. For write transactions, this aborts uncommitted changes.
  void txnClose(Pointer<OBX_txn> txn) {
    c.txn_close(txn); // may return error but we still need to close
  }

  Pointer<OBX_box> box(Pointer<OBX_store> store, int entityId) {
    final ptr = c.box(store, entityId);
    _checkPtr(ptr, 'failed to create box for entity $entityId');
    return ptr;
  }

  /// Look up entity ID by name in the store's model. Returns 0 if not found.
  int storeEntityId(Pointer<OBX_store> store, String name) {
    final cStr = name.toNativeUtf8();
    try {
      return c.store_entity_id(store, cStr.cast());
    } finally {
      malloc.free(cStr);
    }
  }

  /// Get object bytes by ID. Returns null if not found.
  Uint8List? boxGet(Pointer<OBX_box> boxPtr, int id) {
    final dataPtr = malloc<Pointer<Uint8>>();
    final sizePtr = malloc<Size>();
    try {
      final code = c.box_get(boxPtr, id, dataPtr, sizePtr);
      if (code == OBX_NOT_FOUND) return null;
      _checkCode(code, 'failed to get object $id');
      final data = dataPtr.value;
      final size = sizePtr.value;
      if (data == nullptr || size == 0) return null;
      return Uint8List.fromList(data.asTypedList(size));
    } finally {
      malloc.free(dataPtr);
      malloc.free(sizePtr);
    }
  }

  /// Put (insert or update) raw FlatBuffer bytes.
  /// Returns the object ID (0 on error).
  int boxPutObject4(
    Pointer<OBX_box> boxPtr,
    Pointer<Void> data,
    int size,
    int mode,
  ) {
    final id = c.box_put_object4(boxPtr, data, size, mode);
    if (id == 0) _throwError('object put failed');
    return id;
  }

  /// Remove a single object. Returns true if found and removed.
  bool boxRemove(Pointer<OBX_box> boxPtr, int id) {
    final err = c.box_remove(boxPtr, id);
    if (err == OBX_NOT_FOUND) return false;
    _checkCode(err, 'failed to remove object $id');
    return true;
  }

  /// Remove multiple objects. Returns the number of removed objects.
  int boxRemoveMany(Pointer<OBX_box> boxPtr, List<int> ids) {
    return _withIdArray(ids, (idArrayPtr) {
      final countPtr = malloc<Uint64>();
      try {
        _checkCode(
          c.box_remove_many(boxPtr, idArrayPtr, countPtr),
          'failed to remove objects',
        );
        return countPtr.value;
      } finally {
        malloc.free(countPtr);
      }
    });
  }

  // ── Error handling ──

  String lastErrorMessage() {
    final ptr = c.last_error_message();
    if (ptr == nullptr) return '';
    return ptr.cast<Utf8>().toDartString();
  }

  int lastErrorCode() => c.last_error_code();

  void lastErrorClear() => c.last_error_clear();

  // ── Constants ──
  static const int OBX_SUCCESS = 0;
  static const int OBX_NOT_FOUND = 404;
  static const int OBX_ID_NEW = 0xFFFFFFFFFFFFFFFF;

  // ── Private helpers ──

  void _checkCode(int code, String context) {
    if (code != OBX_SUCCESS) {
      final msg = lastErrorMessage();
      lastErrorClear();
      throw ObjectBoxCrudException(
        operation: context,
        errorCode: code,
        message: msg,
      );
    }
  }

  void _checkPtr(Pointer ptr, String context) {
    if (ptr == nullptr) {
      final code = lastErrorCode();
      final msg = lastErrorMessage();
      lastErrorClear();
      throw ObjectBoxCrudException(
        operation: context,
        errorCode: code,
        message: msg,
      );
    }
  }

  Never _throwError(String context) {
    final code = lastErrorCode();
    final msg = lastErrorMessage();
    lastErrorClear();
    throw ObjectBoxCrudException(
      operation: context,
      errorCode: code,
      message: msg,
    );
  }

  R _withIdArray<R>(List<int> ids, R Function(Pointer<OBX_id_array>) fn) {
    final ptr = malloc<OBX_id_array>();
    try {
      final array = ptr.ref;
      array.count = ids.length;
      array.ids = malloc<Uint64>(ids.length);
      for (var i = 0; i < ids.length; i++) {
        array.ids[i] = ids[i];
      }
      return fn(ptr);
    } finally {
      malloc.free(ptr.ref.ids);
      malloc.free(ptr);
    }
  }
}

class ObjectBoxCrudException implements Exception {
  final String operation;
  final int errorCode;
  final String message;

  ObjectBoxCrudException({
    required this.operation,
    required this.errorCode,
    this.message = '',
  });

  @override
  String toString() =>
      '$operation failed (code $errorCode)${message.isNotEmpty ? ': $message' : ''}';
}
