// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);

  print('=== Extracting All 7 Properties ===\n');

  // Property addresses from debug
  final propAddrs = [12212, 12132, 12052, 11996, 11916, 11860, 11796];

  for (var i = 0; i < propAddrs.length; i++) {
    final propAddr = propAddrs[i];
    print('Property[$i] at $propAddr:');
    
    // Read vtable offset (SOffice is relative from table to vtable)
    final vtableSOff = bd.getInt32(propAddr, Endian.little);
    print('  vtableSOff = $vtableSOff');
    
    // In standard FlatBuffers, vtable is BEFORE the table, so vtableSOff is negative
    // vtableStart = tableStart - vtableSOff
    final vtable = propAddr - vtableSOff;
    print('  vtable at $vtable');
    
    if (vtable < 0 || vtable + 2 > data.length) {
      print('  Skipping - invalid vtable address');
      continue;
    }
    
    final vtableSize = bd.getUint16(vtable, Endian.little);
    print('  vtableSize = $vtableSize');
    
    if (vtableSize < 8 || vtableSize > 128) {
      print('  Skipping - invalid vtable size');
      continue;
    }
    
    final numFields = (vtableSize - 4) ~/ 2;
    print('  numFields = $numFields');
    
    // Read field[0] = name
    if (numFields > 0) {
      final nameOff = bd.getUint16(vtable + 4 + 0 * 2, Endian.little);
      if (nameOff > 0) {
        final nameFieldAddr = propAddr + nameOff;
        if (nameFieldAddr + 4 <= data.length) {
          final strOff = bd.getUint32(nameFieldAddr, Endian.little);
          final strAddr = nameFieldAddr + strOff;
          if (strAddr + 4 <= data.length) {
            final strLen = bd.getUint32(strAddr, Endian.little);
            if (strLen > 0 && strLen < 100) {
              final name = String.fromCharCodes(
                data.sublist(strAddr + 4, strAddr + 4 + strLen)
              );
              print('  name = "$name"');
            }
          }
        }
      }
    }
    
    // Read field[1] = type
    if (numFields > 1) {
      final typeOff = bd.getUint16(vtable + 4 + 1 * 2, Endian.little);
      if (typeOff > 0) {
        final typeFieldAddr = propAddr + typeOff;
        if (typeFieldAddr + 4 <= data.length) {
          final type = bd.getInt32(typeFieldAddr, Endian.little);
          print('  type = $type (${_obxTypeName(type)})');
        }
      }
    }
    
    // Read field[2] = flags
    if (numFields > 2) {
      final flagsOff = bd.getUint16(vtable + 4 + 2 * 2, Endian.little);
      if (flagsOff > 0) {
        final flagsFieldAddr = propAddr + flagsOff;
        if (flagsFieldAddr + 4 <= data.length) {
          final flags = bd.getInt32(flagsFieldAddr, Endian.little);
          print('  flags = $flags');
        }
      }
    }
    
    print('');
  }
}

String _obxTypeName(int type) {
  switch (type) {
    case 1: return 'bool';
    case 2: return 'byte';
    case 3: return 'short';
    case 4: return 'int';
    case 5: return 'long';
    case 6: return 'float';
    case 7: return 'double';
    case 8: return 'date';
    case 9: return 'string';
    case 10: return 'bytes';
    case 27: return 'string';
    case 28: return 'int';
    case 32: return 'date-nano';
    default: return 'unknown($type)';
  }
}
