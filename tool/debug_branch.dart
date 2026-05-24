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

  final pgno = 8;
  final off = pgno * pageSize;

  print('=== Page $pgno (Branch Page) ===');
  print('Header:');
  print('  pgno: ${bd.getUint64(off, Endian.little)}');
  print('  pad: ${bd.getUint16(off + 8, Endian.little)}');
  print('  flags: ${bd.getUint16(off + 10, Endian.little)}');
  print('  lower: ${bd.getUint16(off + 12, Endian.little)}');
  print('  upper: ${bd.getUint16(off + 14, Endian.little)}');

  final lower = bd.getUint16(off + 12, Endian.little);
  final numPtrs = (lower - 16) ~/ 2;
  print('  numPtrs: $numPtrs');

  for (var i = 0; i < numPtrs; i++) {
    final ptr = bd.getUint16(off + 16 + i * 2, Endian.little);
    print('  ptr[$i]: $ptr');
  }

  // Print entries
  print('');
  final ptrs = [16360, 16376];
  ptrs.sort();
  for (var i = 0; i < ptrs.length; i++) {
    final entryStart = ptrs[i];
    final entryEnd = (i + 1 < ptrs.length) ? ptrs[i + 1] : pageSize;
    final entryLen = entryEnd - entryStart;
    print('Entry at offset $entryStart, len=$entryLen:');
    if (entryLen > 0) {
      final abs = off + entryStart;
      final hex = bytes
          .sublist(abs, abs + entryLen)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      print('  $hex');
      // Try to find child pgno (last 8 bytes)
      if (entryLen >= 8) {
        final pgno1 = bd.getUint64(abs + entryLen - 8, Endian.little);
        final pgno2 = bd.getUint32(abs + entryLen - 4, Endian.little);
        print('  Possible child pgno (uint64 at end): $pgno1');
        print('  Possible child pgno (uint32 at end): $pgno2');
      }
    }
  }

  // Dump the raw content of the page
  print('');
  print('Raw page content (last 64 bytes):');
  for (var i = pageSize - 64; i < pageSize; i += 16) {
    final hex = bytes
        .sublist(off + i, off + i + 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final ascii = bytes
        .sublist(off + i, off + i + 16)
        .map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '.')
        .join('');
    print('${(off + i).toString().padLeft(6)}: $hex  $ascii');
  }
}
