// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

void main() async {
  final dbPath = r'D:\jack\db';
  final dataFile = File(p.join(dbPath, 'data.mdb'));
  final rawBytes = await dataFile.readAsBytes();

  var start = 0;
  if (rawBytes.length >= 16 &&
      ByteData.sublistView(rawBytes, 16).getUint32(0, Endian.little) == 0xBEEFC0DE) {
    start = 16;
  }
  final data = rawBytes.sublist(start);
  final bd = ByteData.sublistView(data);

  final pageSize = bd.getUint32(24, Endian.little);
  final numPages = data.length ~/ pageSize;

  print('Checking page 5 (last one)\n');

  final pgno = 5;
  final off = pgno * pageSize;
  final lower = bd.getUint16(off + 6, Endian.little);
  print('Page $pgno: lower=$lower');

  final numPtrs = (lower - 12) ~/ 2;
  final ptrs = <int>[];
  for (var i = 0; i < numPtrs && i < 500; i++) {
    final ptr = bd.getUint16(off + 12 + i * 2, Endian.little);
    if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
  }
  ptrs.sort();

  print('Pointer count: ${ptrs.length}');
  print('Pointers: $ptrs\n');

  for (var i = 0; i < ptrs.length; i++) {
    final entryStart = ptrs[i];
    final entryLen = (i + 1 < ptrs.length ? ptrs[i + 1] : pageSize) - entryStart;
    final absEntry = off + entryStart;

    print('Entry $i at entryStart=$entryStart len=$entryLen absEntry=$absEntry');

    // Check bytes 8-14
    var allZero = true;
    for (var j = 8; j <= 14; j++) {
      if (data[absEntry + j] != 0) { allZero = false; break; }
    }
    print('  bytes8-14 all zero: $allZero');

    final entityId = data[absEntry + 15];
    print('  entityId: $entityId');

    final valLen = entryLen - 16;
    print('  valLen: $valLen');

    if (valLen >= 4) {
      final rootOff = bd.getUint32(absEntry + 16, Endian.little);
      print('  rootOff: $rootOff');

      if (entityId == 0 && rootOff > 0 && rootOff < valLen && allZero) {
        print('  >>> IS SCHEMA <<<');

        // Try parse entity
        final valStart = absEntry + 16;
        final tableStart = valStart + rootOff;
        final vtableSOff = bd.getInt32(tableStart, Endian.little);
        print('  vtableSOff: $vtableSOff');

        if (vtableSOff > 0) {
          final vtableStart = tableStart - vtableSOff;
          final vtableSize = bd.getUint16(vtableStart, Endian.little);
          print('  vtableSize: $vtableSize');

          if (vtableSize >= 4 && vtableSize <= 256) {
            final numFields = (vtableSize - 4) ~/ 2;
            print('  numFields: $numFields');

            // Try field[3] (name)
            if (numFields > 3) {
              final nameFieldOff = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
              print('  nameFieldOff: $nameFieldOff');

              if (nameFieldOff > 0) {
                final nameAddr = tableStart + nameFieldOff;
                print('  nameAddr: $nameAddr');

                if (nameAddr + 4 < data.length) {
                  final strOff = bd.getUint32(nameAddr, Endian.little);
                  print('  strOff: $strOff');

                  if (strOff > 0) {
                    final strAddr = nameAddr + strOff;
                    print('  strAddr: $strAddr');

                    if (strAddr + 4 < data.length) {
                      final strLen = bd.getUint32(strAddr, Endian.little);
                      print('  strLen: $strLen');

                      if (strLen > 0 && strLen < 100 && strAddr + 4 + strLen < data.length) {
                        final name = String.fromCharCodes(data.sublist(strAddr + 4, strAddr + 4 + strLen));
                        print('  >>> NAME: "$name" <<<');
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
    print('');
  }
}