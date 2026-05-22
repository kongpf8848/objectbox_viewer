// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Find schema entries by scanning for entity name strings.
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  print('File size: ${raw.length}');

  // Slice 16-byte prefix
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);
  print('Sliced size: ${data.length}');

  // Search for "TodoEntity" and other entity names
  final names = ['TodoEntity', 'UserEntity', 'StudentEntity', 'TeacherEntity'];
  final found = <int>[];

  for (final name in names) {
    final bytes = utf8.encode(name);
    print('\nSearching for "$name"...');
    for (var i = 0; i < data.length - bytes.length; i++) {
      var match = true;
      for (var j = 0; j < bytes.length; j++) {
        if (data[i + j] != bytes[j]) { match = false; break; }
      }
      if (match) {
        print('  FOUND at sliced offset $i (0x${i.toRadixString(16)})');
        found.add(i);
      }
    }
  }

  // For each found position, try to find the FlatBuffer table containing it
  print('\n=== Analyzing FlatBuffer structures around found strings ===');
  for (final strOff in found.take(3)) {
    print('\nString at sliced offset $strOff');
    // The string should be referenced by a FlatBuffer table.
    // Search backward for a vtable (starts with uint16 size, followed by offsets)
    var foundTable = false;
    for (var tryOff = strOff; tryOff >= 0 && tryOff >= strOff - 1024; tryOff -= 4) {
      if (tryOff + 4 > data.length) continue;
      final maybeRootOff = bd.getUint32(tryOff, Endian.little);
      if (maybeRootOff == 0 || maybeRootOff >= 4096) continue;

      final tableStart = tryOff + maybeRootOff;
      if (tableStart + 4 > data.length) continue;

      final vtableSOff = bd.getInt32(tableStart, Endian.little);
      if (vtableSOff == 0) continue;

      final vtableStart = vtableSOff > 0 ? tableStart - vtableSOff : tableStart - vtableSOff;
      if (vtableStart < 0 || vtableStart + 2 > data.length) continue;

      final vtableSize = bd.getUint16(vtableStart, Endian.little);
      if (vtableSize < 4 || vtableSize > 2048) continue;

      // Check if this table has a string field pointing to our string
      final numFields = (vtableSize - 4) ~/ 2;
      for (var f = 1; f <= numFields; f++) {
        final fieldOff = bd.getUint16(vtableStart + 4 + (f - 1) * 2, Endian.little);
        if (fieldOff == 0) continue;
        final fieldAddr = tableStart + fieldOff;
        if (fieldAddr + 4 > data.length) continue;
        final strOffInField = bd.getUint32(fieldAddr, Endian.little);
        if (strOffInField == 0) continue;
        final strAddr = fieldAddr + strOffInField;
        if (strAddr + 4 > data.length) continue;
        final strLen = bd.getUint32(strAddr, Endian.little);
        if (strLen > 0 && strLen < 1000) {
          final s = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
              allowMalformed: true);
          if (s == 'TodoEntity' || s == 'UserEntity') {
            print('  FOUND table at tryOff=$tryOff tableStart=$tableStart');
            print('    vtableSize=$vtableSize numFields=$numFields');
            print('    field[$f] = "$s"');
            foundTable = true;
            break;
          }
        }
      }
      if (foundTable) break;
    }
    if (!foundTable) print('  No FlatBuffer table found containing this string');
  }
}
