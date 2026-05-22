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

  // Dump hex around the string
  print('Hex dump around string:');
  final start = (strOffset - 80 < 0) ? 0 : strOffset - 80;
  final end = (strOffset + 80 > data.length) ? data.length : strOffset + 80;
  
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
    print(line.toString());
  }
  
  print('\n=== Looking for entity table ===');
  
  // The entity table for TodoEntity has vtable at 11684 (confirmed from earlier)
  // Let's manually check that region
  const vtableAddr = 11684;
  
  print('\nChecking vtable at $vtableAddr:');
  print('Bytes: ${_hex(data.sublist(vtableAddr, vtableAddr + 24))}');
  final vtableSize = bd.getUint16(vtableAddr, Endian.little);
  print('vtableSize = $vtableSize');
  final numFields = (vtableSize - 4) ~/ 2;
  print('numFields = $numFields');
  
  // Find the table that uses this vtable
  // vtableSOff should point from table to vtable
  // vtableSOff is at tableStart, as int32 (NEGATIVE)
  // So tableStart = vtableAddr - vtableSOff
  // We need to find where tableStart + vtableSOff = vtableAddr
  // => tableStart = vtableAddr - vtableSOff
  
  print('\nSearching for table that references this vtable...');
  for (var candidate = vtableAddr + vtableSize; candidate < vtableAddr + 200; candidate += 4) {
    if (candidate >= data.length) break;
    final vtableSOff = bd.getInt32(candidate, Endian.little);
    final computedVtable = candidate - vtableSOff;
    if (computedVtable == vtableAddr) {
      print('Found table at $candidate with vtableSOff=$vtableSOff');
      
      // Now extract entity name from field[3]
      final field3Off = bd.getUint16(vtableAddr + 4 + 3*2, Endian.little);
      print('field[3] offset = $field3Off');
      
      final nameFieldAddr = candidate + field3Off;
      final strOff = bd.getUint32(nameFieldAddr, Endian.little);
      final strAddr = nameFieldAddr + strOff;
      final strLen = bd.getUint32(strAddr, Endian.little);
      final name = String.fromCharCodes(data.sublist(strAddr + 4, strAddr + 4 + strLen));
      print('Entity name = "$name"');
      
      // Now get properties from field[4]
      final field4Off = bd.getUint16(vtableAddr + 4 + 4*2, Endian.little);
      print('\nfield[4] offset = $field4Off');
      
      final propsFieldAddr = candidate + field4Off;
      print('Props field address = $propsFieldAddr');
      
      // Read the vector
      // In FlatBuffers, a vector field contains a uoffset that points to the vector table
      // The vector table starts with u32 length, followed by u32 offsets to each element
      final vecOff = bd.getUint32(propsFieldAddr, Endian.little);
      print('Vector offset (from $propsFieldAddr) = $vecOff');
      
      final vecTable = propsFieldAddr + vecOff;
      print('Vector table address = $vecTable');
      
      if (vecTable + 4 <= data.length) {
        final numProps = bd.getUint32(vecTable, Endian.little);
        print('Number of properties = $numProps\n');
        
        // Read property details
        for (var i = 0; i < numProps && i < 12; i++) {
          final propOffAddr = vecTable + 4 + i * 4;
          if (propOffAddr + 4 > data.length) break;
          
          final propOff = bd.getUint32(propOffAddr, Endian.little);
          final propAddr = propOffAddr + propOff;
          
          print('Property[$i] at $propAddr:');
          print('  hex: ${_hex(data.sublist(propAddr, propAddr + 20))}');
          
          // Parse property vtable
          if (propAddr + 4 <= data.length) {
            final propVtableSOff = bd.getInt32(propAddr, Endian.little);
            print('  vtableSOff = $propVtableSOff');
            
            final propVtable = propAddr - propVtableSOff;
            print('  vtable at $propVtable');
            
            if (propVtable >= 0 && propVtable + 2 <= data.length) {
              final propVtableSize = bd.getUint16(propVtable, Endian.little);
              final propNumFields = (propVtableSize - 4) ~/ 2;
              print('  vtableSize = $propVtableSize, numFields = $propNumFields');
              
              // field[0] = name
              if (propNumFields > 0) {
                final propNameOff = bd.getUint16(propVtable + 4 + 0*2, Endian.little);
                if (propNameOff > 0) {
                  final propNameAddr = propAddr + propNameOff;
                  if (propNameAddr + 4 <= data.length) {
                    final pstrOff = bd.getUint32(propNameAddr, Endian.little);
                    final pstrAddr = propNameAddr + pstrOff;
                    if (pstrAddr + 4 <= data.length) {
                      final pstrLen = bd.getUint32(pstrAddr, Endian.little);
                      if (pstrLen > 0 && pstrLen < 100) {
                        final propName = String.fromCharCodes(data.sublist(pstrAddr + 4, pstrAddr + 4 + pstrLen));
                        print('  name = "$propName"');
                      }
                    }
                  }
                }
              }
              
              // field[1] = type
              if (propNumFields > 1) {
                final propTypeOff = bd.getUint16(propVtable + 4 + 1*2, Endian.little);
                if (propTypeOff > 0) {
                  final propTypeAddr = propAddr + propTypeOff;
                  if (propTypeAddr + 4 <= data.length) {
                    final propType = bd.getInt32(propTypeAddr, Endian.little);
                    print('  type = $propType');
                  }
                }
              }
            }
          }
          print('');
        }
      }
      
      break;
    }
  }
}

String _hex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
