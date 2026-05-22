import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  final bytes = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  
  final pageSize = bd.getUint32(40, Endian.little);
  final numPages = bytes.length ~/ pageSize;
  
  // Find TodoEntity schema entry (entityId=1)
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
      
      // Check schema
      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) { isSchema = false; break; }
      }
      if (!isSchema || entityId != 1) continue; // Only TodoEntity
      
      final valStart = absEntry + 16;
      final valLen = entryLen - 16;
      
      print('=== TodoEntity Schema FlatBuffer ($valLen bytes) ===\n');
      
      // Dump entire value
      for (var row = 0; row < valLen; row += 16) {
        final end = row + 16 > valLen ? valLen : row + 16;
        final hex = bytes.sublist(valStart + row, valStart + end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        final ascii = bytes.sublist(valStart + row, valStart + end).map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '.').join();
        print('  ${row.toString().padLeft(3)}: $hex  $ascii');
      }
      
      // Parse as FlatBuffer with ObjectBox convention (positive vtable offsets)
      print('\n--- FlatBuffer Parse ---');
      _parseFlatBuffer(bytes, bd, valStart, valLen, '  ');
      
      break;
    }
  }
}

void _parseFlatBuffer(Uint8List bytes, ByteData bd, int bufStart, int bufLen, String indent) {
  if (bufLen < 4) { print('${indent}Buffer too small'); return; }
  
  final rootOff = bd.getUint32(bufStart, Endian.little);
  print('${indent}rootOffset: $rootOff');
  
  if (rootOff == 0 || rootOff >= bufLen) { print('${indent}Invalid root offset'); return; }
  
  _parseTable(bytes, bd, bufStart, bufLen, bufStart + rootOff, indent);
}

void _parseTable(Uint8List bytes, ByteData bd, int bufStart, int bufLen, int tableStart, String indent) {
  if (tableStart + 4 > bufStart + bufLen) { print('${indent}Table out of bounds'); return; }
  
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  print('${indent}vtableSignedOffset: $vtableSOff');
  
  if (vtableSOff <= 0) { print('${indent}Invalid vtable offset (non-ObjectBox format)'); return; }
  
  final vtableStart = tableStart - vtableSOff;
  if (vtableStart < bufStart) { print('${indent}Vtable before buffer'); return; }
  
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final tableInline = bd.getUint16(vtableStart + 2, Endian.little);
  print('${indent}vtableSize: $vtableSize tableInline: $tableInline');
  
  final numFields = (vtableSize - 4) ~/ 2;
  print('${indent}numFields: $numFields');
  
  for (var fi = 0; fi < numFields; fi++) {
    final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
    if (fieldOff == 0) { print('${indent}field[$fi]: NOT PRESENT'); continue; }
    
    final fieldAddr = tableStart + fieldOff;
    print('${indent}field[$fi] at offset $fieldOff (abs=${fieldAddr - bufStart}):');
    
    // Read uint32 at field position
    if (fieldAddr + 4 <= bufStart + bufLen) {
      final u32 = bd.getUint32(fieldAddr, Endian.little);
      print('${indent}  u32: $u32');
      
      // Try as string offset (offset relative to field position)
      if (u32 >= 4 && u32 + fieldAddr < bufStart + bufLen) {
        final strAddr = fieldAddr + u32;
        if (strAddr + 4 <= bufStart + bufLen) {
          final strLen = bd.getUint32(strAddr, Endian.little);
          if (strLen > 0 && strLen < 10000 && strAddr + 4 + strLen <= bufStart + bufLen) {
            try {
              final strBytes = bytes.sublist(strAddr + 4, strAddr + 4 + strLen);
              final str = utf8.decode(strBytes, allowMalformed: true);
              final printable = str.runes.where((r) => r >= 0x20 && r <= 0x7e).length;
              if (printable >= str.length * 0.3 && str.trim().isNotEmpty) {
                print('${indent}  → STRING: "$str"');
              }
            } catch (_) {}
          }
        }
      }
      
      // Try as vector offset
      if (u32 >= 4 && u32 + fieldAddr < bufStart + bufLen) {
        final vecAddr = fieldAddr + u32;
        if (vecAddr + 4 <= bufStart + bufLen) {
          final vecLen = bd.getUint32(vecAddr, Endian.little);
          if (vecLen > 0 && vecLen < 100) {
            print('${indent}  → VECTOR: len=$vecLen');
            // For vectors of offsets (like Property[])
            final vecDataStart = vecAddr + 4;
            for (var vi = 0; vi < vecLen && vi < 20; vi++) {
              if (vecDataStart + (vi + 1) * 4 <= bufStart + bufLen) {
                final elemOff = bd.getUint32(vecDataStart + vi * 4, Endian.little);
                if (elemOff > 0 && vecDataStart + vi * 4 + elemOff < bufStart + bufLen) {
                  final elemAddr = vecDataStart + vi * 4 + elemOff;
                  print('${indent}    [$vi] offset=$elemOff (abs=${elemAddr - bufStart}):');
                  // Parse as nested table (Property)
                  _parsePropertyTable(bytes, bd, bufStart, bufLen, elemAddr, '${indent}      ');
                }
              }
            }
          }
        }
      }
    }
    
    // Read inline values
    if (fieldAddr + 8 <= bufStart + bufLen) {
      final i64 = bd.getInt64(fieldAddr, Endian.little);
      final i32 = bd.getInt32(fieldAddr, Endian.little);
      print('${indent}  i32: $i32  i64: $i64');
    }
  }
}

