// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Detailed Property parsing to find all fields.
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);

  // TodoEntity's first property is at:
  // tableStart=11708, field[3] is a vector of 10 properties
  final tableStart = 11708;
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  final vtableStart = tableStart - vtableSOff;
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;

  print('Entity vtableSize=$vtableSize numFields=$numFields');

  // field[3] is properties vector
  final propsFieldOff = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
  final propsAddr = tableStart + propsFieldOff;
  final vecOff = bd.getUint32(propsAddr, Endian.little);
  final vecAddr = propsAddr + vecOff;
  final vecLen = bd.getUint32(vecAddr, Endian.little);
  print('Properties vector: length=$vecLen');

  // Parse first property
  if (vecLen > 0) {
    final elemOffAddr = vecAddr + 4;
    final elemRelOff = bd.getUint32(elemOffAddr, Endian.little);
    // elemRelOff is RELATIVE to elemOffAddr, not absolute!
    final propAddr = elemOffAddr + elemRelOff;
    print('\nFirst property at relOffset=$elemRelOff -> addr=$propAddr:');

    final propVtableSOff = bd.getInt32(propAddr, Endian.little);
    final propVtableStart = propAddr - propVtableSOff;
    final propVtableSize = bd.getUint16(propVtableStart, Endian.little);
    final propNumFields = (propVtableSize - 4) ~/ 2;
    print('  vtableSize=$propVtableSize numFields=$propNumFields');

    // Dump ALL fields of the property
    for (var f = 0; f < propNumFields; f++) {
      final fOff = bd.getUint16(propVtableStart + 4 + f * 2, Endian.little);
      if (fOff == 0) {
        print('  field[$f]: offset=0 (empty)');
        continue;
      }
      final fAddr = propAddr + fOff;
      if (fAddr + 4 > data.length) {
        print('  field[$f]: addr=$fAddr out of bounds');
        continue;
      }

      // Try to interpret as different types
      final fVal = bd.getUint32(fAddr, Endian.little);
      final fValS = bd.getInt32(fAddr, Endian.little);

      // Check if it's a string (starts with length)
      String? strVal;
      if (fVal > 4 && fVal < 1000) {
        final strAddr = fAddr + fVal;
        if (strAddr + 4 <= data.length) {
          final strLen = bd.getUint32(strAddr, Endian.little);
          if (strLen > 0 && strLen < 1000 && strAddr + 4 + strLen <= data.length) {
            strVal = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
                allowMalformed: true);
          }
        }
      }

      print('  field[$f]: offset=$fOff value=$fVal (signed=$fValS)${strVal != null ? ' string="$strVal"' : ''}');
    }
  }
}
