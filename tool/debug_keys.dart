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
  final numPages = bytes.length ~/ pageSize;

  print('Page size: $pageSize, numPages: $numPages');
  print('');

  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 16 > bytes.length) continue;
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

    var hasPrintedPage = false;
    for (var i = 0; i < uniquePtrs.length; i++) {
      final entryStart = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length)
          ? uniquePtrs[i + 1]
          : pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;

      final absEntry = off + entryStart;

      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) {
          isSchema = false;
          break;
        }
      }

      if (isSchema) continue;

      if (!hasPrintedPage) {
        print('--- Page $pgno ---');
        hasPrintedPage = true;
      }

      // Print key bytes
      final keyBytes = bytes.sublist(absEntry, absEntry + 16);
      final hex = keyBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');

      final entityIdAt15 = bytes[absEntry + 15];
      final objId32 = bd.getUint32(absEntry, Endian.little);
      final objId48 =
          bd.getUint16(absEntry + 2, Endian.little) |
          (bd.getUint32(absEntry + 4, Endian.little) << 16);
      final objId64 = bd.getUint64(absEntry, Endian.little);
      final objIdAt2 = bd.getUint32(absEntry + 2, Endian.little);
      final objIdAt2_64 = bd.getUint64(absEntry + 2, Endian.little);
      final objIdAt4 = bd.getUint32(absEntry + 4, Endian.little);
      final objIdAt6 = bd.getUint16(absEntry + 6, Endian.little);

      print('Entry off=$entryStart len=$entryLen');
      print('  Key hex: $hex');
      print('  entityId@15=$entityIdAt15');
      print(
        '  objId32@0=$objId32 objId32@2=$objIdAt2 objId32@4=$objIdAt4 objId16@6=$objIdAt6',
      );
      print('  objId48=$objId48 objId64@0=$objId64 objId64@2=$objIdAt2_64');
      print('');
    }
  }
}
