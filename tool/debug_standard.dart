import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  final dbPath = r'D:\jack\db';
  final dataFile = File('$dbPath/data.mdb');
  final bytes = await dataFile.readAsBytes();
  final bd = ByteData.view(bytes.buffer);

  // Element[2] with problematic vtableSOff = -54
  final propTableAddr = 12068;
  print('Examining Element[2] at $propTableAddr');
  print('Hex: ${_hex(bytes, propTableAddr, 40)}');

  // Check what bytes 4-7 mean
  final bytes47 = bd.getUint32(propTableAddr + 4, Endian.little);
  print('\nbytes[4-7] = $bytes47 (0x${bytes47.toRadixString(16)})');

  // Check if this could be inline values (no vtable)
  // In ObjectBox, some values are stored inline in the table itself
  // If vtableSOff is 0, table has no vtable and fields are stored inline

  // Check vtableSOff as uint32 instead of int32
  final vtableSOffUint = bd.getUint32(propTableAddr, Endian.little);
  print('\nvtableSOff as uint32: $vtableSOffUint');
  print('As int32: ${bd.getInt32(propTableAddr, Endian.little)}');

  // Try: if vtableSOff is the ABSOLUTE offset of vtable (not relative)
  if (vtableSOffUint > 0 && vtableSOffUint < bytes.length && vtableSOffUint + 2 < bytes.length) {
    final vtableSize = bd.getUint16(vtableSOffUint, Endian.little);
    print('\nIf vtableSOff is absolute vtable offset:');
    print('  vtable at: $vtableSOffUint');
    print('  vtableSize: $vtableSize');
    if (vtableSize >= 8 && vtableSize <= 128) {
      print('  VALID!');
    }
  }

  // Check if this could be an inline string or vector
  // bytes[4-7] might be the length
  if (bytes47 > 0 && bytes47 < 1000) {
    final possibleLen = bytes47;
    final possibleStrStart = propTableAddr + 8;
    if (possibleStrStart + possibleLen <= bytes.length) {
      final str = utf8.decode(bytes.sublist(possibleStrStart, possibleStrStart + possibleLen), allowMalformed: true);
      if (str.length > 2 && str.codeUnits.every((c) => c > 31 && c < 127)) {
        print('\nPossibly an inline string of length $possibleLen: "$str"');
      }
    }
  }

  // Check bytes[8-11]
  final bytes811 = bd.getUint32(propTableAddr + 8, Endian.little);
  print('\nbytes[8-11] = $bytes811 (0x${bytes811.toRadixString(16)})');

  // Check bytes[12-15]
  final bytes1215 = bd.getUint32(propTableAddr + 12, Endian.little);
  print('bytes[12-15] = $bytes1215 (0x${bytes1215.toRadixString(16)})');
}

String _hex(List<int> bytes, int offset, int len) {
  final end = (offset + len).clamp(0, bytes.length);
  final start = offset.clamp(0, bytes.length);
  return bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
