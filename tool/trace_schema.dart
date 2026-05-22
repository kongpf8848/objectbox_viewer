// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as p;

/// Diagnostic tool: properly parse LMDB pages and find schema entries.
void main() async {
  final dbPath = r'D:\jack\db';
  final dataFile = File(p.join(dbPath, 'data.mdb'));
  if (!await dataFile.exists()) {
    print('ERROR: data.mdb not found');
    exit(1);
  }

  final rawBytes = await dataFile.readAsBytes();
  print('File size: ${rawBytes.length}');

  // Slice 16-byte prefix
  final data = rawBytes.sublist(16);
  final bd = ByteData.sublistView(data);
  print('Sliced data size: ${data.length}');

  // Verify magic
  final magic = bd.getUint32(0, Endian.little);
  if (magic != 0xBEEFC0DE) {
    print('ERROR: bad magic 0x${magic.toRadixString(16)}');
    exit(1);
  }

  // Page size at sliced offset 24 (= original offset 40)
  final pageSize = bd.getUint32(24, Endian.little);
  print('pageSize=$pageSize');
  if (pageSize < 512 || pageSize > 65536) { print('ERROR: bad pageSize'); exit(1); }

  final numPages = data.length ~/ pageSize;
  print('numPages=$numPages\n');

  // Collect schema entries (valid FlatBuffers with entityId=0)
  final schemaEntries = <_Entry>[];
  for (var pgno = 0; pgno < numPages; pgno++) {
    final entries = _readPageEntries(data, bd, pageSize, pgno);
    for (final e in entries) {
      if (e.isSchema) schemaEntries.add(e);
    }
  }
  print('Found ${schemaEntries.length} schema entries');

  // Try each schema entry until one parses successfully
  for (final e in schemaEntries) {
    print('\n=== Trying schema entry abs=${e.absEntry} valLen=${e.valLen} ===');
    final ok = _parseSchemaEntry(data, bd, e.absEntry, e.valLen);
    if (ok) { print('  SUCCESS!'); break; }
  }
}

bool _parseSchemaEntry(Uint8List data, ByteData bd, int absEntry, int valLen) {
  if (valLen < 4) return false;
  final valStart = absEntry + 16;
  final valEnd = valStart + valLen;
  final rootOff = bd.getUint32(valStart, Endian.little);
  if (rootOff == 0 || rootOff >= valLen) return false;

  final tableStart = valStart + rootOff;
  if (tableStart + 4 > valEnd) return false;

  // VTable signed offset
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  int vtableStart;
  if (vtableSOff > 0) {
    vtableStart = tableStart - vtableSOff;
  } else if (vtableSOff < 0) {
    vtableStart = tableStart - vtableSOff;
  } else {
    return false;
  }

  if (vtableStart < valStart || vtableStart + 4 > valEnd) return false;

  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;
  print('  vtableSize=$vtableSize  numFields=$numFields');

  // Entity name at vtable[3]
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
            print('  ENTITY: "$name"');
          }
        }
      }
    }
  }

  // Properties at vtable[4]
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
            _parseProperty(data, bd, propAddr, valStart, valEnd);
          }
        }
      }
    }
  }
  return true;
}

void _parseProperty(Uint8List data, ByteData bd, int tableStart, int valStart, int valEnd) {
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

  // field[1] = name
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
            // field[2] = type
            var type = 0;
            if (numFields > 2) {
              final typeFieldOff = bd.getUint16(vtableStart + 4 + 2 * 2, Endian.little);
              if (typeFieldOff > 0) {
                type = bd.getInt32(tableStart + typeFieldOff, Endian.little);
              }
            }
            print('    "$name"  type=$type');
          }
        }
      }
    }
  }
}

List<_Entry> _readPageEntries(Uint8List data, ByteData bd, int pageSize, int pgno) {
  final off = pgno * pageSize;
  if (off + 12 > data.length) return [];
  final lower = bd.getUint16(off + 6, Endian.little);
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
  final unique = <int>[ptrs.first];
  for (var i = 1; i < ptrs.length; i++) {
    if (ptrs[i] != unique.last) unique.add(ptrs[i]);
  }
  final entries = <_Entry>[];
  for (var i = 0; i < unique.length; i++) {
    final start = unique[i];
    final end = (i + 1 < unique.length) ? unique[i + 1] : pageSize;
    final len = end - start;
    if (len >= 16) entries.add(_Entry(off, start, len, data, bd));
  }
  return entries;
}

class _Entry {
  final int pageOffset, entryOffset, length;
  final Uint8List _data;
  final ByteData _bd;
  _Entry(this.pageOffset, this.entryOffset, this.length, this._data, this._bd);
  int get absEntry => pageOffset + entryOffset;
  int get entityId => _data[absEntry + 15];
  int get objectId => _bd.getUint64(absEntry, Endian.little);
  int get valLen => length - 16;

  /// Schema entry: entityId=0 in key, AND value is a valid FlatBuffer (rootOff > 0)
  bool get isSchema {
    if (_data[absEntry + 15] != 0) return false; // entityId must be 0
    for (var i = 8; i <= 14; i++) { if (_data[absEntry + i] != 0) return false; }
    // Must have non-empty value with valid FlatBuffer root offset
    if (valLen < 4) return false;
    final rootOff = _bd.getUint32(absEntry + 16, Endian.little);
    return rootOff > 0 && rootOff < valLen;
  }
}
