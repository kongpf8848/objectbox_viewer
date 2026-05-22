// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as p;

/// Diagnostic tool: properly parse LMDB pages and find schema entries.
/// The file has a 16-byte prefix; LMDB header starts at offset 16.
void main() async {
  final dbPath = r'D:\jack\db';
  final dataFile = File(p.join(dbPath, 'data.mdb'));
  if (!await dataFile.exists()) {
    print('ERROR: data.mdb not found in $dbPath');
    exit(1);
  }

  final rawBytes = await dataFile.readAsBytes();
  print('File size: ${rawBytes.length}');

  // Slice from offset 16 (16-byte prefix before LMDB header)
  final data = rawBytes.sublist(16);
  final bd = ByteData.sublistView(data);
  print('Sliced data size: ${data.length}');

  // Verify LMDB magic at offset 0 of sliced data
  final magic = bd.getUint32(0, Endian.little);
  if (magic != 0xBEEFC0DE) {
    print('ERROR: invalid LMDB magic 0x${magic.toRadixString(16)}');
    exit(1);
  }
  print('LMDB magic OK');

  // Page size is at offset 24 of sliced data (= original offset 40)
  final pageSize = bd.getUint32(24, Endian.little);
  print('pageSize=$pageSize (0x${pageSize.toRadixString(16)})');
  if (pageSize < 512 || pageSize > 65536) {
    print('ERROR: invalid pageSize');
    exit(1);
  }

  final numPages = data.length ~/ pageSize;
  print('numPages=$numPages\n');

  // Parse all pages to find schema entries
  final schemaEntries = <_Entry>[];
  for (var pgno = 0; pgno < numPages; pgno++) {
    final pageEntries = _readPageEntries(data, bd, pageSize, pgno);
    if (pageEntries.isEmpty) continue;
    print('Page $pgno: ${pageEntries.length} entries');
    for (final e in pageEntries) {
      if (e.isSchema) {
        print('  SCHEMA entry: abs=${e.absEntry} entityId=${e.entityId} objId=${e.objectId}');
        schemaEntries.add(e);
      }
    }
  }

  print('\nFound ${schemaEntries.length} schema entries');

  // Parse schema entries (skip invalid ones)
  var parsed = false;
  for (final e in schemaEntries) {
    print('\n=== Trying schema entry at abs=${e.absEntry} valLen=${e.valLen} ===');
    if (e.valLen < 4) { print('  SKIP: valLen=${e.valLen}'); continue; }
    _parseSchemaEntry(data, bd, e.absEntry, e.valLen);
    // If we get here without early return, it was parsed
    parsed = true;
    break; // Just parse the first valid one
  }
  if (!parsed) print('\nERROR: no valid schema entry found');
}

List<_Entry> _readPageEntries(Uint8List data, ByteData bd, int pageSize, int pgno) {
  final off = pgno * pageSize;
  if (off + 12 > data.length) return [];

  // LMDB page header:
  //   offset 0: mp_magic (uint32)
  //   offset 4: mp_flags (uint16)
  //   offset 6: mp_lower (uint16) - offset of first free pointer slot
  //   offset 8: mp_upper (uint16) - offset of first free data byte
  //   offset 10: mp_pages (uint16)
  //   offset 12+: mp_ptrs[] (uint16 array)

  final lower = bd.getUint16(off + 6, Endian.little);  // mp_lower
  if (lower < 12 || lower > pageSize) return [];

  final numPtrs = (lower - 12) ~/ 2;
  if (numPtrs <= 0 || numPtrs > 2000) return [];

  final ptrs = <int>[];
  for (var i = 0; i < numPtrs; i++) {
    final ptr = bd.getUint16(off + 12 + i * 2, Endian.little);
    if (ptr >= 12 && ptr < pageSize) ptrs.add(ptr);
  }

  if (ptrs.isEmpty) return [];
  ptrs.sort();

  // Deduplicate
  final uniquePtrs = <int>[ptrs.first];
  for (var i = 1; i < ptrs.length; i++) {
    if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
  }

  final entries = <_Entry>[];
  for (var i = 0; i < uniquePtrs.length; i++) {
    final start = uniquePtrs[i];
    final end = (i + 1 < uniquePtrs.length) ? uniquePtrs[i + 1] : pageSize;
    final len = end - start;
    if (len >= 16) entries.add(_Entry(off, start, len, data, bd));
  }
  return entries;
}

