import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  final dbPath = r'D:\jack\db';
  final dataFile = File('$dbPath/data.mdb');
  final bytes = await dataFile.readAsBytes();
  final bd = ByteData.view(bytes.buffer);

  // Known: TodoEntity at offset 11784, vtable at 11684 (offset 100 back)
  // But wait - the discover code scans backward from the string
  // Let me trace through manually

  // Step 1: Find "TodoEntity" string
  const targetName = 'TodoEntity';
  int stringOffset = -1;
  for (var i = 0; i < bytes.length - targetName.length; i++) {
    if (String.fromCharCodes(bytes.sublist(i, i + targetName.length)) == targetName) {
      stringOffset = i;
      break;
    }
  }
  print('String "$targetName" found at offset: $stringOffset');
  print('Hex: ${_hex(bytes, stringOffset, 20)}');

  // Step 2: The string is part of a table. Look for vtableSOff before the string
  // In ObjectBox, table starts with vtableSOff (4 bytes, negative offset to vtable)
  // For TodoEntity: vtableSOff should be negative, pointing to vtable

  // The string "TodoEntity" is at 11784 (based on earlier debug)
  // Let's scan backward from the string for a valid vtableSOff
  print('\n=== Scanning for vtableSOff ===');
  for (var delta = 4; delta < 500; delta += 4) {
    var candidateTableStart = stringOffset - delta;
    if (candidateTableStart < 4) continue;

    final vtableSOff = bd.getInt32(candidateTableStart, Endian.little);
    if (vtableSOff <= 0) continue;

    final vtableStart = candidateTableStart - vtableSOff;
    if (vtableStart < 0 || vtableStart + 2 > bytes.length) continue;

    final vtableSize = bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 8 || vtableSize > 128) continue;

    final numFields = (vtableSize - 4) ~/ 2;

    // Check if field[3] points to our string
    if (numFields > 3) {
      final field3Off = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
      if (field3Off > 0) {
        final field3Addr = candidateTableStart + field3Off;
        if (field3Addr + 4 <= bytes.length) {
          final strOff = bd.getUint32(field3Addr, Endian.little);
          if (strOff > 0 && strOff < 10000) {
            final strAddr = field3Addr + strOff;
            if (strAddr + 4 <= bytes.length) {
              final strLen = bd.getUint32(strAddr, Endian.little);
              if (strLen > 0 && strLen < 100 && strAddr + 4 + strLen <= bytes.length) {
                final name = utf8.decode(bytes.sublist(strAddr + 4, strAddr + 4 + strLen), allowMalformed: true);
                if (name == 'TodoEntity') {
                  print('FOUND TABLE at offset $candidateTableStart');
                  print('  vtableSOff: $vtableSOff');
                  print('  vtable at: $vtableStart');
                  print('  vtableSize: $vtableSize');
                  print('  numFields: $numFields');
                  print('  field[3] string: $name');

                  // Now get field[4] (properties vector)
                  if (numFields > 4) {
                    final field4Off = bd.getUint16(vtableStart + 4 + 4 * 2, Endian.little);
                    print('\n  field[4] offset: $field4Off');
                    if (field4Off > 0) {
                      final field4Addr = candidateTableStart + field4Off;
                      print('  field[4] addr: $field4Addr');
                      print('  field[4] hex: ${_hex(bytes, field4Addr, 20)}');

                      if (field4Addr + 4 <= bytes.length) {
                        final vecOff = bd.getUint32(field4Addr, Endian.little);
                        print('  vector offset from field4: $vecOff');

                        final vecAddr = field4Addr + vecOff;
                        print('  vector header at: $vecAddr');
                        print('  vector header hex: ${_hex(bytes, vecAddr, 40)}');

                        if (vecAddr + 4 <= bytes.length) {
                          final vecLen = bd.getUint32(vecAddr, Endian.little);
                          print('  vector length: $vecLen');

                          // Parse each property
                          for (var i = 0; i < vecLen && i < 20; i++) {
                            final elemOffAddr = vecAddr + 4 + i * 4;
                            if (elemOffAddr + 4 > bytes.length) break;

                            final elemOff = bd.getUint32(elemOffAddr, Endian.little);
                            if (elemOff == 0) continue;

                            final propTableAddr = elemOffAddr + elemOff;
                            print('\n  Property[$i]: table at $propTableAddr, elemOff=$elemOff');
                            print('    hex: ${_hex(bytes, propTableAddr, 20)}');

                            // Parse property vtable
                            if (propTableAddr + 4 <= bytes.length) {
                              final propVtableSOff = bd.getInt32(propTableAddr, Endian.little);
                              print('    vtableSOff: $propVtableSOff');

                              if (propVtableSOff > 0) {
                                final propVtableStart = propTableAddr - propVtableSOff;
                                print('    vtable at: $propVtableStart');

                                if (propVtableStart >= 0 && propVtableStart + 2 <= bytes.length) {
                                  final propVtableSize = bd.getUint16(propVtableStart, Endian.little);
                                  print('    vtableSize: $propVtableSize');

                                  final propNumFields = (propVtableSize - 4) ~/ 2;
                                  print('    numFields: $propNumFields');

                                  // field[0] should be name
                                  if (propNumFields > 0) {
                                    final nameFieldOff = bd.getUint16(propVtableStart + 4, Endian.little);
                                    print('    field[0] (name) offset: $nameFieldOff');
                                    if (nameFieldOff > 0) {
                                      final nameFieldAddr = propTableAddr + nameFieldOff;
                                      print('    name field addr: $nameFieldAddr');

                                      if (nameFieldAddr + 4 <= bytes.length) {
                                        final nameStrOff = bd.getUint32(nameFieldAddr, Endian.little);
                                        print('    name string offset: $nameStrOff');

                                        final nameStrAddr = nameFieldAddr + nameStrOff;
                                        if (nameStrAddr + 4 <= bytes.length) {
                                          final nameStrLen = bd.getUint32(nameStrAddr, Endian.little);
                                          print('    name string len: $nameStrLen');

                                          if (nameStrLen > 0 && nameStrLen < 500 && nameStrAddr + 4 + nameStrLen <= bytes.length) {
                                            final propName = utf8.decode(bytes.sublist(nameStrAddr + 4, nameStrAddr + 4 + nameStrLen), allowMalformed: true);
                                            print('    >>> Property name: "$propName"');
                                          }
                                        }
                                      }
                                    }
                                  }

                                  // field[1] should be type
                                  if (propNumFields > 1) {
                                    final typeFieldOff = bd.getUint16(propVtableStart + 4 + 2, Endian.little);
                                    print('    field[1] (type) offset: $typeFieldOff');
                                    if (typeFieldOff > 0) {
                                      final typeFieldAddr = propTableAddr + typeFieldOff;
                                      if (typeFieldAddr + 4 <= bytes.length) {
                                        final obxType = bd.getInt32(typeFieldAddr, Endian.little);
                                        print('    >>> OBX type: $obxType');
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }

                  return;
                }
              }
            }
          }
        }
      }
    }
  }
  print('NOT FOUND');
}

String _hex(List<int> bytes, int offset, int len) {
  final end = (offset + len).clamp(0, bytes.length);
  final start = offset.clamp(0, bytes.length);
  return bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
