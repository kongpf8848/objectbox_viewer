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
  
  print('TodoEntity string at offset $strOffset');
  print('Bytes at ${strOffset-20} to ${strOffset+20}:\n');
  
  // Dump hex around the string
  final start = (strOffset - 40 < 0) ? 0 : strOffset - 40;
  final end = (strOffset + 60 > data.length) ? data.length : strOffset + 60;
  
  for (var i = start; i < end; i += 16) {
    final line = StringBuffer();
    line.write('${i.toString().padLeft(5)}: ');
    for (var j = 0; j < 16; j++) {
      if (i + j < end) {
        line.write('${data[i + j].toRadixString(16).padLeft(2, '0')} ');
      } else {
        line.write('   ');
      }
    }
    line.write(' |');
    for (var j = 0; j < 16; j++) {
      if (i + j < end) {
        final b = data[i + j];
        line.write(b >= 32 && b <= 126 ? String.fromCharCode(b) : '.');
      }
    }
    line.write('|');
    print(line.toString());
  }
  
  print('\n=== Trying to find vtable ===');
  
  // Try looking at bytes BEFORE the string
  // The entity table likely has field[3] pointing to the name string
  // Let's check if bytes before strOffset look like they could be field offsets
  for (var back = 0; back < 200; back += 4) {
    final pos = strOffset - back;
    if (pos < 0) break;
    
    // Check if this could be a vtable offset (should be positive, relatively small)
    final val = bd.getUint32(pos, Endian.little);
    if (val > 0 && val < 500) {
      final potentialTable = pos + val;
      if (potentialTable > pos && potentialTable < strOffset + 50) {
        // Check if potential table has vtableSOff that points to a reasonable vtable
        if (potentialTable + 4 < data.length) {
          final vtableSOff = bd.getInt32(potentialTable, Endian.little);
          final potentialVtableStart = potentialTable - vtableSOff;
          
          if (potentialVtableStart >= 0 && potentialVtableStart + 2 < data.length) {
            final vtableSize = bd.getUint16(potentialVtableStart, Endian.little);
            
            if (vtableSize >= 8 && vtableSize <= 64 && vtableSize % 2 == 0) {
              print('Found potential table at $potentialTable (offset=$val from $pos)');
              print('  vtableSOff=$vtableSOff, vtable at $potentialVtableStart, size=$vtableSize');
              
              // Check if this could be the entity table
              if (vtableSOff < 0) {  // vtableSOff should be negative
                print('  This looks like a valid FlatBuffer table!');
                
                // Try to parse field[3] (name)
                final field3Off = bd.getUint16(potentialVtableStart + 4 + 3*2, Endian.little);
                print('  field[3] offset from vtable = $field3Off');
                
                if (field3Off > 0) {
                  final nameFieldAddr = potentialTable + field3Off;
                  print('  name field address = $nameFieldAddr');
                  
                  if (nameFieldAddr + 4 <= data.length) {
                    final strOff = bd.getUint32(nameFieldAddr, Endian.little);
                    final strAddr = nameFieldAddr + strOff;
                    if (strAddr + 4 <= data.length) {
                      final strLen = bd.getUint32(strAddr, Endian.little);
                      if (strLen > 0 && strLen < 50) {
                        final name = String.fromCharCodes(data.sublist(strAddr + 4, strAddr + 4 + strLen));
                        print('  Extracted name: "$name"');
                        
                        if (name == 'TodoEntity') {
                          print('\n*** FOUND IT! ***');
                          print('Entity table at $potentialTable');
                          print('vtable at $potentialVtableStart');
                          
                          // Now find properties (field[4])
                          final field4Off = bd.getUint16(potentialVtableStart + 4 + 4*2, Endian.little);
                          print('\nfield[4] offset = $field4Off');
                          
                          if (field4Off > 0) {
                            final propsAddr = potentialTable + field4Off;
                            print('Properties field address = $propsAddr');
                            
                            // Read vector
                            final vecOff = bd.getUint32(propsAddr, Endian.little);
                            print('Vector offset = $vecOff (from $propsAddr)');
                            
                            final vecTable = propsAddr + vecOff;
                            print('Vector table at $vecTable');
                            
                            if (vecTable + 4 <= data.length) {
                              final numProps = bd.getUint32(vecTable, Endian.little);
                              print('Number of properties: $numProps');
                              
                              // Read first few property offsets
                              for (var pi = 0; pi < numProps && pi < 12; pi++) {
                                final propOffAddr = vecTable + 4 + pi * 4;
                                if (propOffAddr + 4 > data.length) break;
                                final propOff = bd.getUint32(propOffAddr, Endian.little);
                                final propAddr = propOffAddr + propOff;
                                print('  Property[$pi]: off=$propOff, addr=$propAddr');
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
        }
      }
    }
  }
}
