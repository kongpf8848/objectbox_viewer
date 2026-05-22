// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  final data = raw.sublist(16);  // Skip 16-byte prefix
  final bd = ByteData.sublistView(data);

  print('=== Debug: TodoEntity Properties Vector ===\n');

  // Find TodoEntity string
  const nameBytes = 'TodoEntity';
  int strOffset = -1;
  for (var i = 0; i < data.length - nameBytes.length; i++) {
    if (String.fromCharCodes(data.sublist(i, i + nameBytes.length)) == nameBytes) {
      strOffset = i;
      break;
    }
  }
  
  if (strOffset < 0) {
    print('TodoEntity not found!');
    return;
  }
  
  print('TodoEntity string at offset $strOffset\n');

  // Scan backwards for vtable
  // The vtableSOff is stored at the table start (before the string)
  // In FlatBuffer: table starts with int32 vtableSOff (negative offset to vtable)
  for (var candidate = strOffset - 4; candidate > strOffset - 100 && candidate >= 0; candidate -= 4) {
    final vtableSOff = bd.getInt32(candidate, Endian.little);
    if (vtableSOff < -200 || vtableSOff > -10) continue;  // vtable should be before table
    
    final vtableStart = candidate - vtableSOff;
    if (vtableStart < 0 || vtableStart + 2 > data.length) continue;
    
    final vtableSize = bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 8 || vtableSize > 128) continue;
    
    final numFields = (vtableSize - 4) ~/ 2;
    if (numFields < 5) continue;
    
    print('Found table at offset $candidate');
    print('  vtableSOff = $vtableSOff (vtable at $vtableStart)');
    print('  vtableSize = $vtableSize, numFields = $numFields\n');

    // Get field[4] (properties) offset
    final field4VtableOff = bd.getUint16(vtableStart + 4 + 4 * 2, Endian.little);
    print('field[4] vtable offset = $field4VtableOff');

    // Calculate field[4] address (field offset is relative to table start)
    final field4Addr = candidate + field4VtableOff;
    print('field[4] address = $field4Addr\n');

    // Read the properties vector
    // In FlatBuffer, a vector starts with u32 length, then u32 offsets to each element
    // OR the elements are stored inline
    
    // Try reading as offset to vector table
    final vecTableOff = bd.getUint32(field4Addr, Endian.little);
    print('Vector table offset from field4: $vecTableOff');
    
    if (vecTableOff > 0 && vecTableOff < 1000) {
      final vecTable = field4Addr + vecTableOff;
      print('Vector table at $vecTable');
      
      if (vecTable + 4 <= data.length) {
        final numProps = bd.getUint32(vecTable, Endian.little);
        print('Number of properties: $numProps\n');
        
        // Read property offsets
        for (var i = 0; i < numProps && i < 15; i++) {
          final propOffAddr = vecTable + 4 + i * 4;
          if (propOffAddr + 4 > data.length) break;
          
          final propOff = bd.getUint32(propOffAddr, Endian.little);
          final propAddr = propOffAddr + propOff;
          
          print('Property[$i]: offset=$propOff, addr=$propAddr');
          
          // Parse property
          if (propAddr + 4 <= data.length) {
            final propVtableSOff = bd.getInt32(propAddr, Endian.little);
            if (propVtableSOff > 0 && propVtableSOff < 256) {
              final propVtableStart = propAddr - propVtableSOff;
              final propVtableSize = bd.getUint16(propVtableStart, Endian.little);
              final propNumFields = (propVtableSize - 4) ~/ 2;
              
              print('  vtable at $propVtableStart, size=$propVtableSize, fields=$propNumFields');
              
              // field[0] = name (string offset)
              if (propNumFields > 0) {
                final propNameFieldOff = bd.getUint16(propVtableStart + 4 + 0 * 2, Endian.little);
                if (propNameFieldOff > 0) {
                  final propNameAddr = propAddr + propNameFieldOff;
                  if (propNameAddr + 4 <= data.length) {
                    final propStrOff = bd.getUint32(propNameAddr, Endian.little);
                    if (propStrOff > 0) {
                      final propStrAddr = propNameAddr + propStrOff;
                      if (propStrAddr + 4 <= data.length) {
                        final propStrLen = bd.getUint32(propStrAddr, Endian.little);
                        if (propStrLen > 0 && propStrLen < 100) {
                          final propName = String.fromCharCodes(
                            data.sublist(propStrAddr + 4, propStrAddr + 4 + propStrLen)
                          );
                          print('  name: "$propName"');
                        }
                      }
                    }
                  }
                }
              }
              
              // field[1] = type
              if (propNumFields > 1) {
                final propTypeFieldOff = bd.getUint16(propVtableStart + 4 + 1 * 2, Endian.little);
                if (propTypeFieldOff > 0) {
                  final propTypeAddr = propAddr + propTypeFieldOff;
                  if (propTypeAddr + 2 <= data.length) {
                    final propType = bd.getUint16(propTypeAddr, Endian.little);
                    print('  type: $propType');
                  }
                }
              }
            }
          }
          print('');
        }
      }
    } else {
      // Maybe the vector is inline?
      print('Trying inline vector at field4Addr=$field4Addr');
      for (var i = 0; i < 10; i++) {
        final valAddr = field4Addr + i * 4;
        if (valAddr + 4 > data.length) break;
        final val = bd.getUint32(valAddr, Endian.little);
        print('  [$i] at $valAddr: $val');
      }
    }
    
    break;
  }
}
