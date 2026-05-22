// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

/// Debug: print LMDB page headers for all pages
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final rawBytes = await file.readAsBytes();
  print('File size: ${rawBytes.length}');

  // Slice from offset 16 (16-byte prefix)
  final data = rawBytes.sublist(16);
  final bd = ByteData.sublistView(data);
  final pageSize = bd.getUint32(24, Endian.little);
  print('pageSize=$pageSize');

  final numPages = data.length ~/ pageSize;
  print('numPages=$numPages\n');

  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 14 > data.length) break;

    final magic = bd.getUint32(off, Endian.little);
    final flags = bd.getUint16(off + 4, Endian.little);
    final lower = bd.getUint16(off + 12, Endian.little);  // mp_lower
    final upper = bd.getUint16(off + 10, Endian.little);  // mp_upper (wait, need to check)
    
    // Actually, let me re-check the LMDB page header format
    // From mdb.c:
    // #define MDB_MAGIC       0xBEEFC0DE
    // typedef struct MDB_page {
    //     uint32_t    mp_magic;       /* Offset 0 */
    //     uint16_t    mp_flags;       /* Offset 4 */
    //     uint16_t    mp_lower;       /* Offset 6 */
    //     uint16_t    mp_upper;       /* Offset 8 */
    //     uint16_t    mp_pages;       /* Offset 10 */
    //     /* uint16_t    mp_ptrs[];  /* Offset 12+ */
    // } MDB_page;
    
    final mp_flags = bd.getUint16(off + 4, Endian.little);
    final mp_lower = bd.getUint16(off + 6, Endian.little);
    final mp_upper = bd.getUint16(off + 8, Endian.little);
    final mp_pages = bd.getUint16(off + 10, Endian.little);
    
    print('Page $pgno: off=$off magic=0x${magic.toRadixString(16)} '
          'flags=$mp_flags lower=$mp_lower upper=$mp_upper pages=$mp_pages');
    
    if (magic != 0xBEEFC0DE && pgno > 0) {
      print('  WARNING: invalid magic for page $pgno');
    }
    
    if (pgno == 0) {
      // Print first 64 bytes of page 0
      print('  Page 0 header bytes:');
      for (var i = 0; i < 64 && off + i < data.length; i += 16) {
        final b = <String>[];
        for (var j = 0; j < 16 && off + i + j < data.length; j++) {
          b.add(data[off + i + j].toRadixString(16).padLeft(2, '0'));
        }
        print('    ${(off + i).toRadixString(16).padLeft(8, '0')}:  ${b.join(' ')}');
      }
    }
  }
}
