// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  final data = raw.sublist(16);  // Skip 16-byte prefix
  final bd = ByteData.sublistView(data);

  print('=== Debug: Property Parsing Issue ===\n');

  // Known values from previous debug
  const entityTable = 11708;
  const vtable = 11684;
  const vtableSize = 24;
  const numFields = 10;

  print('Entity table at $entityTable, vtable at $vtable');
  print('vtableSize=$vtableSize, numFields=$numFields\n');

  // Read field offsets from vtable
  print('Field offsets from vtable:');
  for (var fi = 0; fi < numFields; fi++) {
    final fieldOff = bd.getUint16(vtable + 4 + fi * 2, Endian.little);
    final fieldAddr = entityTable + fieldOff;
    print('  field[$fi]: offset=$fieldOff, addr=$fieldAddr');
  }

  // Get field[4] (properties)
  final field4Off = bd.getUint16(vtable + 4 + 4 * 2, Endian.little);
  final field4Addr = entityTable + field4Off;
  print('\nfield[4] (properties): offset=$field4Off, addr=$field4Addr');

  // Read what field[4] points to
  print('\nReading field[4] value at $field4Addr:');
  final vecOff = bd.getUint32(field4Addr, Endian.little);
  print('  uoffset32 = $vecOff (0x${vecOff.toRadixString(16)})');
  
  final vecTable = field4Addr + vecOff;
  print('  Vector table at $vecTable');
  
  // Read vector table header
  if (vecTable + 4 <= data.length) {
    final vecLen = bd.getUint32(vecTable, Endian.little);
    print('  Vector length (first u32) = $vecLen');
    
    // Check if this could be a vtable
    if (vecLen >= 8 && vecLen <= 128 && vecLen % 2 == 0) {
      print('  This looks like a vtable (size=$vecLen)');
      
      final innerNumFields = (vecLen - 4) ~/ 2;
      print('  Number of fields = $innerNumFields');
      
      // If this is a vtable, the actual vector data would be after it
      final actualVecData = vecTable + vecLen;
      print('\n  Trying actual vector data at $actualVecData:');
      
      if (actualVecData + 4 <= data.length) {
        final actualLen = bd.getUint32(actualVecData, Endian.little);
        print('  Length at $actualVecData = $actualLen');
        
        // Try reading offsets
        for (var i = 0; i < actualLen && i < 15; i++) {
          final offAddr = actualVecData + 4 + i * 4;
          if (offAddr + 4 > data.length) break;
          final off = bd.getUint32(offAddr, Endian.little);
          final propAddr = offAddr + off;
          print('  Property[$i]: offset=$off, addr=$propAddr');
        }
      }
    } else {
      // This is a regular vector - read element offsets
      print('\n  Reading as regular vector with $vecLen elements:');
      
      for (var i = 0; i < vecLen && i < 15; i++) {
        final offAddr = vecTable + 4 + i * 4;
        if (offAddr + 4 > data.length) break;
        final off = bd.getUint32(offAddr, Endian.little);
        final propAddr = offAddr + off;
        print('  Element[$i]: offset=$off, addr=$propAddr');
        
        // Try to parse property at propAddr
        if (propAddr + 4 <= data.length) {
          final propVtableSOff = bd.getInt32(propAddr, Endian.little);
          print('    vtableSOff = $propVtableSOff');
          
          if (propVtableSOff > 0) {
            final propVtable = propAddr - propVtableSOff;
            print('    vtable at $propVtable');
            
            if (propVtable + 2 <= data.length) {
              final propVtableSize = bd.getUint16(propVtable, Endian.little);
              print('    vtableSize = $propVtableSize');
              
              // Read property name from field[0]
              if (propVtableSize >= 8) {
                final propNameOff = bd.getUint16(propVtable + 4 + 0 * 2, Endian.little);
                print('    name field offset = $propNameOff');
                
                if (propNameOff > 0) {
                  final propNameAddr = propAddr + propNameOff;
                  if (propNameAddr + 4 <= data.length) {
                    final nameOff = bd.getUint32(propNameAddr, Endian.little);
                    final nameAddr = propNameAddr + nameOff;
                    if (nameAddr + 4 <= data.length) {
                      final nameLen = bd.getUint32(nameAddr, Endian.little);
                      if (nameLen > 0 && nameLen < 100) {
                        final name = String.fromCharCodes(data.sublist(nameAddr + 4, nameAddr + 4 + nameLen));
                        print('    name = "$name"');
                      }
                    }
                  }
                }
                
                // Read property type from field[1]
                final propTypeOff = bd.getUint16(propVtable + 4 + 1 * 2, Endian.little);
                if (propTypeOff > 0) {
                  final propTypeAddr = propAddr + propTypeOff;
                  if (propTypeAddr + 4 <= data.length) {
                    final propType = bd.getInt32(propTypeAddr, Endian.little);
                    print('    type = $propType');
                  }
                }
              }
            }
          }
        }
        print('');
      }
    }
  }

  // Also try: what if the vector IS inline after the length?
  print('\n=== Alternative: treating first u32 as length, data inline ===');
  print('If vector at $vecTable:');
  final firstWord = bd.getUint32(vecTable, Endian.little);
  print('  First word = $firstWord (could be element count)');
  
  // Check next 10 u32 values
  print('\n  Next 20 u32 values from $vecTable:');
  for (var i = 0; i < 20; i++) {
    final addr = vecTable + i * 4;
    if (addr + 4 > data.length) break;
    final val = bd.getUint32(addr, Endian.little);
    print('    [$i] at $addr: $val (0x${val.toRadixString(16).padLeft(8, '0')})');
  }
}
