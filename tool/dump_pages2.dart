// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

/// Dump first 32 bytes of each candidate page start (no assumption about format)
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  print('File size: ${raw.length}');

  // Try pageSize=4096: dump bytes at 16, 4112, 8208, 12304, 16400, 20496, 24592
  final ps = 4096;
  print('\n=== pageSize=$ps, dumping first 32 bytes of each page ===');
  for (var pgno = 0; pgno < 8; pgno++) {
    final off = 16 + pgno * ps;
    if (off + 32 > raw.length) break;
    final bd = ByteData.sublistView(raw, off);
    final magic = bd.getUint32(0, Endian.little);
    final flags = bd.getUint16(4, Endian.little);
    final lower = bd.getUint16(6, Endian.little);
    final upper = bd.getUint16(8, Endian.little);

    final b = <String>[];
    for (var j = 0; j < 32; j++) b.add(raw[off + j].toRadixString(16).padLeft(2, '0'));

    print('  Page $pgno (off=$off): magic=0x${magic.toRadixString(16)} '
          'flags=$flags lower=$lower upper=$upper');
    print('    ${b.sublist(0, 16).join(' ')}');
    print('    ${b.sublist(16, 32).join(' ')}');
  }

  // Also try pageSize=2048
  final ps2 = 2048;
  print('\n=== pageSize=$ps2, dumping first 32 bytes of each page ===');
  for (var pgno = 0; pgno < 12; pgno++) {
    final off = 16 + pgno * ps2;
    if (off + 32 > raw.length) break;
    final bd = ByteData.sublistView(raw, off);
    final m = bd.getUint32(0, Endian.little);
    final flags = bd.getUint16(4, Endian.little);
    final lower = bd.getUint16(6, Endian.little);

    final b = <String>[];
    for (var j = 0; j < 32; j++) b.add(raw[off + j].toRadixString(16).padLeft(2, '0'));

    print('  Page $pgno (off=$off): magic=0x${m.toRadixString(16)} '
          'flags=$flags lower=$lower');
    print('    ${b.sublist(0, 16).join(' ')}');
  }
}
