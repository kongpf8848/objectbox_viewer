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

  print('File size: ${bytes.length}, Page size: $pageSize, Pages: $numPages');
  print('');

  // Collect all data entries by page
  final entriesByPage = <int, List<Map<String, dynamic>>>{};
  final allEntries = <Map<String, dynamic>>[];

  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 16 > bytes.length) continue;

    final pagePgno = bd.getUint64(off, Endian.little);
    final flags = bd.getUint16(off + 8, Endian.little);
    final type = bd.getUint16(off + 10, Endian.little);
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

      // Check schema vs data
      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) {
          isSchema = false;
          break;
        }
      }
      if (isSchema) continue;

      // Parse FlatBuffer
      int? fbObjectId;
      String? title;
      if (entryLen > 20) {
        final valStart = absEntry + 16;
        final valLen = entryLen - 16;
        final rootOff = bd.getUint32(valStart, Endian.little);
        if (rootOff > 0 && rootOff < valLen) {
          final tableStart = valStart + rootOff;
          if (tableStart + 4 <= valStart + valLen) {
            final vtableSOff = bd.getInt32(tableStart, Endian.little);
            if (vtableSOff != 0) {
              final vtableStart = tableStart - vtableSOff;
              if (vtableStart >= valStart &&
                  vtableStart + 4 <= valStart + valLen) {
                final vtableSize = bd.getUint16(vtableStart, Endian.little);
                final numFields = (vtableSize - 4) ~/ 2;
                if (numFields > 0) {
                  final idFieldOff = bd.getUint16(
                    vtableStart + 4,
                    Endian.little,
                  );
                  if (idFieldOff > 0) {
                    final idFieldAddr = tableStart + idFieldOff;
                    if (idFieldAddr + 8 <= valStart + valLen) {
                      fbObjectId = bd.getInt64(idFieldAddr, Endian.little);
                    }
                  }
                }
                if (numFields > 1) {
                  final titleFieldOff = bd.getUint16(
                    vtableStart + 4 + 1 * 2,
                    Endian.little,
                  );
                  if (titleFieldOff > 0) {
                    final titleFieldAddr = tableStart + titleFieldOff;
                    if (titleFieldAddr + 4 <= valStart + valLen) {
                      final strOff = bd.getUint32(
                        titleFieldAddr,
                        Endian.little,
                      );
                      if (strOff >= 4) {
                        final strAddr = titleFieldAddr + strOff;
                        if (strAddr + 4 <= valStart + valLen) {
                          final strLen = bd.getUint32(strAddr, Endian.little);
                          if (strLen > 0 &&
                              strLen < 200 &&
                              strAddr + 4 + strLen <= valStart + valLen) {
                            try {
                              title = String.fromCharCodes(
                                bytes.sublist(
                                  strAddr + 4,
                                  strAddr + 4 + strLen,
                                ),
                              );
                            } catch (_) {}
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      final keyHex = bytes
          .sublist(absEntry, absEntry + 16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final entry = {
        'pgno': pgno,
        'pagePgno': pagePgno,
        'flags': flags,
        'type': type,
        'objectId': fbObjectId ?? -1,
        'title': title ?? '?',
        'entryLen': entryLen,
        'keyHex': keyHex,
      };

      entriesByPage.putIfAbsent(pgno, () => []).add(entry);
      allEntries.add(entry);
    }
  }

  // Print summary by page
  print('=== Data entries by page ===');
  for (var pgno = 0; pgno < numPages; pgno++) {
    final entries = entriesByPage[pgno];
    if (entries == null || entries.isEmpty) continue;
    final first = entries.first;
    print(
      'Page $pgno: headerPgno=${first['pagePgno']}, flags=${first['flags']}, type=${first['type']}, ${entries.length} entries',
    );
    for (final e in entries) {
      print(
        '  objectId=${e['objectId']}, title="${e['title']}", len=${e['entryLen']}',
      );
      print('    key: ${e['keyHex']}');
    }
  }

  print('');
  print('=== Summary ===');
  print('Total data entries: ${allEntries.length}');

  // Count unique objectIds
  final objectIds = allEntries.map((e) => e['objectId'] as int).toSet();
  print('Unique objectIds: ${objectIds.length}');
  print(
    'ObjectId range: ${objectIds.reduce((a, b) => a < b ? a : b)} - ${objectIds.reduce((a, b) => a > b ? a : b)}',
  );

  // Check for duplicates
  final idCounts = <int, int>{};
  for (final e in allEntries) {
    final id = e['objectId'] as int;
    idCounts[id] = (idCounts[id] ?? 0) + 1;
  }
  final duplicates = idCounts.entries.where((e) => e.value > 1).toList();
  if (duplicates.isNotEmpty) {
    print('Duplicate objectIds (copy-on-write):');
    for (final d in duplicates) {
      print('  objectId=${d.key}, count=${d.value}');
      // Show which pages
      final pages = allEntries
          .where((e) => e['objectId'] == d.key)
          .map((e) => e['pgno'] as int)
          .toList();
      print('    pages: $pages');
    }
  }
}
