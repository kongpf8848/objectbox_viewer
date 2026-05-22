import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  final data = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(data);

  final ps = 4096;
  final np = data.length ~/ ps;
  print('Pages: $np');

  final seenSchema = <String>{};

  for (var pgno = 2; pgno < np; pgno++) {
    final off = pgno * ps;
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 14) continue;

    final numPtrs = (lower - 14) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs; i++) {
      final p = bd.getUint16(off + 14 + i * 2, Endian.little);
      if (p > 0 && p < ps) ptrs.add(p);
    }
    ptrs.sort();
    final uniquePtrs = <int>[if (ptrs.isNotEmpty) ptrs.first];
    for (var i = 1; i < ptrs.length; i++) {
      if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
    }

    for (var i = 0; i < uniquePtrs.length; i++) {
      final ptr = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length) ? uniquePtrs[i + 1] : ps;
      final entryLen = entryEnd - ptr;
      if (entryLen < 16) continue;

      var isSchema = true;
      for (var k = 8; k <= 14; k++) {
        if (data[off + ptr + k] != 0) { isSchema = false; break; }
      }
      final eid = data[off + ptr + 15];

      if (isSchema && eid == 0) continue;
      if (isSchema) {
        final key = 'entity_$eid';
        if (seenSchema.contains(key)) continue;
        seenSchema.add(key);
      }

      // Extract UTF-8 strings
      final valStart = off + ptr + 16;
      final valEnd = off + ptr + entryLen;
      final buf = <int>[];
      final strings = <String>[];
      for (var j = valStart; j < valEnd; j++) {
        if (data[j] >= 32 || data[j] >= 0x80) {
          buf.add(data[j]);
        } else {
          if (buf.length >= 3) {
            try {
              final s = utf8.decode(buf, allowMalformed: true);
              if (s.trim().isNotEmpty) strings.add(s.trim());
            } catch (_) {}
          }
          buf.clear();
        }
      }
      if (buf.length >= 3) {
        try {
          final s = utf8.decode(buf, allowMalformed: true);
          if (s.trim().isNotEmpty) strings.add(s.trim());
        } catch (_) {}
      }

      final tag = isSchema ? 'SCHEMA' : 'DATA';
      if (isSchema || strings.isNotEmpty) {
        print('Page $pgno entry $i: $tag entity=$eid len=$entryLen');
        print('  $strings');
      }
    }
  }
}
