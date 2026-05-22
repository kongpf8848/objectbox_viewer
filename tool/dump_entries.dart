import 'dart:io';
import 'dart:typed_data';

void main() {
  final data = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(data);
  final ps = 4096;
  final np = data.length ~/ ps;

  // Dump the data areas of pages 2, 4, 5, 6 (entries are in the middle/end)
  for (var p in [2, 4, 5, 6]) {
    final off = p * ps;
    // Read header
    final pageNum = bd.getUint64(off, Endian.little);
    final flags = bd.getUint16(off + 8, Endian.little);
    final type = bd.getUint16(off + 10, Endian.little);
    final lower = bd.getUint16(off + 12, Endian.little);
    final numPtrs = (lower - 14) ~/ 2;
    
    print('\n=== PAGE $p: pageNum=$pageNum, flags=$flags, type=$type, lower=$lower, numPtrs=$numPtrs ===');
    
    // Read pointers
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs; i++) {
      final ptr = bd.getUint16(off + 14 + i * 2, Endian.little);
      ptrs.add(ptr);
      print('  ptr[$i] = 0x${ptr.toRadixString(16)} ($ptr)');
    }
    
    // Dump data at each pointer (64 bytes from each entry)
    for (var i = 0; i < ptrs.length; i++) {
      final ptr = ptrs[i];
      if (ptr == 0) continue;
      print('\n  --- Entry $i at page offset 0x${ptr.toRadixString(16)} ---');
      for (var j = 0; j < 128 && off + ptr + j < data.length; j += 16) {
        final hex = <String>[];
        final ascii = <int>[];
        for (var k = 0; k < 16 && off + ptr + j + k < data.length; k++) {
          hex.add(data[off + ptr + j + k].toRadixString(16).padLeft(2, '0'));
          final c = data[off + ptr + j + k];
          ascii.add((c >= 32 && c < 127) ? c : 46);
        }
        print('    ${j.toString().padLeft(4)}: ${hex.join(' ')}  ${String.fromCharCodes(ascii)}');
      }
    }
  }
}
