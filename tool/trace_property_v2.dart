// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as p;

/// Diagnostic tool: trace FlatBuffer parsing of ObjectBox schema entries.
/// Usage: dart run tool/trace_property_v2.dart
void main() async {
  final dbPath = r'D:\jack\db';
  final dataFile = File(p.join(dbPath, 'data.mdb'));
  if (!await dataFile.exists()) {
    print('ERROR: data.mdb not found in $dbPath');
    exit(1);
  }

  final rawBytes = await dataFile.readAsBytes();
  print('File size: ${rawBytes.length}');

  // ObjectBox data.mdb has a 16-byte prefix before the LMDB header.
  var start = 0;
  if (rawBytes.length >= 16 &&
      ByteData.sublistView(rawBytes, 16).getUint32(0, Endian.little) == 0xBEEFC0DE) {
    start = 16;
    print('16-byte prefix detected, slicing from offset 16');
  }

  final data = rawBytes.sublist(start);
  final bd = ByteData.sublistView(data);

  final pageSize = bd.getUint32(24, Endian.little);
  if (pageSize < 512 || pageSize > 65536) {
    print('ERROR: invalid pageSize=$pageSize');
    exit(1);
  }
  final numPages = data.length ~/ pageSize;
  print('pageSize=$pageSize  numPages=$numPages');

  // Find schema entries (entityId=0 sub-db, key bytes 8-14 all zero)
  final schemaEntries = <_Entry>[];
  for (var pgno = numPages - 1; pgno >= 0; pgno--) {
    final pageEntries = _readPageEntries(data, bd, pageSize, pgno);
    print('  pgno=$pgno: ${pageEntries.length} entries');
    for (final e in pageEntries) {
      final isSch = e.isSchema;
      print('    entry abs=${e.absEntry} entityId=${e.entityId} isSchema=$isSch');
      if (isSch) schemaEntries.add(e);
    }
  }

  print('\nFound ${schemaEntries.length} schema entries');

  // Focus on TodoEntity (entityId=1)
  for (final e in schemaEntries) {
    if (e.entityId == 1) {
      print('\n=== TodoEntity schema entry ===');
      print('  absEntry=${e.absEntry}  valLen=${e.valLen}');
      _traceEntitySchema(data, bd, e.absEntry, e.valLen);
      break;
    }
  }
}

void _traceEntitySchema(Uint8List data, ByteData bd, int absEntry, int valLen) {
  final valStart = absEntry + 16;
  final valEnd = valStart + valLen;

  final rootOff = bd.getUint32(valStart, Endian.little);
  print('  rootOff=$rootOff (0x${rootOff.toRadixString(16)})');
  if (rootOff == 0 || rootOff >= valLen) {
    print('  ERROR: invalid rootOff');
    return;
  }

  final tableStart = valStart + rootOff;
  print('  tableStart=abs $tableStart');

  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  print('  vtableSOff=$vtableSOff');
  int vtableStart;
  if (vtableSOff > 0) {
    vtableStart = tableStart - vtableSOff;
    print('  ObjectBox format: vtable at abs $vtableStart');
  } else if (vtableSOff < 0) {
    vtableStart = tableStart - vtableSOff;
    print('  Standard FB format: vtable at abs $vtableStart');
  } else {
    print('  ERROR: vtableSOff=0');
    return;
  }

  if (vtableStart < valStart || vtableStart + 4 > valEnd) {
    print('  ERROR: vtableStart out of range');
    return;
  }

  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;
  print('  vtableSize=$vtableSize  numFields=$numFields');

  // Entity name is at vtable index 3 (field[3])
  if (numFields > 3) {
    final nameFieldOff = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
    print('  entity name field offset=$nameFieldOff (vtable[3])');
    if (nameFieldOff > 0) {
      final nameAddr = tableStart + nameFieldOff;
      final strOff = bd.getUint32(nameAddr, Endian.little);
      print('    name field addr=abs $nameAddr  strOff=$strOff');
      if (strOff > 0) {
        final strAddr = nameAddr + strOff;
        if (strAddr + 4 <= valEnd) {
          final strLen = bd.getUint32(strAddr, Endian.little);
          print('    strAddr=abs $strAddr  strLen=$strLen');
          if (strLen > 0 && strLen < 1000 && strAddr + 4 + strLen <= valEnd) {
            final name = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
                allowMalformed: true);
            print('    ENTITY NAME: "$name"');
          }
        }
      }
    }
  }

  // Properties vector is at vtable index 4 (field[4])
  if (numFields > 4) {
    final propsFieldOff = bd.getUint16(vtableStart + 4 + 4 * 2, Endian.little);
    print('  properties field offset=$propsFieldOff (vtable[4])');
    if (propsFieldOff > 0) {
      final propsAddr = tableStart + propsFieldOff;
      final vecOff = bd.getUint32(propsAddr, Endian.little);
      print('    props addr=abs $propsAddr  vecOff=$vecOff');
      if (vecOff >= 4) {
        final vecAddr = propsAddr + vecOff;
        if (vecAddr + 4 <= valEnd) {
          final vecLen = bd.getUint32(vecAddr, Endian.little);
          print('    properties vector: addr=abs $vecAddr  len=$vecLen');

          for (var i = 0; i < vecLen && i < 20; i++) {
            final elemOffAddr = vecAddr + 4 + i * 4;
            if (elemOffAddr + 4 > valEnd) break;
            final elemOff = bd.getUint32(elemOffAddr, Endian.little);
            if (elemOff == 0) continue;
            final propAddr = elemOffAddr + elemOff;
            print('\n  Property [$i] at abs $propAddr');
            _tracePropertyTable(data, bd, propAddr, valStart, valEnd);
          }
        }
      }
    }
  }
}

