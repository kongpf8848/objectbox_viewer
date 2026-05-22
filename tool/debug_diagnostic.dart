import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Diagnostic: compare schema parsing vs actual data fields
void main() {
  final bytes = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  
  final pageSize = bd.getUint32(40, Endian.little);
  final numPages = bytes.length ~/ pageSize;
  
  print('=== Phase 1: Parse Schema Entries ===\n');
  
  // Collect schema entries by entityId
  final schemaEntries = <int, List<Map<String, dynamic>>>{};
  
  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 14 > bytes.length) continue;
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 14) continue;
    final numPtrs = (lower - 14) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = bd.getUint16(off + 14 + i * 2, Endian.little);
      if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
    }
    if (ptrs.isEmpty) continue;
    ptrs.sort();
    final uniquePtrs = <int>[ptrs.first];
    for (var i = 1; i < ptrs.length; i++) {
      if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
    }
    
    for (var i = 0; i < uniquePtrs.length; i++) {
      final entryStart = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length) ? uniquePtrs[i + 1] : pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;
      
      final absEntry = off + entryStart;
      final entityId = bytes[absEntry + 15];
      
      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) { isSchema = false; break; }
      }
      if (!isSchema || entityId == 0) continue;
      
      final valStart = absEntry + 16;
      final valLen = entryLen - 16;
      
      final props = _parseEntitySchema(bytes, bd, valStart, valLen);
      schemaEntries.putIfAbsent(entityId, () => []).add({
        'name': props['name'],
        'properties': props['properties'],
      });
    }
  }
  
  // Print schema results
  schemaEntries.forEach((entityId, entries) {
    print('Entity ID: $entityId');
    for (final e in entries) {
      print('  Name: ${e['name']}');
      final props = e['properties'] as List;
      for (var i = 0; i < props.length; i++) {
        final p = props[i];
        print('    [$i] id=${p['id']} name="${p['name']}" type=${p['type']}');
      }
    }
    print('');
  });
  
  print('\n=== Phase 2: Parse Data Entries ===\n');
  
  // Now parse actual data
  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 14 > bytes.length) continue;
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 14) continue;
    final numPtrs = (lower - 14) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = bd.getUint16(off + 14 + i * 2, Endian.little);
      if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
    }
    if (ptrs.isEmpty) continue;
    ptrs.sort();
    final uniquePtrs = <int>[ptrs.first];
    for (var i = 1; i < ptrs.length; i++) {
      if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
    }
    
    for (var i = 0; i < uniquePtrs.length; i++) {
      final entryStart = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length) ? uniquePtrs[i + 1] : pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;
      
      final absEntry = off + entryStart;
      
      // Check if schema
      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) { isSchema = false; break; }
      }
      if (isSchema) continue;
      
      final entityId = bytes[absEntry + 15];
      if (entityId != 1) continue; // Only TodoEntity
      
      final objectId = bd.getUint32(absEntry, Endian.little);
      final valStart = absEntry + 16;
      final valLen = entryLen - 16;
      
      print('Data entry: entityId=$entityId objectId=$objectId valLen=$valLen');
      
      // Parse FlatBuffer fields
      final fields = _parseDataValue(bytes, bd, valStart, valLen);
      for (var i = 0; i < fields.length; i++) {
        final f = fields[i];
        print('  field[$i]: type=${f['type']} value=${f['value']}');
      }
      print('');
    }
  }
}

Map<String, dynamic> _parseEntitySchema(Uint8List bytes, ByteData bd, int valStart, int valLen) {
  if (valLen < 4) return {'name': null, 'properties': []};
  
  final rootOff = bd.getUint32(valStart, Endian.little);
  if (rootOff == 0 || rootOff >= valLen) return {'name': null, 'properties': []};
  
  final tableStart = valStart + rootOff;
  if (tableStart + 4 > valStart + valLen) return {'name': null, 'properties': []};
  
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  int vtableStart;
  if (vtableSOff > 0) {
    vtableStart = tableStart - vtableSOff;
  } else if (vtableSOff < 0) {
    vtableStart = tableStart - vtableSOff; // subtract negative = add
  } else {
    return {'name': null, 'properties': []};
  }
  
  if (vtableStart < valStart || vtableStart + 4 > valStart + valLen) {
    return {'name': null, 'properties': []};
  }
  
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;
  
  String? entityName;
  List<Map<String, dynamic>> properties = [];
  
  // field[1] = name
  if (numFields > 1) {
    final nameOff = bd.getUint16(vtableStart + 4 + 1 * 2, Endian.little);
    if (nameOff > 0) {
      entityName = _readString(bytes, bd, tableStart + nameOff, valStart, valLen);
    }
  }
  
  // field[2] = properties (vector)
  if (numFields > 2) {
    final propsOff = bd.getUint16(vtableStart + 4 + 2 * 2, Endian.little);
    if (propsOff > 0) {
      properties = _parsePropertiesVector(bytes, bd, tableStart + propsOff, valStart, valLen);
    }
  }
  
  return {'name': entityName, 'properties': properties};
}

List<Map<String, dynamic>> _parsePropertiesVector(Uint8List bytes, ByteData bd, int fieldAddr, int valStart, int valLen) {
  final result = <Map<String, dynamic>>[];
  
  final vecOff = bd.getUint32(fieldAddr, Endian.little);
  if (vecOff < 4) return result;
  
  final vecAddr = fieldAddr + vecOff;
  if (vecAddr + 4 > valStart + valLen) return result;
  
  final vecLen = bd.getUint32(vecAddr, Endian.little);
  if (vecLen <= 0 || vecLen > 100) return result;
  
  for (var i = 0; i < vecLen; i++) {
    final elemOffAddr = vecAddr + 4 + i * 4;
    if (elemOffAddr + 4 > valStart + valLen) break;
    
    final elemOff = bd.getUint32(elemOffAddr, Endian.little);
    if (elemOff == 0) continue;
    
    final propTableAddr = elemOffAddr + elemOff;
    if (propTableAddr + 4 > valStart + valLen) continue;
    
    final prop = _parsePropertyTable(bytes, bd, propTableAddr, valStart, valLen);
    if (prop != null) result.add(prop);
  }
  
  return result;
}

