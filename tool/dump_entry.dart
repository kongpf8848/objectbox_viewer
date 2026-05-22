// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Dump raw bytes of a specific entry to debug parsing.
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();

  // Slice from offset 16
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);
  print('Sliced data size: ${data.length}');

  // Dump entry at abs=8268
  final absEntry = 8268;
  final entryLen = 200; // guess
  print('\n=== Dumping entry at abs=$absEntry (len=$entryLen) ===');
  for (var i = 0; i < entryLen; i += 16) {
    final b = <String>[];
    for (var j = 0; j < 16 && absEntry + i + j < data.length; j++) {
      b.add(data[absEntry + i + j].toRadixString(16).padLeft(2, '0'));
    }
    print('  ${(absEntry + i).toRadixString(16).padLeft(8, '0')}:  ${b.join(' ')}');
  }

  // Try to parse as schema entry
  final valStart = absEntry + 16;
  final valLen = entryLen - 16;
  print('\nvalStart=$valStart valLen=$valLen');

  final rootOff = bd.getUint32(valStart, Endian.little);
  print('rootOff=$rootOff (0x${rootOff.toRadixString(16)})');

  if (rootOff > 0 && rootOff < valLen) {
    final tableStart = valStart + rootOff;
    print('tableStart=abs $tableStart');

    final vtableSOff = bd.getInt32(tableStart, Endian.little);
    print('vtableSOff=$vtableSOff');

    if (vtableSOff > 0) {
      final vtableStart = tableStart - vtableSOff;
      print('vtableStart=abs $vtableStart');
      final vtableSize = bd.getUint16(vtableStart, Endian.little);
      print('vtableSize=$vtableSize');
      final numFields = (vtableSize - 4) ~/ 2;
      print('numFields=$numFields');

      // Try to read field[3] = name
      if (numFields > 3) {
        final nameFieldOff = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
        print('nameFieldOff=$nameFieldOff');
        if (nameFieldOff > 0) {
          final nameAddr = tableStart + nameFieldOff;
          final strOff = bd.getUint32(nameAddr, Endian.little);
          print('nameAddr=abs $nameAddr strOff=$strOff');
          if (strOff > 0) {
            final strAddr = nameAddr + strOff;
            print('strAddr=abs $strAddr');
            if (strAddr + 4 < data.length) {
              final strLen = bd.getUint32(strAddr, Endian.little);
              print('strLen=$strLen');
              if (strLen > 0 && strLen < 1000) {
                final name = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
                    allowMalformed: true);
                print('ENTITY NAME: "$name"');
              }
            }
          }
        }
      }
    }
  }
}
