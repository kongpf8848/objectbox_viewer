// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

/// Check file header and print first 64 bytes
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  if (!await file.exists()) {
    print('ERROR: file not found');
    exit(1);
  }

  final bytes = await file.readAsBytes();
  print('File size: ${bytes.length}');

  final bd = ByteData.sublistView(bytes);

  // Print first 64 bytes as hex
  print('\nFirst 64 bytes:');
  for (var i = 0; i < 64; i += 16) {
    final b = <String>[];
    for (var j = 0; j < 16 && i + j < bytes.length; j++) {
      b.add(bytes[i + j].toRadixString(16).padLeft(2, '0'));
    }
    print('  ${i.toRadixString(16).padLeft(8, '0')}:  ${b.join(' ')}');
  }

  // Check magic at offset 0
  final magic = bd.getUint32(0, Endian.little);
  print('\nMagic at 0: 0x${magic.toRadixString(16)}');

  // Check offset 40 (page size)
  if (bytes.length >= 44) {
    final pageSize = bd.getUint32(40, Endian.little);
    print('Page size at 40: $pageSize (0x${pageSize.toRadixString(16)})');
  }

  // Try to find BEEFC0DE in first 1KB
  print('\nSearching for BEEFC0DE in first 4KB...');
  for (var i = 0; i < bytes.length && i < 4096; i++) {
    if (bd.getUint32(i, Endian.little) == 0xBEEFC0DE) {
      print('  FOUND at offset $i (0x${i.toRadixString(16)})');
      break;
    }
  }
}
