// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

void main() async {
  final dbPath = r'D:\jack\db';
  final dataFile = File(p.join(dbPath, 'data.mdb'));
  final rawBytes = await dataFile.readAsBytes();
  print('File size: ${rawBytes.length}');

  // Slice 16-byte prefix
  var start = 0;
  if (rawBytes.length >= 16 &&
      ByteData.sublistView(rawBytes, 16).getUint32(0, Endian.little) == 0xBEEFC0DE) {
    start = 16;
  }
  final data = rawBytes.sublist(start);
  final bd = ByteData.sublistView(data);
  print('Sliced data size: ${data.length}');

  // Check magic
  final magic = bd.getUint32(0, Endian.little);
  print('Magic: 0x${magic.toRadixString(16)} (expected 0xbeefc0de)');

  // Page size
  final pageSize = bd.getUint32(24, Endian.little);
  print('Page size: $pageSize');

  if (pageSize < 512 || pageSize > 65536) {
    print('ERROR: bad pageSize');
    return;
  }

  final numPages = data.length ~/ pageSize;
  print('Num pages: $numPages\n');

  // Read pages
  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 12 > data.length) break;

    final lower = bd.getUint16(off + 6, Endian.little);
    print('Page $pgno: lower=$lower');

    if (lower < 12 || lower > pageSize) continue;

    final numPtrs = (lower - 12) ~/ 2;
    print('  numPtrs=$numPtrs');

    if (numPtrs <= 0) continue;

    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = bd.getUint16(off + 12 + i * 2, Endian.little);
      // Debug first 5 pointers
      if (i < 5) print('    ptr[$i]=$ptr');
      if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
    }
    ptrs.sort();

    print('  unique ptrs: ${ptrs.length}');

    // Check first few entries
    for (var i = 0; i < ptrs.length && i < 3; i++) {
      final entryStart = ptrs[i];
      final entryLen = (i + 1 < ptrs.length ? ptrs[i + 1] : pageSize) - entryStart;
      final absEntry = off + entryStart;

      // Check isSchema
      var isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (data[absEntry + j] != 0) { isSchema = false; break; }
      }
      if (data[absEntry + 15] != 0) isSchema = false;
      final valLen = entryLen - 16;
      if (valLen < 4) isSchema = false;
      final rootOff = valLen >= 4 ? bd.getUint32(absEntry + 16, Endian.little) : 0;
      if (rootOff == 0 || rootOff >= valLen) isSchema = false;

      if (isSchema) {
        print('  Entry $i: abs=$absEntry len=$entryLen IS_SCHEMA');
        // Try to parse entity name
        final valStart = absEntry + 16;
        if (rootOff > 0 && rootOff < valLen) {
          final tableStart = valStart + rootOff;
          final vtableSOff = bd.getInt32(tableStart, Endian.little);
          if (vtableSOff > 0) {
            final vtableStart = tableStart - vtableSOff;
            final vtableSize = bd.getUint16(vtableStart, Endian.little);
            final numFields = (vtableSize - 4) ~/ 2;
            print('    vtableSize=$vtableSize numFields=$numFields');

            // field[3] = name
            if (numFields > 3) {
              final nameFieldOff = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
              if (nameFieldOff > 0) {
                final nameAddr = tableStart + nameFieldOff;
                final strOff = bd.getUint32(nameAddr, Endian.little);
                if (strOff > 0) {
                  final strAddr = nameAddr + strOff;
                  if (strAddr + 4 < data.length) {
                    final strLen = bd.getUint32(strAddr, Endian.little);
                    if (strLen > 0 && strLen < 100 && strAddr + 4 + strLen < data.length) {
                      final name = String.fromCharCodes(data.sublist(strAddr + 4, strAddr + 4 + strLen));
                      print('    ENTITY: "$name"');
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
