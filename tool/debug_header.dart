// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

/// Debug: print file header after slicing
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final rawBytes = await file.readAsBytes();
  print('File size: ${rawBytes.length}');

  // Check if 16-byte prefix exists
  var start = 0;
  if (rawBytes.length >= 16 &&
      ByteData.sublistView(rawBytes, 16).getUint32(0, Endian.little) == 0xBEEFC0DE) {
    start = 16;
    print('16-byte prefix detected, slicing from offset 16');
  }

  final data = rawBytes.sublist(start);
  final bd = ByteData.sublistView(data);
  print('Sliced data size: ${data.length}');

  // Print first 64 bytes of sliced data
  print('\nFirst 64 bytes of sliced data:');
  for (var i = 0; i < 64; i += 16) {
    final b = <String>[];
    for (var j = 0; j < 16 && i + j < data.length; j++) {
      b.add(data[i + j].toRadixString(16).padLeft(2, '0'));
    }
    print('  ${i.toRadixString(16).padLeft(8, '0')}:  ${b.join(' ')}');
  }

  // Read LMDB header fields
  final magic = bd.getUint32(0, Endian.little);
  print('\nLMDB magic at 0: 0x${magic.toRadixString(16)}');
  print('LMDB version at 4: ${bd.getUint32(4, Endian.little)}');
  print('LMDB page size at 40: ${bd.getUint32(40, Endian.little)} (0x${bd.getUint32(40, Endian.little).toRadixString(16)})');
  print('LMDB num pages: ${data.length} / ${bd.getUint32(40, Endian.little)} = ${data.length ~/ bd.getUint32(40, Endian.little)}');
}
