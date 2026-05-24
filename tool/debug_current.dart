import 'dart:io';
import 'dart:typed_data';

void main() {
  final path = '/Users/kongpengfei/Documents/data.mdb';
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);

  // Detect magic offset
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

  print('File size: ${bytes.length}');
  print('Magic offset: $magicOffset');
  print('Page size: $pageSize');
  print('Num pages: $numPages');
  print('');

  // Collect all entries
  final schemaEntries = <int, List<Map<String, dynamic>>>{};
  final dataEntries = <int, List<Map<String, dynamic>>>{};

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
      final entityId = bytes[absEntry + 15];

      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) {
          isSchema = false;
          break;
        }
      }

      if (isSchema) {
        if (entityId == 0) continue;
        final valStart = absEntry + 16;
        final valLen = entryLen - 16;
        final name = _parseSchemaName(bytes, bd, valStart, valLen);
        schemaEntries.putIfAbsent(entityId, () => []).add({
          'pgno': pgno,
          'name': name,
        });
      } else {
        final objectId = bd.getUint32(absEntry, Endian.little);
        dataEntries.putIfAbsent(entityId, () => []).add({
          'pgno': pgno,
          'objectId': objectId,
          'entryLen': entryLen,
        });
      }
    }
  }

  print('=== Schema Entries ===');
  schemaEntries.forEach((entityId, entries) {
    print('Entity ID $entityId:');
    for (final e in entries) {
      print('  page=${e['pgno']} name=${e['name']}');
    }
  });
  print('');

  print('=== Data Entries ===');
  dataEntries.forEach((entityId, entries) {
    print('Entity ID $entityId: ${entries.length} entries');
    for (final e in entries) {
      print(
        '  page=${e['pgno']} objectId=${e['objectId']} len=${e['entryLen']}',
      );
    }
    print('');
  });
}

String? _parseSchemaName(
  Uint8List bytes,
  ByteData bd,
  int valStart,
  int valLen,
) {
  if (valLen < 4) return null;
  final rootOff = bd.getUint32(valStart, Endian.little);
  if (rootOff == 0 || rootOff >= valLen) return null;
  final tableStart = valStart + rootOff;
  if (tableStart + 4 > valStart + valLen) return null;

  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  int vtableStart;
  if (vtableSOff > 0) {
    vtableStart = tableStart - vtableSOff;
  } else if (vtableSOff < 0) {
    vtableStart = tableStart - vtableSOff;
  } else {
    return null;
  }

  if (vtableStart < valStart || vtableStart + 4 > valStart + valLen)
    return null;
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;

  for (final fi in [3, 1]) {
    if (numFields <= fi) continue;
    final off = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
    if (off == 0) continue;
    final addr = tableStart + off;
    if (addr + 4 > valStart + valLen) continue;
    final strOff = bd.getUint32(addr, Endian.little);
    if (strOff < 4) continue;
    final strAddr = addr + strOff;
    if (strAddr + 4 > valStart + valLen) continue;
    final strLen = bd.getUint32(strAddr, Endian.little);
    if (strLen <= 0 || strLen > 100 || strAddr + 4 + strLen > valStart + valLen)
      continue;
    try {
      return String.fromCharCodes(
        bytes.sublist(strAddr + 4, strAddr + 4 + strLen),
      );
    } catch (_) {}
  }
  return null;
}
