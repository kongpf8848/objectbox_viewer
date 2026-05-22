// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  final data = raw.sublist(16);  // Skip 16-byte prefix
  final bd = ByteData.sublistView(data);

  print('=== Parsing TodoEntity Schema ===\n');

  // Find TodoEntity string
  final nameBytes = utf8.encode('TodoEntity');
  int? todoOffset;

  for (var i = 0; i < data.length - nameBytes.length; i++) {
    var match = true;
    for (var j = 0; j < nameBytes.length; j++) {
      if (data[i + j] != nameBytes[j]) { match = false; break; }
    }
    if (match) { todoOffset = i; break; }
  }

  if (todoOffset == null) {
    print('TodoEntity not found!');
    return;
  }

  print('Found "TodoEntity" at offset $todoOffset\n');

  // Scan backwards to find vtable
  for (var j = todoOffset; j > todoOffset - 500 && j >= 0; j -= 4) {
    final vtableSOff = bd.getInt32(j, Endian.little);
    if (vtableSOff > 0 && vtableSOff < 256) {
      final vtableStart = j - vtableSOff;
      final vtableSize = bd.getUint16(vtableStart, Endian.little);

      if (vtableSize >= 8 && vtableSize <= 128) {
        final numFields = (vtableSize - 4) ~/ 2;
        print('Found vtable at $vtableStart, size=$vtableSize, fields=$numFields');
        print('Entity table at offset $j\n');

        // Parse field[3] = name
        if (numFields > 3) {
          final nameFieldOff = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
          if (nameFieldOff > 0) {
            final nameAddr = j + nameFieldOff;
            final strOff = bd.getUint32(nameAddr, Endian.little);
            final strAddr = nameAddr + strOff;
            final strLen = bd.getUint32(strAddr, Endian.little);
            final name = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen));
            print('Entity name: "$name"\n');
          }
        }

        // Parse field[4] = properties vector
        if (numFields > 4) {
          final propsFieldOffAddr = vtableStart + 4 + 4 * 2;
          print('Reading propsFieldOff from addr=$propsFieldOffAddr');
          
          final propsFieldOff = bd.getUint16(propsFieldOffAddr, Endian.little);
          print('propsFieldOff=$propsFieldOff');

          if (propsFieldOff > 0) {
            final propsAddr = j + propsFieldOff;
            print('propsAddr=$propsAddr (j=$j, data.length=${data.length})\n');

            if (propsAddr + 4 <= data.length) {
              final vecOff = bd.getUint32(propsAddr, Endian.little);
              print('vecOff=$vecOff');

              if (vecOff > 0 && vecOff < 10000) {
                final vecTable = propsAddr + vecOff;
                print('vecTable=$vecTable');

                if (vecTable + 4 <= data.length) {
                  final numProps = bd.getUint32(vecTable, Endian.little);
                  print('numProps=$numProps\n');

                  // Read property offsets
                  print('Property offsets:');
                  for (var i = 0; i < numProps && i < 20; i++) {
                    if (vecTable + 4 + i * 4 + 4 > data.length) break;
                    final propOff = bd.getUint32(vecTable + 4 + i * 4, Endian.little);
                    final propAddr = vecTable + propOff;
                    print('  [$i] propOff=$propOff, propAddr=$propAddr');

                    // Parse Property FlatBuffer
                    if (propAddr + 4 <= data.length) {
                      final propVtableSOff = bd.getInt32(propAddr, Endian.little);
                      if (propVtableSOff > 0 && propVtableSOff < 256) {
                        final propVtableStart = propAddr - propVtableSOff;
                        final propVtableSize = bd.getUint16(propVtableStart, Endian.little);
                        final propNumFields = (propVtableSize - 4) ~/ 2;

                        // field[0] = name
                        if (propNumFields > 0) {
                          final propNameFieldOff = bd.getUint16(propVtableStart + 4 + 0 * 2, Endian.little);
                          if (propNameFieldOff > 0) {
                            final propNameAddr = propAddr + propNameFieldOff;
                            if (propNameAddr + 4 <= data.length) {
                              final propStrOff = bd.getUint32(propNameAddr, Endian.little);
                              final propStrAddr = propNameAddr + propStrOff;
                              if (propStrAddr + 4 <= data.length) {
                                final propStrLen = bd.getUint32(propStrAddr, Endian.little);
                                if (propStrLen > 0 && propStrLen < 100) {
                                  final propName = utf8.decode(data.sublist(propStrAddr + 4, propStrAddr + 4 + propStrLen));
                                  print('       name: "$propName"');
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
                              print('       type: $propType');
                            }
                          }
                        }
                      }
                    }
                    print('');
                  }
                }
              }
            }
          }
        }
        break;
      }
    }
  }
}
