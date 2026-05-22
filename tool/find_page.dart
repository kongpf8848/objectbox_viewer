// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Dump raw bytes at candidate page boundaries to find the correct pageSize.
/// Also search for "TodoEntity" string to locate schema data.
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  print('File size: ${raw.length}');

  // Search for "TodoEntity" string
  final target = utf8.encode('TodoEntity');
  print('\nSearching for "TodoEntity"...');
  for (var i = 0; i < raw.length - target.length; i++) {
    var match = true;
    for (var j = 0; j < target.length; j++) {
      if (raw[i + j] != target[j]) { match = false; break; }
    }
    if (match) print('  FOUND at offset $i (0x${i.toRadixString(16)})');
  }

  // Dump bytes at candidate page boundaries
  final candidates = [4096, 2048, 8192];
  for (final ps in candidates) {
    if (raw.length % ps != 0) {
      print('\npageSize=$ps: SKIP (file size not multiple)');
      continue;
    }
    print('\n=== pageSize=$ps (${raw.length ~/ ps} pages) ===');
    for (var pgno = 0; pgno < raw.length ~/ ps && pgno < 8; pgno++) {
      final off = pgno * ps;
      if (off + 32 > raw.length) break;
      final b = <String>[];
      for (var j = 0; j < 32; j++) b.add(raw[off + j].toRadixString(16).padLeft(2, '0'));
      final magic = ByteData.sublistView(raw, off).getUint32(0, Endian.little);
      print('  Page $pgno (off=$off): magic=0x${magic.toRadixString(16)}');
      print('    ${b.sublist(0, 16).join(' ')}');
      print('    ${b.sublist(16, 32).join(' ')}');
    }
  }
}
