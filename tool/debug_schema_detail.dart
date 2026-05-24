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

      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) {
          isSchema = false;
          break;
        }
      }
      if (!isSchema || bytes[absEntry + 15] == 0) continue;

      final valStart = absEntry + 16;
      final valLen = entryLen - 16;

      print(
        '=== Schema page=$pgno off=$entryStart entityId=${bytes[absEntry + 15]} len=$entryLen ===',
      );
      _parseSchema(bytes, bd, valStart, valLen);
      print('');
    }
  }
}

void _parseSchema(Uint8List bytes, ByteData bd, int valStart, int valLen) {
  if (valLen < 4) return;
  final rootOff = bd.getUint32(valStart, Endian.little);
  if (rootOff == 0 || rootOff >= valLen) return;
  final tableStart = valStart + rootOff;
  if (tableStart + 4 > valStart + valLen) return;

  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  int vtableStart;
  if (vtableSOff > 0) {
    vtableStart = tableStart - vtableSOff;
  } else if (vtableSOff < 0) {
    vtableStart = tableStart - vtableSOff;
  } else
    return;

  if (vtableStart < valStart || vtableStart + 4 > valStart + valLen) return;
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;

  print('Schema table: numFields=$numFields');

  // Parse entity name
  for (final fi in [3, 1]) {
    if (numFields <= fi) continue;
    final off = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
    if (off == 0) continue;
    final name = _readString(bytes, bd, tableStart + off, valStart, valLen);
    if (name != null) {
      print('Entity name: $name');
      break;
    }
  }

  // Parse properties vector
  for (final pi in [4, 2]) {
    if (numFields <= pi) continue;
    final off = bd.getUint16(vtableStart + 4 + pi * 2, Endian.little);
    if (off == 0) continue;
    final props = _parsePropertiesVector(
      bytes,
      bd,
      tableStart + off,
      valStart,
      valLen,
    );
    if (props.isNotEmpty) {
      print('Properties: ${props.length}');
      for (final p in props) {
        print(
          '  prop uid=${p['uid']} fieldIndex=${p['fieldIndex']} seq=${p['seq']} name=${p['name']} type=${p['type']} flags=${p['flags']}',
        );
      }
      break;
    }
  }
}

List<Map<String, dynamic>> _parsePropertiesVector(
  Uint8List bytes,
  ByteData bd,
  int fieldAddr,
  int valStart,
  int valLen,
) {
  final result = <Map<String, dynamic>>[];
  if (fieldAddr + 4 > valStart + valLen) return result;
  final vecOff = bd.getUint32(fieldAddr, Endian.little);
  if (vecOff < 4 || vecOff > 10000) return result;
  final vecAddr = fieldAddr + vecOff;
  if (vecAddr + 4 > valStart + valLen) return result;
  final vecLen = bd.getUint32(vecAddr, Endian.little);
  if (vecLen <= 0 || vecLen > 100) return result;

  for (var i = 0; i < vecLen; i++) {
    final elemOffAddr = vecAddr + 4 + i * 4;
    if (elemOffAddr + 4 > valStart + valLen) break;
    final elemOff = bd.getUint32(elemOffAddr, Endian.little);
    if (elemOff == 0) continue;
    final propTableAddr = elemOffAddr + elemOff;
    if (propTableAddr + 4 > valStart + valLen) continue;
    final prop = _parsePropertyTable(
      bytes,
      bd,
      propTableAddr,
      valStart,
      valLen,
    );
    if (prop != null) result.add(prop);
  }
  return result;
}

Map<String, dynamic>? _parsePropertyTable(
  Uint8List bytes,
  ByteData bd,
  int tableStart,
  int valStart,
  int valLen,
) {
  if (tableStart + 4 > valStart + valLen) return null;
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  if (vtableSOff == 0) return null;
  final vtableStart = tableStart - vtableSOff;
  if (vtableStart < valStart || vtableStart + 4 > valStart + valLen)
    return null;
  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  if (vtableSize < 8 || vtableSize > 128) return null;
  final numFields = (vtableSize - 4) ~/ 2;

  int uid = 0;
  int fieldIndex = 0;
  int seq = 0;
  String? name;
  int type = 0;
  int flags = 0;

  for (var fi = 0; fi < numFields && fi < 10; fi++) {
    final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
    if (fieldOff == 0) continue;
    final fieldAddr = tableStart + fieldOff;
    if (fieldAddr + 4 > valStart + valLen) continue;

    switch (fi) {
      case 0: // id struct (uid, fieldIndex, seq)
        if (fieldAddr + 12 <= valStart + valLen) {
          uid = bd.getInt32(fieldAddr, Endian.little);
          fieldIndex = bd.getInt32(fieldAddr + 4, Endian.little);
          seq = bd.getInt32(fieldAddr + 8, Endian.little);
        }
      case 1: // name
        name = _readString(bytes, bd, fieldAddr, valStart, valLen);
      case 2: // type
        type = bd.getInt32(fieldAddr, Endian.little);
      case 3: // flags
        flags = bd.getInt32(fieldAddr, Endian.little);
    }
  }

  if (name == null || name.isEmpty) return null;
  return {
    'uid': uid,
    'fieldIndex': fieldIndex,
    'seq': seq,
    'name': name,
    'type': type,
    'flags': flags,
  };
}

String? _readString(
  Uint8List bytes,
  ByteData bd,
  int fieldAddr,
  int valStart,
  int valLen,
) {
  if (fieldAddr + 4 > valStart + valLen) return null;
  final strOff = bd.getUint32(fieldAddr, Endian.little);
  if (strOff < 4) return null;
  final strAddr = fieldAddr + strOff;
  if (strAddr + 4 > valStart + valLen) return null;
  final strLen = bd.getUint32(strAddr, Endian.little);
  if (strLen <= 0 || strLen > 10000 || strAddr + 4 + strLen > valStart + valLen)
    return null;
  try {
    return String.fromCharCodes(
      bytes.sublist(strAddr + 4, strAddr + 4 + strLen),
    );
  } catch (_) {
    return null;
  }
}
