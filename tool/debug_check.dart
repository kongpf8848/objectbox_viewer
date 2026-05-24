import 'dart:io';
import 'dart:typed_data';

void main() {
  final path = '/Users/kongpengfei/Documents/data.mdb';
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);

  final pageSize = 16384;
  final pgno = 5;
  final off = pgno * pageSize;
  final entryStart = 15776;
  final absEntry = off + entryStart;
  final valStart = absEntry + 16;

  print('absEntry=$absEntry valStart=$valStart');
  print('byte15=${bytes[absEntry + 15]}');
  print('');

  for (var i = 0; i < 80; i += 4) {
    final v = bd.getUint32(valStart + i, Endian.little);
    final hex = bytes
        .sublist(valStart + i, valStart + i + 4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    print('offset $i: $hex -> $v');
  }
}