Map<String, dynamic>? _parsePropertyTable(Uint8List bytes, ByteData bd, int tableStart, int valStart, int valLen) {
  if (tableStart + 4 > valStart + valLen) return null;
  
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  int vtableStart;
  if (vtableSOff > 0) {
    vtableStart = tableStart - vtableSOff;
  } else if (vtableSOff < 0) {
    vtableStart = tableStart - vtableSOff;
  } else {
    return null;
  }
  
  if (vtableStart < valStart || vtableStart + 4 > valStart + valLen) return null;
  
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;
  
  String? name;
  int propId = 0;
  int type = 0;
  int flags = 0;
  
  for (var fi = 0; fi < numFields && fi < 10; fi++) {
    final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
    if (fieldOff == 0) continue;
    
    final fieldAddr = tableStart + fieldOff;
    if (fieldAddr + 4 > valStart + valLen) continue;
    
    switch (fi) {
      case 0: // id struct
        if (fieldAddr + 12 <= valStart + valLen) {
          propId = bd.getInt32(fieldAddr, Endian.little);
        }
      case 1: // name
        name = _readString(bytes, bd, fieldAddr, valStart, valLen);
      case 2: // type
        type = bd.getInt32(fieldAddr, Endian.little);
      case 3: // flags
        flags = bd.getInt32(fieldAddr, Endian.little);
    }
  }
  
  if (name == null || name.isEmpty) return null;
  return {'id': propId, 'name': name, 'type': type, 'flags': flags};
}

List<Map<String, dynamic>> _parseDataValue(Uint8List bytes, ByteData bd, int valStart, int valLen) {
  if (valLen < 4) return [];
  
  final rootOff = bd.getUint32(valStart, Endian.little);
  if (rootOff == 0 || rootOff >= valLen) return [];
  
  final tableStart = valStart + rootOff;
  if (tableStart + 4 > valStart + valLen) return [];
  
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  if (vtableSOff <= 0) return []; // Must be positive for ObjectBox
  
  final vtableStart = tableStart - vtableSOff;
  if (vtableStart < valStart) return [];
  
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;
  
  final fields = <Map<String, dynamic>>[];
  
  for (var fi = 0; fi < numFields && fi < 20; fi++) {
    final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
    if (fieldOff == 0) {
      fields.add({'index': fi, 'type': 'NOT_PRESENT', 'value': null});
      continue;
    }
    
    final fieldAddr = tableStart + fieldOff;
    if (fieldAddr + 8 > valStart + valLen) {
      fields.add({'index': fi, 'type': 'OUT_OF_BOUNDS', 'value': null});
      continue;
    }
    
    // Try string
    final strOff = bd.getUint32(fieldAddr, Endian.little);
    if (strOff >= 4 && fieldAddr + strOff + 4 <= valStart + valLen) {
      final strAddr = fieldAddr + strOff;
      final strLen = bd.getUint32(strAddr, Endian.little);
      if (strLen > 0 && strLen < 10000 && strAddr + 4 + strLen <= valStart + valLen) {
        try {
          final str = utf8.decode(bytes.sublist(strAddr + 4, strAddr + 4 + strLen), allowMalformed: true);
          if (str.runes.where((r) => r >= 32).length >= str.length * 0.3) {
            fields.add({'index': fi, 'type': 'STRING', 'value': str});
            continue;
          }
        } catch (_) {}
      }
    }
    
    // Try int64
    final i64 = bd.getInt64(fieldAddr, Endian.little);
    if (i64 > 0 && i64 < 0x7FFFFFFFFFFFFFFF) {
      // Check if it's a timestamp (nanos since epoch)
      if (i64 > 1577836800000000000 && i64 < 1893456000000000000) {
        fields.add({'index': fi, 'type': 'TIMESTAMP_NS', 'value': DateTime.fromMicrosecondsSinceEpoch(i64 ~/ 1000).toIso8601String()});
        continue;
      }
      // Check if it's a timestamp (millis since epoch)
      if (i64 > 1577836800000 && i64 < 1893456000000) {
        fields.add({'index': fi, 'type': 'TIMESTAMP_MS', 'value': DateTime.fromMillisecondsSinceEpoch(i64).toIso8601String()});
        continue;
      }
      fields.add({'index': fi, 'type': 'INT64', 'value': i64});
      continue;
    }
    
    // Try int32
    final i32 = bd.getInt32(fieldAddr, Endian.little);
    fields.add({'index': fi, 'type': 'INT32', 'value': i32});
  }
  
  return fields;
}

String? _readString(Uint8List bytes, ByteData bd, int fieldAddr, int valStart, int valLen) {
  if (fieldAddr + 4 > valStart + valLen) return null;
  final strOff = bd.getUint32(fieldAddr, Endian.little);
  if (strOff < 4) return null;
  final strAddr = fieldAddr + strOff;
  if (strAddr + 4 > valStart + valLen) return null;
  final strLen = bd.getUint32(strAddr, Endian.little);
  if (strLen <= 0 || strLen > 10000 || strAddr + 4 + strLen > valStart + valLen) return null;
  try {
    return utf8.decode(bytes.sublist(strAddr + 4, strAddr + 4 + strLen), allowMalformed: true);
  } catch (_) {
    return null;
  }
}
