import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Trace Property table parsing in detail
void main() {
  final bytes = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  final pageSize = bd.getUint32(40, Endian.little);
  final numPages = bytes.length ~/ pageSize;

  // Find TodoEntity schema entry (entityId=1)
  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 14 > bytes.length) continue;
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 14) continue;
    final numPtrs = (lower - 14) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = bd.getUint16(off + 14 + i * 2, Endian.little);
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
      final entryEnd = (i + 1 < uniquePtrs.length) ? uniquePtrs[i + 1] : pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;

      final absEntry = off + entryStart;
      final entityId = bytes[absEntry + 15];
      if (entityId != 1) continue;

      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) { isSchema = false; break; }
      }
      if (!isSchema) continue;

      final valStart = absEntry + 16;
      final valLen = entryLen - 16;

      print('=== Found TodoEntity schema entry ===');
      print('valStart=abs $valStart  valLen=$valLen\n');

      _traceEntitySchema(bytes, bd, valStart, valLen);
      return;
    }
  }
}

void _traceEntitySchema(Uint8List bytes, ByteData bd, int valStart, int valLen) {
  final rootOff = bd.getUint32(valStart, Endian.little);
  final tableStart = valStart + rootOff;
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  final vtableStart = tableStart - vtableSOff;

  // Entity field[4] = properties vector
  final propsVtableOff = bd.getUint16(vtableStart + 4 + 4 * 2, Endian.little);
  final propsFieldAddr = tableStart + propsVtableOff;
  final vecOff = bd.getUint32(propsFieldAddr, Endian.little);
  final vecAddr = propsFieldAddr + vecOff;
  final vecLen = bd.getUint32(vecAddr, Endian.little);

  print('Properties vector at abs $vecAddr  len=$vecLen\n');

  for (var i = 0; i < vecLen; i++) {
    final elemOffAddr = vecAddr + 4 + i * 4;
    final elemOff = bd.getUint32(elemOffAddr, Endian.little);
    final propTableAddr = elemOffAddr + elemOff;

    print('--- Property [$i] at abs $propTableAddr ---');
    _traceOneProperty(bytes, bd, propTableAddr, valStart, valLen, i);
    print('');
  }
}

void _traceOneProperty(Uint8List bytes, ByteData bd, int tableStart, int valStart, int valLen, int idx) {
  if (tableStart + 4 > valStart + valLen) return;

  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  int vtableStart;
  if (vtableSOff > 0) {
    vtableStart = tableStart - vtableSOff;
    print('  vtableSOff=$vtableSOff (ObjectBox: vtable at abs $vtableStart)');
  } else if (vtableSOff < 0) {
    vtableStart = tableStart - vtableSOff;
    print('  vtableSOff=$vtableSOff (standard FB: vtable at abs $vtableStart)');
  } else {
    print('  vtableSOff=0, SKIP');
    return;
  }

  if (vtableStart < valStart || vtableStart + 4 > valStart + valLen) {
    print('  vtable out of bounds!');
    return;
  }

  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;
  print('  vtableSize=$vtableSize  numFields=$numFields');

  // Dump vtable bytes
  print('  VTable bytes: ${_hex(bytes.sublist(vtableStart, vtableStart + vtableSize))}');

  // Dump table bytes (first 32 bytes from table start)
  final tableDumpLen = (32 < valStart + valLen - tableStart) ? 32 : valStart + valLen - tableStart;
  print('  Table bytes: ${_hex(bytes.sublist(tableStart, tableStart + tableDumpLen))}');

  // Try to read field[0] = id struct
  if (numFields > 0) {
    final f0Off = bd.getUint16(vtableStart + 4 + 0 * 2, Endian.little);
    print('  field[0] vtableOff=$f0Off');
    if (f0Off > 0) {
      final f0Addr = tableStart + f0Off;
      if (f0Addr + 12 <= valStart + valLen) {
        final id = bd.getInt32(f0Addr, Endian.little);
        final uid = bd.getUint64(f0Addr + 4, Endian.little);
        print('    id=$id  uid=$uid');
      }
    } else {
      print('    NOT PRESENT');
    }
  }

  // Try to read field[1] = name (string)
  if (numFields > 1) {
    final f1Off = bd.getUint16(vtableStart + 4 + 1 * 2, Endian.little);
    print('  field[1] vtableOff=$f1Off (name)');
    if (f1Off > 0) {
      final f1Addr = tableStart + f1Off;
      print('    nameFieldAddr=abs $f1Addr');
      if (f1Addr + 4 <= valStart + valLen) {
        final strOff = bd.getUint32(f1Addr, Endian.little);
        print('    string offset = $strOff (0x${strOff.toRadixString(16)})');
        if (strOff >= 4) {
          final strAddr = f1Addr + strOff;
          print('    string data at abs $strAddr');
          if (strAddr + 4 <= valStart + valLen) {
            final strLen = bd.getUint32(strAddr, Endian.little);
            print('    string length = $strLen');
            if (strLen > 0 && strLen < 1000 && strAddr + 4 + strLen <= valStart + valLen) {
              final str = utf8.decode(bytes.sublist(strAddr + 4, strAddr + 4 + strLen), allowMalformed: true);
              print('    → name: "$str"');
            }
          }
        }
      }
    } else {
      print('    NOT PRESENT');
    }
  }

  // Try to read field[2] = type
  if (numFields > 2) {
    final f2Off = bd.getUint16(vtableStart + 4 + 2 * 2, Endian.little);
    print('  field[2] vtableOff=$f2Off (type)');
    if (f2Off > 0) {
      final f2Addr = tableStart + f2Off;
      if (f2Addr + 4 <= valStart + valLen) {
        final type = bd.getInt32(f2Addr, Endian.little);
        print('    type=$type (${_obxType(type)})');
      }
    } else {
      print('    NOT PRESENT');
    }
  }

  // Try to read field[3] = flags
  if (numFields > 3) {
    final f3Off = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
    print('  field[3] vtableOff=$f3Off (flags)');
    if (f3Off > 0) {
      final f3Addr = tableStart + f3Off;
      if (f3Addr + 4 <= valStart + valLen) {
        final flags = bd.getInt32(f3Addr, Endian.little);
        print('    flags=$flags  isId=${flags & 1 != 0}');
      }
    } else {
      print('    NOT PRESENT');
    }
  }
}

String _obxType(int t) {
  const names = {
    1: 'Bool', 2: 'Byte', 3: 'Short', 4: 'Char',
    5: 'Int', 6: 'Long', 7: 'Float', 8: 'Double', 9: 'String',
    10: 'Date', 11: 'Relation', 12: 'DateNano', 13: 'Flex',
  };
  return names[t] ?? 'Type_$t';
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
