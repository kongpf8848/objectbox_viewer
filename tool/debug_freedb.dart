import 'dart:io';
import 'dart:typed_data';

void main() {
  final path = '/Users/kongpengfei/Documents/data.mdb';
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);

  var magicOffset = 0;
  if (bytes.length >= 20 && bd.getUint32(16, Endian.little) == 0xBEEFC0DE) {
    magicOffset = 16;
  }

  final pageSizeOffset = magicOffset == 16 ? 40 : 24;
  var pageSize = bytes.length > pageSizeOffset + 4
      ? bd.getUint32(pageSizeOffset, Endian.little)
      : 4096;
  if (pageSize < 512 || pageSize > 65536) pageSize = 4096;

  // Read meta page 0 (active)
  final metaOff = 0 + 16;
  final mainDbOff = metaOff + 24 + 48;
  final mainRoot = bd.getUint64(mainDbOff + 40, Endian.little);
  final mainEntries = bd.getUint64(mainDbOff + 32, Endian.little);

  final freeDbOff = metaOff + 24;
  final freeRoot = bd.getUint64(freeDbOff + 40, Endian.little);
  final freeEntries = bd.getUint64(freeDbOff + 32, Endian.little);

  print('mainDB: root=$mainRoot, entries=$mainEntries');
  print('freeDB: root=$freeRoot, entries=$freeEntries');
  print('');

  // Parse freeDB pages to find which pages are free
  final freedPages = <int>[];

  // freeDB root=9, let's read page 9
  for (var pgno in [9, 7, 6]) {
    final off = pgno * pageSize;
    if (off + 16 > bytes.length) continue;

    final pagePgno = bd.getUint64(off, Endian.little);
    final flags = bd.getUint16(off + 8, Endian.little);
    final type = bd.getUint16(off + 10, Endian.little);
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 16 || lower > pageSize) continue;

    final numPtrs = (lower - 16) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = bd.getUint16(off + 16 + i * 2, Endian.little);
      if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
    }
    if (ptrs.isEmpty) continue;
    ptrs.sort();
    final uniquePtrs = <int>[ptrs.first];
    for (var i = 1; i < ptrs.length; i++) {
      if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
    }

    print('=== Page $pgno (freeDB?) ===');
    print('  headerPgno=$pagePgno, flags=$flags, type=$type');

    for (var i = 0; i < uniquePtrs.length; i++) {
      final entryStart = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length)
          ? uniquePtrs[i + 1]
          : pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;

      final absEntry = off + entryStart;
      final keyHex = bytes
          .sublist(absEntry, absEntry + 16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final valLen = entryLen - 16;
      final valStart = absEntry + 16;

      print('  entry offset=$entryStart, len=$entryLen');
      print('    key: $keyHex');
      print('    value len=$valLen');

      // Parse value as list of page numbers (uint64 array)
      if (valLen >= 8) {
        final numPgnos = valLen ~/ 8;
        final pgnos = <int>[];
        for (var j = 0; j < numPgnos; j++) {
          final pg = bd.getUint64(valStart + j * 8, Endian.little);
          pgnos.add(pg);
          freedPages.add(pg);
        }
        print('    pages: $pgnos');
      } else if (valLen >= 4) {
        // Try uint32
        final numPgnos = valLen ~/ 4;
        final pgnos = <int>[];
        for (var j = 0; j < numPgnos; j++) {
          final pg = bd.getUint32(valStart + j * 4, Endian.little);
          pgnos.add(pg);
          freedPages.add(pg);
        }
        print('    pages (uint32): $pgnos');
      }
    }
    print('');
  }

  print('All freed pages: ${freedPages.toSet().toList()..sort()}');
}