void _parseSchemaEntry(Uint8List data, ByteData bd, int absEntry, int valLen) {
  if (valLen < 4) { print('  SKIP: valLen=$valLen < 4'); return; }
  final valStart = absEntry + 16;
  final valEnd = valStart + valLen;
  final rootOff = bd.getUint32(valStart, Endian.little);
  print('  valStart=$valStart valLen=$valLen rootOff=$rootOff');
  if (rootOff == 0) { print('  SKIP: rootOff=0'); return; }
  if (rootOff >= valLen) { print('  SKIP: rootOff=$rootOff >= valLen=$valLen'); return; }

  final tableStart = valStart + rootOff;
  if (tableStart + 4 > valEnd) return;

  // VTable signed offset
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  int vtableStart;
  if (vtableSOff > 0) {
    vtableStart = tableStart - vtableSOff;
  } else if (vtableSOff < 0) {
    vtableStart = tableStart - vtableSOff;  // subtract negative = add
  } else {
    return;
  }

  if (vtableStart < valStart || vtableStart + 4 > valEnd) return;

  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;
  print('  vtableSize=$vtableSize  numFields=$numFields');

  // Entity name is at vtable index 3 (field[3])
  if (numFields > 3) {
    final nameFieldOff = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
    if (nameFieldOff > 0) {
      final nameAddr = tableStart + nameFieldOff;
      final strOff = bd.getUint32(nameAddr, Endian.little);
      if (strOff > 0) {
        final strAddr = nameAddr + strOff;
        if (strAddr + 4 <= valEnd) {
          final strLen = bd.getUint32(strAddr, Endian.little);
          if (strLen > 0 && strLen < 1000 && strAddr + 4 + strLen <= valEnd) {
            final name = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
                allowMalformed: true);
            print('  ENTITY NAME: "$name"');
          }
        }
      }
    }
  }

  // Properties vector is at vtable index 4 (field[4])
  if (numFields > 4) {
    final propsFieldOff = bd.getUint16(vtableStart + 4 + 4 * 2, Endian.little);
    if (propsFieldOff > 0) {
      final propsAddr = tableStart + propsFieldOff;
      final vecOff = bd.getUint32(propsAddr, Endian.little);
      if (vecOff >= 4) {
        final vecAddr = propsAddr + vecOff;
        if (vecAddr + 4 <= valEnd) {
          final vecLen = bd.getUint32(vecAddr, Endian.little);
          print('  Properties: $vecLen items');

          for (var i = 0; i < vecLen && i < 20; i++) {
            final elemOffAddr = vecAddr + 4 + i * 4;
            if (elemOffAddr + 4 > valEnd) break;
            final elemOff = bd.getUint32(elemOffAddr, Endian.little);
            if (elemOff == 0) continue;
            final propAddr = elemOffAddr + elemOff;
            _parsePropertyTable(data, bd, propAddr, valStart, valEnd);
          }
        }
      }
    }
  }
}

void _parsePropertyTable(Uint8List data, ByteData bd, int tableStart, int valStart, int valEnd) {
  if (tableStart + 4 > valEnd) return;

  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  int vtableStart;
  if (vtableSOff > 0) {
    vtableStart = tableStart - vtableSOff;
  } else if (vtableSOff < 0) {
    vtableStart = tableStart - vtableSOff;
  } else {
    return;
  }

  if (vtableStart < valStart || vtableStart + 4 > valEnd) return;

  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;
  print('    Property: vtableSize=$vtableSize  numFields=$numFields');

  // field[1] = name (string)
  if (numFields > 1) {
    final nameFieldOff = bd.getUint16(vtableStart + 4 + 1 * 2, Endian.little);
    if (nameFieldOff > 0) {
      final nameAddr = tableStart + nameFieldOff;
      final strOff = bd.getUint32(nameAddr, Endian.little);
      if (strOff > 0) {
        final strAddr = nameAddr + strOff;
        if (strAddr + 4 <= valEnd) {
          final strLen = bd.getUint32(strAddr, Endian.little);
          if (strLen > 0 && strLen < 1000 && strAddr + 4 + strLen <= valEnd) {
            final name = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
                allowMalformed: true);
            print('      PROPERTY NAME: "$name"');
          }
        }
      }
    }
  }

  // field[2] = type (int32)
  if (numFields > 2) {
    final typeFieldOff = bd.getUint16(vtableStart + 4 + 2 * 2, Endian.little);
    if (typeFieldOff > 0) {
      final typeAddr = tableStart + typeFieldOff;
      final type = bd.getInt32(typeAddr, Endian.little);
      print('      PROPERTY TYPE: $type');
    }
  }
}

class _Entry {
  final int pageOffset;
  final int entryOffset;
  final int length;
  final Uint8List _data;
  final ByteData _bd;
  _Entry(this.pageOffset, this.entryOffset, this.length, this._data, this._bd);
  int get absEntry => pageOffset + entryOffset;
  int get entityId => _data[absEntry + 15];
  int get objectId => _bd.getUint32(absEntry, Endian.little);
  int get valLen => length - 16;
  bool get isSchema {
    for (var i = 8; i <= 14; i++) {
      if (_data[absEntry + i] != 0) return false;
    }
    return true;
  }
}
