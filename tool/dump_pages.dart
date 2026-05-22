// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

/// Dump first 64 bytes of each page
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final rawBytes = await file.readAsBytes();
  print('File size: ${rawBytes.length}');

  // Try different page sizes
  final candidatePageSizes = [4096, 2048, 8192, 16384];
  
  for (final ps in candidatePageSizes) {
    if (rawBytes.length % ps!= 0) continue;
    print('\n=== Trying pageSize=$ps (${rawBytes.length ~/ ps} pages) ===');
    
    // Check magic at page 0, offset 16
    final bd = ByteData.sublistView(rawBytes, 16);
    final magic = bd.getUint32(0, Endian.little);
    if (magic!= 0xBEEFC0DE) {
      print('  SKIP: magic at offset 16 = 0x${magic.toRadixString(16)}');
      continue;
    }
    print('  Magic OK at offset 16');
    
    // Dump first 64 bytes of each page
    for (var pgno = 0; pgno < rawBytes.length ~/ ps && pgno < 8; pgno++) {
      final off = 16 + pgno * ps;
      if (off + 64 > rawBytes.length) break;
      
      final b = <String>[];
      for (var j = 0; j < 64; j++) {
        b.add(rawBytes[off + j].toRadixString(16).padLeft(2, '0'));
      }
      
      final lines = <String>[];
      for (var i = 0; i < 64; i += 16) {
        lines.add('  ${off.toRadixString(16).padLeft(8, '0')}:  ${b.sublist(i, i + 16).join(' ')}');
      }
      
      final pageMagic = ByteData.sublistView(rawBytes, off).getUint32(0, Endian.little);
      print('  Page $pgno (off=$off): magic=0x${pageMagic.toRadixString(16)}');
      if (pgno == 0) lines.forEach(print);
    }
  }
}
