// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

/// Check page size at various offsets
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final rawBytes = await file.readAsBytes();

  // Sice from offset 16 (LMDB header starts there)
  final data = rawBytes.sublist(16);
  final bd = ByteData.sublistView(data);

  print('Sliced data size: ${data.length}');
  print('');

  // Print offsets 0-64 as hex
  print('Offsets 0-63 of sliced data:');
  for (var i = 0; i < 64; i += 16) {
    final b = <String>[];
    for (var j = 0; j < 16 && i + j < data.length; j++) {
      b.add(data[i + j].toRadixString(16).padLeft(2, '0'));
    }
    print('  ${i.toRadixString(16).padLeft(8, '0')}:  ${b.join(' ')}');
  }
  print('');

  // Check page size at various offsets
  print('Checking page size at various offsets:');
  print('  offset 8:  ${bd.getUint32(8, Endian.little)} (0x${bd.getUint32(8, Endian.little).toRadixString(16)})');
  print('  offset 12: ${bd.getUint32(12, Endian.little)} (0x${bd.getUint32(12, Endian.little).toRadixString(16)})');
  print('  offset 16: ${bd.getUint32(16, Endian.little)} (0x${bd.getUint32(16, Endian.little).toRadixString(16)})');
  print('  offset 24: ${bd.getUint32(24, Endian.little)} (0x${bd.getUint32(24, Endian.little).toRadixString(16)})');
  print('  offset 28: ${bd.getUint32(28, Endian.little)} (0x${bd.getUint32(28, Endian.little).toRadixString(16)})');
  print('  offset 40: ${bd.getUint32(40, Endian.little)} (0x${bd.getUint32(40, Endian.little).toRadixString(16)})');
  print('  offset 52: ${bd.getUint32(52, Endian.little)} (0x${bd.getUint32(52, Endian.little).toRadixString(16)})');
  print('');

  // Try to find 0x1000 (4096) in first 256 bytes
  print('Searching for 0x1000 (4096) in first 256 bytes...');
  for (var i = 0; i < 256 && i + 4 <= data.length; i++) {
    final v = bd.getUint32(i, Endian.little);
    if (v == 4096) {
      print('  FOUND at offset $i (0x${i.toRadixString(16)})');
    }
  }
}
