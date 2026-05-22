// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Based on the discovered schema, properly parse ALL Entity and Property FlatBuffers.
/// Discovery: entity name is at vtable index 4 (field[4])
void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  print('File size: ${raw.length}');

  // Slice 16-byte prefix
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);
  print('Sliced size: ${data.length}');

  // Process each found TodoEntity FlatBuffer
  // From find_schema2.dart output:
  //   TodoEntity at sliced offset 11784, tableStart=11708
  //   vtableSize=24, numFields=10
  //   entity name at field[4] (vtable[6])

  final entities = [
    {'name': 'TodoEntity', 'strOff': 11784, 'tableStart': 11708},
    {'name': 'UserEntity', 'strOff': 11240, 'tableStart': null},
    {'name': 'StudentEntity', 'strOff': 10964, 'tableStart': null},
  ];

  for (final ent in entities) {
    final strOff = ent['strOff'] as int;
    print('\n=== Entity: ${ent['name']} (str at $strOff) ===');

    // Find the FlatBuffer table containing this string
    // The string is referenced by a field in the table
    // Search backward for a vtable
    var found = false;
    for (var tryOff = strOff; tryOff >= 0 && tryOff >= strOff - 4096; tryOff -= 4) {
      if (tryOff + 4 > data.length) continue;
      final maybeRootOff = bd.getUint32(tryOff, Endian.little);
      if (maybeRootOff == 0 || maybeRootOff >= 4096) continue;

      final tryTableStart = tryOff + maybeRootOff;
      if (tryTableStart + 4 > data.length) continue;

      final vtableSOff = bd.getInt32(tryTableStart, Endian.little);
      if (vtableSOff == 0) continue;

      final tryVtableStart = vtableSOff > 0
          ? tryTableStart - vtableSOff
          : tryTableStart - vtableSOff; // subtract negative
      if (tryVtableStart < 0 || tryVtableStart + 2 > data.length) continue;

      final tryVtableSize = bd.getUint16(tryVtableStart, Endian.little);
      if (tryVtableSize < 4 || tryVtableSize > 2048) continue;

      // Check if this table has a field pointing to our string
      final tryNumFields = (tryVtableSize - 4) ~/ 2;
      for (var f = 0; f < tryNumFields; f++) {
        final fieldOff = bd.getUint16(tryVtableStart + 4 + f * 2, Endian.little);
        if (fieldOff == 0) continue;
        final fieldAddr = tryTableStart + fieldOff;
        if (fieldAddr + 4 > data.length) continue;
        final strOffInField = bd.getUint32(fieldAddr, Endian.little);
        if (strOffInField == 0) continue;
        final tryStrAddr = fieldAddr + strOffInField;
        if (tryStrAddr + 4 > data.length) continue;
        final tryStrLen = bd.getUint32(tryStrAddr, Endian.little);
        if (tryStrLen > 0 && tryStrLen < 1000) {
          final s = utf8.decode(data.sublist(tryStrAddr + 4, tryStrAddr + 4 + tryStrLen),
              allowMalformed: true);
          if (s == ent['name']) {
            print('  FOUND: table at $tryTableStart, vtable at $tryVtableStart');
            print('  vtableSize=$tryVtableSize  numFields=$tryNumFields');
            found = true;

            // Now parse: which vtable index holds the name?
            for (var f2 = 0; f2 < tryNumFields; f2++) {
              final fOff = bd.getUint16(tryVtableStart + 4 + f2 * 2, Endian.little);
              if (fOff == 0) continue;
              final fAddr = tryTableStart + fOff;
              if (fAddr + 4 > data.length) continue;
              final sOff = bd.getUint32(fAddr, Endian.little);
              if (sOff == 0) continue;
              final sAddr = fAddr + sOff;
              if (sAddr + 4 > data.length) continue;
              final sLen = bd.getUint32(sAddr, Endian.little);
              if (sLen > 0 && sLen < 1000) {
                final name = utf8.decode(data.sublist(sAddr + 4, sAddr + 4 + sLen),
                    allowMalformed: true);
                if (name == ent['name']) {
                  print('  → name is at vtable index $f2 (field[$f2])');
                }
              }
            }

            // Parse properties (need to find which field is the properties vector)
            // Try each field to see if it's a vector of FlatBuffers
            for (var f2 = 0; f2 < tryNumFields; f2++) {
              final fOff = bd.getUint16(tryVtableStart + 4 + f2 * 2, Endian.little);
              if (fOff == 0) continue;
              final fAddr = tryTableStart + fOff;
              if (fAddr + 4 > data.length) continue;
              final vecOff = bd.getUint32(fAddr, Endian.little);
              if (vecOff < 4) continue;
              final vecAddr = fAddr + vecOff;
              if (vecAddr + 4 > data.length) continue;
              final vecLen = bd.getUint32(vecAddr, Endian.little);
              if (vecLen > 0 && vecLen < 50) {
                print('  field[$f2]: vector of length $vecLen (possibly properties?)');
                // Try to parse first element as Property FlatBuffer
                if (vecLen > 0) {
                  final elemOffAddr = vecAddr + 4;
                  if (elemOffAddr + 4 <= data.length) {
                    final elemOff = bd.getUint32(elemOffAddr, Endian.little);
                    if (elemOff != 0) {
                      final propAddr = elemOffAddr + elemOff;
                      _parseProperty(data, bd, propAddr);
                    }
                  }
                }
              }
            }
            break;
          }
        }
      }
      if (found) break;
    }
    if (!found) print('  NOT FOUND');
  }
}

void _parseProperty(Uint8List data, ByteData bd, int tableStart) {
  if (tableStart + 4 > data.length) return;
  final vtableSOff = bd.getInt32(tableStart, Endian.little);
  if (vtableSOff == 0) return;
  final vtableStart = vtableSOff > 0 ? tableStart - vtableSOff : tableStart - vtableSOff;
  if (vtableStart < 0 || vtableStart + 4 > data.length) return;

  final vtableSize = bd.getUint16(vtableStart, Endian.little);
  final numFields = (vtableSize - 4) ~/ 2;
  print('    Property: vtableSize=$vtableSize  numFields=$numFields');

  // field[1] = name (string), field[2] = type (int32)
  if (numFields > 1) {
    final nameFieldOff = bd.getUint16(vtableStart + 4 + 1 * 2, Endian.little);
    if (nameFieldOff > 0) {
      final nameAddr = tableStart + nameFieldOff;
      final strOff = bd.getUint32(nameAddr, Endian.little);
      if (strOff > 0) {
        final strAddr = nameAddr + strOff;
        if (strAddr + 4 <= data.length) {
          final strLen = bd.getUint32(strAddr, Endian.little);
          if (strLen > 0 && strLen < 1000) {
            final name = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen),
                allowMalformed: true);
            var type = 0;
            if (numFields > 2) {
              final typeFieldOff = bd.getUint16(vtableStart + 4 + 2 * 2, Endian.little);
              if (typeFieldOff > 0) {
                type = bd.getInt32(tableStart + typeFieldOff, Endian.little);
              }
            }
            print('      "$name"  type=$type');
          }
        }
      }
    }
  }
}
