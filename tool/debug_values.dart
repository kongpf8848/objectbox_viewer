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
  final numPages = bytes.length ~/ pageSize;

  print('Page size: $pageSize, numPages: $numPages');
  print('');

  var entryNum = 0;
  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 16 > bytes.length) continue;
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 16 || lower > pageSize) continue;
    final numPtrs = (lower - 16) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = bd.getUint16(off + 16 + i * 2, Endian.little);
      if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
    }
    if (ptrs.isEmpty) continue;
    ptrs.sort();
    final uniquePtrs = <int>[ptrs.first];
    for (var i = 1; i < ptrs.length; i++) {
      if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
    }

    for (var i = 0; i < uniquePtrs.length; i++) {
      final entryStart = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length)
          ? uniquePtrs[i + 1]
          : pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;

      final absEntry = off + entryStart;
      final valStart = absEntry + 16;
      final valLen = entryLen - 16;

      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) {
          isSchema = false;
          break;
        }
      }
      if (isSchema) continue;

      // Only process entries with valLen >= 100 (real data, not small metadata)
      if (valLen < 100) continue;

      entryNum++;
      print(
        '=== Entry #$entryNum (page $pgno, off=$entryStart, len=$entryLen, byte15=${bytes[absEntry + 15]}) ===',
      );

      // Parse FlatBuffer
      final fields = _parseFlatBuffer(bytes, bd, valStart, valLen);
      for (var fi = 0; fi < fields.length; fi++) {
        final f = fields[fi];
        if (f['value'] != null) {
          print('  field[$fi]: ${f['type']} = ${f['value']}');
        }
      }
      print('');
    }
  }
}

List<Map<String, dynamic>> _parseFlatBuffer(
  Uint8List bytes,
  ByteData bd,
  int valStart,
  int valLen,
) {
  final fields = <Map<String, dynamic>>[];
  if (valLen < 4) return fields;

  final rootOff = bd.getUint32(valStart, Endian.little);
  if (rootOff == 0 || rootOff >= valLen) return fields;

  final tableStart = valStart + rootOff;
  if (tableStart + 4 > valStart + valLen) return fields;

  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  if (vtableSOff <= 0) return fields;

  final vtableStart = tableStart - vtableSOff;
  if (vtableStart < valStart || vtableStart + 4 > valStart + valLen)
    return fields;

  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;

  for (var fi = 0; fi < numFields && fi < 20; fi++) {
    final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
    if (fieldOff == 0) {
      fields.add({'index': fi, 'type': 'NOT_PRESENT', 'value': null});
      continue;
    }

    final fieldAddr = tableStart + fieldOff;
    if (fieldAddr + 8 > valStart + valLen) {
      fields.add({'index': fi, 'type': 'OUT_OF_BOUNDS', 'value': null});
      continue;
    }

    // Try string first
    final strOff = bd.getUint32(fieldAddr, Endian.little);
    if (strOff >= 4 && fieldAddr + strOff + 4 <= valStart + valLen) {
      final strAddr = fieldAddr + strOff;
      final strLen = bd.getUint32(strAddr, Endian.little);
      if (strLen > 0 &&
          strLen < 1000 &&
          strAddr + 4 + strLen <= valStart + valLen) {
        try {
          final str = String.fromCharCodes(
            bytes.sublist(strAddr + 4, strAddr + 4 + strLen),
          );
          if (str.runes.where((r) => r >= 32 && r <= 126).length >=
              str.length * 0.5) {
            fields.add({'index': fi, 'type': 'STRING', 'value': str});
            continue;
          }
        } catch (_) {}
      }
    }

    // Try int64
    final i64 = bd.getInt64(fieldAddr, Endian.little);
    if (i64 > 0 && i64 < 0x7FFFFFFFFFFFFFFF) {
      if (i64 > 1577836800000000000 && i64 < 1893456000000000000) {
        fields.add({
          'index': fi,
          'type': 'TIMESTAMP_NS',
          'value': DateTime.fromMicrosecondsSinceEpoch(
            i64 ~/ 1000,
          ).toIso8601String(),
        });
        continue;
      }
      if (i64 > 1577836800000 && i64 < 1893456000000) {
        fields.add({
          'index': fi,
          'type': 'TIMESTAMP_MS',
          'value': DateTime.fromMillisecondsSinceEpoch(i64).toIso8601String(),
        });
        continue;
      }
      fields.add({'index': fi, 'type': 'INT64', 'value': i64});
      continue;
    }

    // Try int32
    final i32 = bd.getInt32(fieldAddr, Endian.little);
    fields.add({'index': fi, 'type': 'INT32', 'value': i32});
  }

  return fields;
}