void _tracePropertyTable(Uint8List data, ByteData bd, int tableStart, int valStart, int valEnd) {
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
  print('    vtableSOff=$vtableSOff  vtableSize=$vtableSize  numFields=$numFields');

  // field[1] = name (string)
  if (numFields > 1) {
    final nameFieldOff = bd.getUint16(vtableStart + 4 + 1 * 2, Endian.little);
    print('    name field offset=$nameFieldOff');
    if (nameFieldOff > 0) {
      final nameAddr = tableStart + nameFieldOff;
      final strOff = bd.getUint32(nameAddr, Endian.little);
      print('      nameAddr=abs $nameAddr  strOff=$strOff (0x${strOff.toRadixString(16)})');

      if (strOff > 0) {
        final strAddr = nameAddr + strOff;
        print('      strAddr=abs $strAddr');
        if (strAddr + 4 <= valEnd) {
          final strLen = bd.getUint32(strAddr, Endian.little);
          print('      strLen=$strLen (0x${strLen.toRadixString(16)})');
          if (strLen > 0 && strLen < 1000 && strAddr + 4 + strLen <= valEnd) {
            final name = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
                allowMalformed: true);
            print('      PROPERTY NAME: "$name"');
          } else {
            print('      ERROR: invalid strLen=$strLen');
          }
        } else {
          print('      ERROR: strAddr+4 > valEnd');
        }
      } else {
        print('      ERROR: strOff=0 (null string)');
      }
    }
  }

  // field[2] = type (int32)
  if (numFields > 2) {
    final typeFieldOff = bd.getUint16(vtableStart + 4 + 2 * 2, Endian.little);
    if (typeFieldOff > 0) {
      final typeAddr = tableStart + typeFieldOff;
      final type = bd.getInt32(typeAddr, Endian.little);
      print('    type=$type (0x${type.toRadixString(16)})');
    }
  }
}

// ─── LMDB Page/Entry Reading ─────────────────────────────────

List<_Entry> _readPageEntries(Uint8List data, ByteData bd, int pageSize, int pgno) {
  final off = pgno * pageSize;
  if (off + 14 > data.length) return [];
  final lower = bd.getUint16(off + 12, Endian.little);
  if (lower < 14) return [];
  final numPtrs = (lower - 14) ~/ 2;
  final ptrs = <int>[];
  for (var i = 0; i < numPtrs && i < 500; i++) {
    final ptr = bd.getUint16(off + 14 + i * 2, Endian.little);
    if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
  }
  if (ptrs.isEmpty) return [];
  ptrs.sort();
  final uniquePtrs = <int>[ptrs.first];
  for (var i = 1; i < ptrs.length; i++) {
    if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
  }
  final entries = <_Entry>[];
  for (var i = 0; i < uniquePtrs.length; i++) {
    final start = uniquePtrs[i];
    final end = (i + 1 < uniquePtrs.length) ? uniquePtrs[i + 1] : pageSize;
    final len = end - start;
    if (len < 16) continue;
    entries.add(_Entry(off, start, len, data, bd));
  }
  return entries;
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
  bool get isSchema {
    for (var i = 8; i <= 14; i++) {
      if (_data[absEntry + i] != 0) return false;
    }
    return true;
  }

  int get valLen => length - 16;
}
