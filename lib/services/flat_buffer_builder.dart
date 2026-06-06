import 'dart:typed_data';
import 'package:flat_buffers/flat_buffers.dart' as fb;
import '../models/objectbox_model.dart';

/// Builds FlatBuffer bytes in ObjectBox data format.
///
/// ObjectBox data FlatBuffer layout:
///   field[0]: int64 object ID  (property ID = 1)
///   field[N]: value at fieldIndex = propertyId - 1
///
/// The vtable size is calculated from the maximum property ID.
class ObjectBoxFbBuilder {
  /// Build a FlatBuffer for an ObjectBox entity.
  ///
  /// [entity] provides the schema (properties with types and propertyIds).
  /// [values] maps property names to their values.
  /// [objectId] the object ID (required for updates; OBX_ID_NEW for inserts).
  Uint8List build(EntityInfo entity, Map<String, dynamic> values, {int? objectId}) {
    final id = objectId ?? ObxCApiConstants.obxIdNew;

    // Compute the max property ID to determine vtable size.
    // field[0] = object ID (propertyId=1), field[N] = property with propertyId = N+1
    final maxPropertyId = entity.properties
        .map((p) => p.propertyId)
        .where((pid) => pid > 0)
        .fold<int>(0, (a, b) => a > b ? a : b);

    // Total fields = maxPropertyId + 1 (field 0..maxPropertyId)
    // But field[0] is always the ID. Non-id properties start at field[1].
    final totalFields = (maxPropertyId > 0 ? maxPropertyId : entity.properties.length) + 1;

    // Build property lookup: name -> PropertyInfo
    final propByName = <String, PropertyInfo>{};
    for (final prop in entity.properties) {
      propByName[prop.name] = prop;
    }

    final builder = fb.Builder(initialSize: 1024);

    // First pass: create string and vector offsets (non-inline data).
    final offsets = <String, int>{};
    for (final entry in values.entries) {
      final prop = propByName[entry.key];
      if (prop == null || prop.isId) continue;

      final fieldIdx = prop.propertyId > 0 ? prop.propertyId - 1 : -1;
      if (fieldIdx < 1) continue; // field 0 is object ID

      final val = entry.value;
      if (val == null) continue;

      final pt = prop.type;
      if (pt == PropertyType.string.value) {
        offsets[entry.key] = builder.writeString(val.toString());
      }
      // Vector types: store as byte vector for now (pass-through for flex/vector)
      // These will be handled in a future iteration.
    }

    // Second pass: build the table.
    builder.startTable(totalFields);

    // field[0] = object ID (int64)
    builder.addInt64(0, id);

    // Add each property value at its field index.
    for (final entry in values.entries) {
      final prop = propByName[entry.key];
      if (prop == null || prop.isId) continue;

      final fieldIdx = prop.propertyId > 0 ? prop.propertyId - 1 : -1;
      if (fieldIdx < 1) continue; // field 0 is object ID

      final val = entry.value;
      if (val == null) continue; // null fields are omitted (vtable offset = 0)

      _addField(builder, fieldIdx, prop.type, val, offsets[entry.key]);
    }

    final end = builder.endTable();
    builder.finish(end);
    return builder.buffer;
  }

  void _addField(fb.Builder builder, int fieldIdx, int propType, dynamic val, int? offset) {
    // PropertyType values:
    // 1=bool, 2=byte, 3=short, 4=char, 5=int, 6=long,
    // 7=float, 8=double, 9=string, 10=date, 11=relation,
    // 12=dateNano, 13=flex
    switch (propType) {
      case 1: // bool
        builder.addBool(fieldIdx, val as bool);
        break;
      case 2: // byte
        builder.addInt8(fieldIdx, (val as int).toSigned(8));
        break;
      case 3: // short (int16)
        builder.addInt16(fieldIdx, (val as int).toSigned(16));
        break;
      case 4: // char (uint16)
        builder.addInt16(fieldIdx, val as int);
        break;
      case 5: // int (int32)
        builder.addInt32(fieldIdx, val as int);
        break;
      case 6: // long (int64)
        builder.addInt64(fieldIdx, val as int);
        break;
      case 7: // float
        builder.addFloat32(fieldIdx, (val as num).toDouble());
        break;
      case 8: // double
        builder.addFloat64(fieldIdx, (val as num).toDouble());
        break;
      case 9: // string
        if (offset != null) {
          builder.addOffset(fieldIdx, offset);
        }
        break;
      case 10: // date (int64 ms)
        builder.addInt64(fieldIdx, val as int);
        break;
      case 11: // relation (int64 target ID)
        builder.addInt64(fieldIdx, val as int);
        break;
      case 12: // dateNano (int64 ns)
        builder.addInt64(fieldIdx, val as int);
        break;
      case 13: // flex — not editable in first iteration, skip
        break;
      // Vector types (22-32) — not editable in first iteration
      default:
        break;
    }
  }
}

/// Constants shared between C API and FlatBuffer builder.
class ObxCApiConstants {
  static const int obxIdNew = 0xFFFFFFFFFFFFFFFF; // OBX_ID_NEW
  static const int obxSuccess = 0;
  static const int obxNotFound = 404;

  // OBXPutMode values
  static const int putModePut = 1;
  static const int putModeInsert = 2;
  static const int putModeUpdate = 3;
}
