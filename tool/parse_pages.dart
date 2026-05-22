// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Properly parse LMDB pages and extract entries.
/// The file has a 16-byte prefix; LMDB data starts at offset 16.
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  print('File size: ${raw.length}');

  // Slice from offset 16
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);
  print('Sliced data size: ${data.length}');

  // Read page size from LMDB header (offset 24 of sliced = offset 40 of original)
  final pageSize = bd.getUint32(24, Endian.little);
  print('pageSize=$pageSize (0x${pageSize.toRadixString(16)})');
  if (pageSize < 512 || pageSize > 65536) {
    print('ERROR: invalid pageSize');
    exit(1);
  }

  final numPages = data.length ~/ pageSize;
  print('numPages=$numPages\n');

  // Parse each page
  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 12 > data.length) break;

    final magic = bd.getUint32(off, Endian.little);
    final flags = bd.getUint16(off + 4, Endian.little);
    final lower = bd.getUint16(off + 6, Endian.little); // mp_lower
    final upper = bd.getUint16(off + 8, Endian.little); // mp_upper

    // Number of entries = (mp_lower - 12) / 2
    final numEntries = (lower >= 12) ? ((lower - 12) ~/ 2) : 0;

    print('Page $pgno: off=$off magic=0x${magic.toRadixString(16)} '
          'flags=$flags lower=$lower upper=$upper entries=$numEntries');

    if (numEntries > 0 && numEntries < 500) {
      // Read entry pointers
      final ptrs = <int>[];
      for (var i = 0; i < numEntries; i++) {
        final ptr = bd.getUint16(off + 12 + i * 2, Endian.little);
        if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
      }
      ptrs.sort();

      for (var i = 0; i < ptrs.length && i < 5; i++) {
        final ptr = ptrs[i];
        final entryOff = off + ptr;
        if (entryOff + 16 > data.length) continue;

        // LMDB entry: 8-byte key + 2-byte data size + data
        final key = bd.getUint64(entryOff, Endian.little);
        final valSize = bd.getUint16(entryOff + 8, Endian.little);
        final entityId = data[entryOff + 15];

        print('  [$i] ptr=$ptr key=$key entityId=$entityId valSize=$valSize');
      }
      if (ptrs.length > 5) print('  ... and ${ptrs.length - 5} more');
    }
  }
}
