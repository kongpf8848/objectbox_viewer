// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Check both field[3] and field[4] to find properties vector.
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);

  final tableStart = 11708;
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  final vtableStart = tableStart - vtableSOff;
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;

  print('Entity: tableStart=$tableStart vtableStart=$vtableStart');
  print('vtableSize=$vtableSize numFields=$numFields\n');

  // Check each field for vectors
  for (var f = 0; f < numFields; f++) {
    final fOff = bd.getUint16(vtableStart + 4 + f * 2, Endian.little);
    if (fOff == 0) {
      print('field[$f]: inline/empty');
      continue;
    }

    final fAddr = tableStart + fOff;
    if (fAddr + 4 > data.length) {
      print('field[$f]: addr=$fAddr OOB');
      continue;
    }

    // Check if it's a vector (starts with small length < 100)
    final val = bd.getUint32(fAddr, Endian.little);
    if (val > 0 && val < 100) {
      // Could be vector length
      print('field[$f]: offset=$fOff addr=$fAddr len=$val (vector?)');

      // Try to parse as FlatBuffers vector
      final vecAddr = fAddr + 4; // offset after length
      if (vecAddr + 4 < data.length) {
        final firstElemOff = bd.getUint32(vecAddr, Endian.little);
        if (firstElemOff < 100) {
          final elemAddr = vecAddr + firstElemOff;
          print('  First element at $elemAddr (offset=$firstElemOff)');

          if (elemAddr + 4 < data.length) {
            final elemVtableSOff = bd.getInt32(elemAddr, Endian.little);
            print('  vtableSOff=$elemVtableSOff');
            if (elemVtableSOff > 0 && elemVtableSOff < 1000) {
              final elemVtableStart = elemAddr - elemVtableSOff;
              if (elemVtableStart > 0 && elemVtableStart + 4 < data.length) {
                final elemVtableSize = bd.getUint16(elemVtableStart, Endian.little);
                print('  elem vtableSize=$elemVtableSize');
                final elemNumFields = (elemVtableSize - 4) ~/ 2;
                print('  elem numFields=$elemNumFields');

                // Show field[1] and field[2] (name and type)
                if (elemNumFields > 1) {
                  final nameOff = bd.getUint16(elemVtableStart + 4 + 1 * 2, Endian.little);
                  if (nameOff > 0) {
                    final nameAddr = elemAddr + nameOff;
                    final strOff = bd.getUint32(nameAddr, Endian.little);
                    if (strOff > 0) {
                      final strAddr = nameAddr + strOff;
                      if (strAddr + 4 < data.length) {
                        final strLen = bd.getUint32(strAddr, Endian.little);
                        if (strLen > 0 && strLen < 100) {
                          final name = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
                              allowMalformed: true);
                          final typeOff = elemNumFields > 2
                              ? bd.getUint16(elemVtableStart + 4 + 2 * 2, Endian.little)
                              : 0;
                          var type = 0;
                          if (typeOff > 0) {
                            type = bd.getInt32(elemAddr + typeOff, Endian.little);
                          }
                          print('  → PROP: "$name" type=$type');
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
    } else {
      print('field[$f]: offset=$fOff addr=$fAddr val=$val');
    }
  }
}
