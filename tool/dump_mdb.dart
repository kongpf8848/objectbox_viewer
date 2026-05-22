import 'dart:io';
import 'dart:typed_data';

void main() {
  final data = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(data);
  final ps = 4096;
  final np = data.length ~/ ps;

  // Dump full content of pages 2-6
  for (var p = 2; p < np; p++) {
    final off = p * ps;
    print('\n=== PAGE $p (offset $off), first 512 bytes ===');
    for (var i = 0; i < 512; i += 16) {
      final hex = <String>[];
      final ascii = <int>[];
      for (var j = 0; j < 16; j++) {
        hex.add(data[off + i + j].toRadixString(16).padLeft(2, '0'));
        final c = data[off + i + j];
        ascii.add((c >= 32 && c < 127) ? c : 46);
      }
      print('  ${i.toString().padLeft(4)}: ${hex.join(' ')}  ${String.fromCharCodes(ascii)}');
    }
    print('  ...');
    for (var i = ps - 256; i < ps; i += 16) {
      final hex = <String>[];
      final ascii = <int>[];
      for (var j = 0; j < 16; j++) {
        hex.add(data[off + i + j].toRadixString(16).padLeft(2, '0'));
        final c = data[off + i + j];
        ascii.add((c >= 32 && c < 127) ? c : 46);
      }
      print('  ${i.toString().padLeft(4)}: ${hex.join(' ')}  ${String.fromCharCodes(ascii)}');
    }
  }

  // Detailed page 0 analysis
  print('\n=== PAGE 0 META ANALYSIS ===');
  print('Offset 16 magic (LE): 0x${bd.getUint32(16, Endian.little).toRadixString(16)}');
  print('Offset 20 (LE uint32): ${bd.getUint32(20, Endian.little)}');
  print('Offset 40 page_size? (LE uint32): ${bd.getUint32(40, Endian.little)}');
  print('Offset 44 (LE uint32): ${bd.getUint32(44, Endian.little)}');
  print('Offset 56 (LE uint32): ${bd.getUint32(56, Endian.little)}');
  print('Offset 56 (LE uint64): ${bd.getUint64(56, Endian.little)}');
  print('Offset 80 (LE uint64): ${bd.getUint64(80, Endian.little)}');
  print('Offset 112 (LE uint64): ${bd.getUint64(112, Endian.little)}');
}
