// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Dump raw bytes of entries detected as "schema" to verify detection logic.
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  print('File size: ${raw.length}');

  // Slice 16-byte prefix
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);

  // Dump entries at these offsets (detected as schema by isSchema)
  final candidates = [8268, 8284, 8320, 8416, 8456, 8887, 8960];
  for (final abs in candidates) {
    if (abs + 32 > data.length) break;
    print('\n=== Entry at abs=$abs ===');
    // Dump first 32 bytes (16-byte header + 16 bytes of value)
    for (var i = 0; i < 32; i += 16) {
      final b = <String>[];
      for (var j = 0; j < 16 && abs + i + j < data.length; j++) {
        b.add(data[abs + i + j].toRadixString(16).padLeft(2, '0'));
      }
      print('  ${(abs + i).toRadixString(16).padLeft(8, '0')}:  ${b.join(' ')}');
    }
    // Check isSchema logic: bytes 8-14 of entry == 0?
    var isSch = true;
    for (var i = 8; i <= 14; i++) {
      if (data[abs + i] != 0) { isSch = false; break; }
    }
    print('  isSchema (bytes 8-14==0): $isSch');
    print('  entityId (byte 15): ${data[abs + 15]}');
    print('  objectId (bytes 0-7): ${bd.getUint64(abs, Endian.little)}');

    // Check value data (bytes 16+)
    if (abs + 16 + 4 <= data.length) {
      final rootOff = bd.getUint32(abs + 16, Endian.little);
      print('  value rootOff: $rootOff (0x${rootOff.toRadixString(16)})');
    }
  }
}
