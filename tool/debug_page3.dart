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

  // Check page 3 specifically (known from earlier to contain schema)
  for (var pgno = 3; pgno <= 3; pgno++) {
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

    print('  Pointers: $ptrs\n');

    for (var i = 0; i < ptrs.length; i++) {
      final entryStart = ptrs[i];
      final entryLen = (i + 1 < ptrs.length ? ptrs[i + 1] : pageSize) - entryStart;
      final absEntry = off + entryStart;

      print('Entry $i: entryStart=$entryStart len=$entryLen absEntry=$absEntry');

      // Check bytes 8-14
      final byteVals = <int>[];
      for (var j = 8; j <= 14; j++) byteVals.add(data[absEntry + j]);
      print('  bytes8-14: $byteVals');

      var allZero = byteVals.every((b) => b == 0);
      print('  allZero: $allZero');

      final entityId = data[absEntry + 15];
      final valLen = entryLen - 16;

      if (valLen >= 4) {
        final rootOff = bd.getUint32(absEntry + 16, Endian.little);
        print('  rootOff=$rootOff (valLen=$valLen)');
        
        // Schema check: entityId=0, rootOff in range, bytes 8-14 zero
        if (entityId == 0 && rootOff > 0 && rootOff < valLen && allZero) {
          print('  >>> IS SCHEMA <<<');
          
          // Parse entity name
          final tableStart = absEntry + 16 + rootOff;
          final vtableSOff = bd.getInt32(tableStart, Endian.little);
          print('  vtableSOff=$vtableSOff tableStart=$tableStart');

          if (vtableSOff > 0 && vtableSOff < 100) {
            final vtableTop = tableStart - vtableSOff;
            final vtableSize = bd.getUint16(vtableTop, Endian.little);
            final numFields = (vtableSize - 4) ~/ 2;
            print('  vtableSize=$vtableSize numFields=$numFields');

            // Try field 3
            if (numFields > 3) {
              final f3off = bd.getUint16(vtableTop + 4 + 3 * 2, Endian.little);
              print('  f3@$f3off');

              if (f3off > 0) {
                final f3addr = tableStart + f3off;
                if (f3addr + 4 < data.length) {
                  final f3 = bd.getUint32(f3addr, Endian.little);
                  print('  f3 val: $f3');

                  if (f3 > 0 && f3 < 100) {
                    final saddr = f3addr + f3;
                    if (saddr + 4 < data.length) {
                      final slen = bd.getUint32(saddr, Endian.little);
                      print('  str len: $slen');

                      if (slen > 0 && slen < 100 && saddr + 4 + slen <= data.length) {
                        final name = String.fromCharCodes(data.sublist(saddr + 4, saddr + 4 + slen));
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
      print('');
    }
  }
}