void _parsePropertyTable(Uint8List bytes, ByteData bd, int bufStart, int bufLen, int tableStart, String indent) {
  if (tableStart + 4 > bufStart + bufLen) return;
  
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  if (vtableSOff <= 0) {
    print('${indent}Invalid vtable offset: $vtableSOff');
    return;
  }
  
  final vtableStart = tableStart - vtableSOff;
  if (vtableStart < bufStart) { print('${indent}Vtable before buffer'); return; }
  
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final tableInline = bd.getUint16(vtableStart + 2, Endian.little);
  
  final numFields = (vtableSize - 4) ~/ 2;
  
  String? propName;
  int? propType;
  int? propId;
  int? propFlags;
  
  // Property FlatBuffer fields (from objectbox.fbs):
  // field[0]: id (Id table - inline)
  // field[1]: name (string - offset)
  // field[2]: type (int - inline)
  // field[3]: flags (int - inline)
  // field[4]: indexId (Id table - inline)
  // field[5]: relationTarget (string - offset)
  
  for (var fi = 0; fi < numFields; fi++) {
    final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
    if (fieldOff == 0) continue;
    
    final fieldAddr = tableStart + fieldOff;
    if (fieldAddr + 4 > bufStart + bufLen) continue;
    
    switch (fi) {
      case 0: // id (Id table with id + uid)
        // Id is an inline struct: int32 id + uint64 uid
        if (fieldAddr + 12 <= bufStart + bufLen) {
          propId = bd.getInt32(fieldAddr, Endian.little);
          final uid = bd.getUint64(fieldAddr + 4, Endian.little);
          print('${indent}id: id=$propId uid=$uid');
        }
        break;
      case 1: // name (string)
        final strOff = bd.getUint32(fieldAddr, Endian.little);
        if (strOff >= 4) {
          final strAddr = fieldAddr + strOff;
          if (strAddr + 4 <= bufStart + bufLen) {
            final strLen = bd.getUint32(strAddr, Endian.little);
            if (strLen > 0 && strLen < 1000 && strAddr + 4 + strLen <= bufStart + bufLen) {
              try {
                propName = utf8.decode(bytes.sublist(strAddr + 4, strAddr + 4 + strLen), allowMalformed: true);
                print('${indent}name: "$propName"');
              } catch (_) {}
            }
          }
        }
        break;
      case 2: // type (int)
        propType = bd.getInt32(fieldAddr, Endian.little);
        print('${indent}type: $propType (${_propertyTypeName(propType)})');
        break;
      case 3: // flags (int)
        propFlags = bd.getInt32(fieldAddr, Endian.little);
        print('${indent}flags: $propFlags');
        break;
    }
  }
  
  if (propName != null) {
    print('${indent}>>> PROPERTY: id=$propId name="$propName" type=${_propertyTypeName(propType ?? 0)} flags=$propFlags');
  }
}

String _propertyTypeName(int type) {
  const names = {
    0: 'Unknown', 1: 'Bool', 2: 'Byte', 3: 'Short', 4: 'Char',
    5: 'Int', 6: 'Long', 7: 'Float', 8: 'Double', 9: 'String',
    10: 'Date', 11: 'Relation', 12: 'DateNano', 13: 'Flex',
    22: 'BoolVector', 23: 'ByteVector', 24: 'ShortVector',
    25: 'CharVector', 26: 'IntVector', 27: 'LongVector',
    28: 'FloatVector', 29: 'DoubleVector', 30: 'StringVector',
    31: 'DateVector', 32: 'DateNanoVector',
  };
  return names[type] ?? 'Type_$type';
}
