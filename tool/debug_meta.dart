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

  print('Magic offset: $magicOffset');
  print('Page size: $pageSize');
  print('');

  // Read both meta pages (page 0 and page 1)
  for (var metaPgno in [0, 1]) {
    final off = metaPgno * pageSize;
    print('=== Meta Page $metaPgno (offset $off) ===');

    // Page header
    final pagePgno = bd.getUint64(off, Endian.little);
    final flags = bd.getUint16(off + 8, Endian.little);
    final type = bd.getUint16(off + 10, Endian.little);
    print('  pageHeader: pgno=$pagePgno, flags=$flags, type=$type');

    // MDB_meta starts after page header (16 bytes)
    final metaOff = off + 16;
    final magic = bd.getUint32(metaOff, Endian.little);
    final version = bd.getUint32(metaOff + 4, Endian.little);
    final address = bd.getUint64(metaOff + 8, Endian.little);
    final mapsize = bd.getUint64(metaOff + 16, Endian.little);
    print('  magic: 0x${magic.toRadixString(16)} (expected 0xBEEFC0DE)');
    print('  version: $version');
    print('  address: $address');
    print('  mapsize: $mapsize');

    // mm_dbs[0] - free DB
    final freeDbOff = metaOff + 24;
    _printDbInfo(bd, freeDbOff, 'freeDB');

    // mm_dbs[1] - main DB
    final mainDbOff = metaOff + 24 + 48;
    _printDbInfo(bd, mainDbOff, 'mainDB');

    // mm_last_pg
    final lastPgOff = metaOff + 24 + 48 + 48;
    final lastPg = bd.getUint64(lastPgOff, Endian.little);
    print('  lastPg: $lastPg');

    // mm_txnid
    final txnidOff = metaOff + 24 + 48 + 48 + 8;
    final txnid = bd.getUint64(txnidOff, Endian.little);
    print('  txnid: $txnid');

    print('');
  }
}

void _printDbInfo(ByteData bd, int off, String name) {
  final pad = bd.getUint32(off, Endian.little);
  final flags = bd.getUint16(off + 4, Endian.little);
  final depth = bd.getUint16(off + 6, Endian.little);
  final branchPages = bd.getUint64(off + 8, Endian.little);
  final leafPages = bd.getUint64(off + 16, Endian.little);
  final overflowPages = bd.getUint64(off + 24, Endian.little);
  final entries = bd.getUint64(off + 32, Endian.little);
  final root = bd.getUint64(off + 40, Endian.little);
  print(
    '  $name: pad=$pad, flags=$flags, depth=$depth, root=$root, entries=$entries, branch=$branchPages, leaf=$leafPages, overflow=$overflowPages',
  );
}
