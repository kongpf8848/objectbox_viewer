import 'dart:io';
import 'dart:typed_data';

void main() {
  final path = '/Users/kongpengfei/Documents/data.mdb';
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);

  var magicOffset = 0;
  if (bytes.length >= 20 && bd.getUint32(16, Endian.little) == 0xBEEFC0DE) {
    magicOffset = 16;
  }
  final pageSizeOffset = magicOffset == 16 ? 40 : 24;
  var pageSize = bytes.length > pageSizeOffset + 4
      ? bd.getUint32(pageSizeOffset, Endian.little)
      : 4096;
  if (pageSize < 512 || pageSize > 65536) pageSize = 4096;

  // Just parse TodoEntity schema from page 5
  final pgno = 5;
  final off = pgno * pageSize;
  final lower = bd.getUint16(off + 12, Endian.little);
  final numPtrs = (lower - 16) ~/ 2;
  final ptrs = <int>[];
  for (var i = 0; i < numPtrs && i < 500; i++) {
    final ptr = bd.getUint16(off + 16 + i * 2, Endian.little);
    if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
  }
  ptrs.sort();
  final uniquePtrs = <int>[ptrs.first];
  for (var i = 1; i < ptrs.length; i++) {
    if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
  }

  for (var i = 0; i < uniquePtrs.length; i++) {
    final entryStart = uniquePtrs[i];
    final entryEnd = (i + 1 < uniquePtrs.length) ? uniquePtrs[i + 1] : pageSize;
    final entryLen = entryEnd - entryStart;
    if (entryLen < 16) continue;
    final absEntry = off + entryStart;
    bool isSchema = true;
    for (var j = 8; j <= 14; j++) {
      if (bytes[absEntry + j] != 0) {
        isSchema = false;
        break;
      }
    }
    if (!isSchema || bytes[absEntry + 15] != 1) continue;

    final valStart = absEntry + 16;
    final valLen = entryLen - 16;
    print('TodoEntity schema at page=$pgno off=$entryStart valLen=$valLen');
    print('Value hex:');
    for (var j = 0; j < valLen; j += 16) {
      final line = <String>[];
      for (var k = j; k < j + 16 && k < valLen; k++) {
        line.add(bytes[valStart + k].toRadixString(16).padLeft(2, '0'));
      }
      print('  ${j.toString().padLeft(4)}: ${line.join(' ')}');
    }

    // Parse root offset
    final rootOff = bd.getUint32(valStart, Endian.little);
    print('rootOff=$rootOff');
    final tableStart = valStart + rootOff;
    final vtableSOff = bd.getInt32(tableStart, Endian.little);
    final vtableStart = tableStart - vtableSOff;
    final vtableSize = bd.getUint16(vtableStart, Endian.little);
    final numFields = (vtableSize - 4) ~/ 2;
    print(
      'vtable at ${vtableStart - valStart} (rel), size=$vtableSize, numFields=$numFields',
    );
    for (var fi = 0; fi < numFields; fi++) {
      final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
      print('  field[$fi] off=$fieldOff');
      if (fieldOff > 0) {
        final fieldAddr = tableStart + fieldOff;
        print('    addr=${fieldAddr - valStart} (rel)');
        // Try string
        if (fieldAddr + 4 <= valStart + valLen) {
          final strOff = bd.getUint32(fieldAddr, Endian.little);
          print('    strOff=$strOff');
          if (strOff >= 4 && fieldAddr + strOff + 4 <= valStart + valLen) {
            final strAddr = fieldAddr + strOff;
            final strLen = bd.getUint32(strAddr, Endian.little);
            print('    strAddr=${strAddr - valStart} (rel) strLen=$strLen');
            if (strLen > 0 &&
                strLen < 200 &&
                strAddr + 4 + strLen <= valStart + valLen) {
              final str = String.fromCharCodes(
                bytes.sublist(strAddr + 4, strAddr + 4 + strLen),
              );
              print('    STRING: "$str"');
            }
          }
        }
        // Try vector
        if (fieldAddr + 4 <= valStart + valLen) {
          final vecOff = bd.getUint32(fieldAddr, Endian.little);
          print('    vecOff=$vecOff');
          if (vecOff >= 4 &&
              vecOff < 1000 &&
              fieldAddr + vecOff + 4 <= valStart + valLen) {
            final vecAddr = fieldAddr + vecOff;
            final vecLen = bd.getUint32(vecAddr, Endian.little);
            print('    vecAddr=${vecAddr - valStart} (rel) vecLen=$vecLen');
          }
        }
      }
    }
    break;
  }
}
