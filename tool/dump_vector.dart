// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Dump raw bytes around properties vector to understand structure.
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);

  // Same structure parsing as before
  final tableStart = 11708;
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  final vtableStart = tableStart - vtableSOff;
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;

  // Get field[3] offset
  final propsFieldOff = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
  final propsAddr = tableStart + propsFieldOff;

  print('tableStart=$tableStart vtableStart=$vtableStart');
  print('propsFieldOff=$propsFieldOff propsAddr=$propsAddr');

  // The vector starts with length (uint32) at propsAddr
  final vecLen = bd.getUint32(propsAddr, Endian.little);
  print('Expected vector length: $vecLen');

  // Check bytes after length: is it inline data or offset?
  // For offset vectors, bytes 4-7 are offset to first element
  final afterLen = bd.getUint32(propsAddr + 4, Endian.little);
  print('After length: $afterLen (maybe offset to first element)');

  // Try treating as offset vector
  if (afterLen < 4096) {
    final firstElemAddr = propsAddr + 4 + afterLen;
    print('firstElemAddr (if offset vector) = $firstElemAddr');

    if (firstElemAddr + 4 < data.length) {
      final elemVtableSOff = bd.getInt32(firstElemAddr, Endian.little);
      print('  first element vtableSOff=$elemVtableSOff');

      final elemVtableStart = elemVtableSOff > 0
          ? firstElemAddr - elemVtableSOff
          : firstElemAddr - elemVtableSOff;
      print('  elemVtableStart=$elemVtableStart');

      if (elemVtableStart > 0 && elemVtableStart + 2 < data.length) {
        final elemVtableSize = bd.getUint16(elemVtableStart, Endian.little);
        print('  elemVtableSize=$elemVtableSize');
        final elemNumFields = (elemVtableSize - 4) ~/ 2;
        print('  elemNumFields=$elemNumFields');

        // Show up to 5 fields
        for (var f = 0; f < elemNumFields && f < 5; f++) {
          final fOff = bd.getUint16(elemVtableStart + 4 + f * 2, Endian.little);
          if (fOff == 0) {
            print('  field[$f]: <inline or 0>');
            continue;
          }
          final fAddr = firstElemAddr + fOff;
          if (fAddr + 4 > data.length) break;

          final fVal = bd.getUint32(fAddr, Endian.little);

          // String if length prefix
          String? str;
          if (fVal > 4 && fVal < 1000) {
            final strAddr = fAddr + fVal;
            if (strAddr + 4 <= data.length) {
              final strLen = bd.getUint32(strAddr, Endian.little);
              if (strLen > 0 && strLen < 100 && strAddr + 4 + strLen <= data.length) {
                str = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
                    allowMalformed: true);
              }
            }
          }

          if (str != null) {
            print('  field[$f]: "$str"');
          } else if (fOff < 32) {
            print('  field[$f]: offset=$fOff val=$fVal');
          } else {
            print('  field[$f]: offset=$fOff (maybe inline)');
          }
        }
      }
    }
  }
}