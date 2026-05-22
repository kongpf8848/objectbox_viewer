import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  final bytes = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  
  final magic = bd.getUint32(16, Endian.little);
  if (magic != 0xBEEFC0DE) { print('Not ObjectBox'); return; }
  
  final pageSize = bd.getUint32(40, Endian.little);
  final numPages = bytes.length ~/ pageSize;
  
  print('=== Scanning ALL entries ===\n');
  
  // Collect ALL entries from all pages
  final allEntries = <Map<String,dynamic>>[];
  
  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 14 > bytes.length) continue;
    
    final type = bd.getUint16(off + 10, Endian.little);
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
      
      // Read full 16-byte key
      final keyBytes = bytes.sublist(absEntry, absEntry + 16);
      final keyHex = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      
      // Object ID from first 8 bytes
      final objectIdU64 = bd.getUint64(absEntry, Endian.little);
      
      // Entity ID from byte 15
      final entityId = bytes[absEntry + 15];
      
      // Check if schema (bytes 8-14 all zero)
      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) { isSchema = false; break; }
      }
      
      // For data entries, also check bytes 8-11 for a different entity ID encoding
      final possibleEntityId32 = bd.getUint32(absEntry + 8, Endian.little);
      
      allEntries.add({
        'pgno': pgno,
        'entryStart': entryStart,
        'absEntry': absEntry,
        'entryLen': entryLen,
        'keyHex': keyHex,
        'objectIdU64': objectIdU64,
        'entityId': entityId,
        'possibleEntityId32': possibleEntityId32,
        'isSchema': isSchema,
        'valueLen': entryLen - 16,
      });
    }
  }
  
  // Print all entries
  for (final e in allEntries) {
    final isSchema = e['isSchema'] as bool;
    final entityId = e['entityId'] as int;
    final entityId32 = e['possibleEntityId32'] as int;
    final objectId = e['objectIdU64'] as int;
    final valueLen = e['valueLen'] as int;
    final keyHex = e['keyHex'] as String;
    
    print('${isSchema ? "SCHEMA" : "DATA "} entityId=$entityId entityId32=$entityId32 objId=$objectId valLen=$valueLen key=$keyHex');
    
    if (!isSchema && valueLen >= 4) {
      final absEntry = e['absEntry'] as int;
      final valStart = absEntry + 16;
      
      // Dump first 80 bytes of value as hex
      final showLen = valueLen > 80 ? 80 : valueLen;
      final hex = bytes.sublist(valStart, valStart + showLen).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('  value[0..$showLen]: $hex');
      
      // Try to find ALL strings in the value using UTF-8
      final strings = _extractStringsUtf8(bytes, valStart, valueLen);
      if (strings.isNotEmpty) print('  strings: $strings');
    }
  }
  
  print('\n=== Summary: DATA entries by entityId ===');
  final byEntity = <int, List<int>>{};
  for (final e in allEntries) {
    if (!(e['isSchema'] as bool)) {
      final eid = e['entityId'] as int;
      byEntity.putIfAbsent(eid, () => []).add(e['objectIdU64'] as int);
    }
  }
  for (final eid in byEntity.keys.toList()..sort()) {
    print('  entityId=$eid: ${byEntity[eid]!.length} entries, objectIds=${byEntity[eid]}');
  }
  
  // Now deep-parse the TodoEntity data entry
  print('\n=== Deep parse TodoEntity (entityId=1) data ===');
  for (final e in allEntries) {
    if (e['isSchema'] as bool) continue;
    if ((e['entityId'] as int) != 1) continue;
    
    final absEntry = e['absEntry'] as int;
    final valStart = absEntry + 16;
    final valueLen = e['valueLen'] as int;
    
    // Dump ENTIRE value
    print('\nFull value ($valueLen bytes):');
    for (var offset = 0; offset < valueLen; offset += 16) {
      final end = offset + 16 > valueLen ? valueLen : offset + 16;
      final hex = bytes.sublist(valStart + offset, valStart + end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      final ascii = bytes.sublist(valStart + offset, valStart + end).map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '.').join();
      print('  ${offset.toString().padLeft(3)}: $hex  $ascii');
    }
    
    // Parse FlatBuffer carefully
    if (valueLen < 4) continue;
    
    final rootOff = bd.getUint32(valStart, Endian.little);
    print('\nrootOffset: $rootOff');
    
    final tableStart = valStart + rootOff;
    final vtableSOff = bd.getInt32(tableStart, Endian.little);
    print('vtableSignedOffset: $vtableSOff');
    
    if (vtableSOff <= 0) { print('Invalid vtable offset'); continue; }
    
    final vtableStart = tableStart - vtableSOff;
    final vtableSize = bd.getUint16(vtableStart, Endian.little);
    final tableInline = bd.getUint16(vtableStart + 2, Endian.little);
    print('vtableSize: $vtableSize tableInline: $tableInline');
    
    final numFields = (vtableSize - 4) ~/ 2;
    print('numFields: $numFields');
    
    for (var fi = 0; fi < numFields; fi++) {
      final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
      if (fieldOff == 0) { print('  field[$fi]: NOT PRESENT'); continue; }
      
      final fieldAddr = tableStart + fieldOff;
      final relToValStart = fieldAddr - valStart;
      print('  field[$fi]: vtableOff=$fieldOff valOffset=$relToValStart');
      
      // Try as uint32 string offset
      final u32 = bd.getUint32(fieldAddr, Endian.little);
      print('    u32: $u32 (0x${u32.toRadixString(16)})');
      
      if (u32 >= 4 && u32 < valueLen) {
        final strAddr = fieldAddr + u32;
        if (strAddr + 4 <= bytes.length) {
          final strLen = bd.getUint32(strAddr, Endian.little);
          print('    -> stringOff: len=$strLen');
          if (strLen > 0 && strLen < 10000 && strAddr + 4 + strLen <= bytes.length) {
            try {
              final strBytes = bytes.sublist(strAddr + 4, strAddr + 4 + strLen);
              final str = utf8.decode(strBytes, allowMalformed: true);
              print('    -> STRING: "$str"');
            } catch (ex) {
              print('    -> decode error: $ex');
            }
          }
        }
      }
      
      // Try as various int sizes
      final i8 = bytes[fieldAddr];
      final i16 = bd.getInt16(fieldAddr, Endian.little);
      final i32 = bd.getInt32(fieldAddr, Endian.little);
      final i64 = bd.getInt64(fieldAddr, Endian.little);
      print('    i8: $i8  i16: $i16  i32: $i32  i64: $i64');
      
      // Check if timestamp
      if (i64 > 1700000000000 && i64 < 1800000000000) {
        print('    -> TIMESTAMP(ms): ${DateTime.fromMillisecondsSinceEpoch(i64)}');
      }
      if (i64 > 1700000000000000 && i64 < 1800000000000000) {
        print('    -> TIMESTAMP(μs): ${DateTime.fromMicrosecondsSinceEpoch(i64)}');
      }
    }
  }
}

List<String> _extractStringsUtf8(Uint8List bytes, int start, int len) {
  final strings = <String>[];
  var i = start;
  final end = start + len;
  while (i < end) {
    // Try to read a uint32 length prefix
    if (i + 4 > bytes.length) break;
    final strLen = ByteData.sublistView(bytes).getUint32(i, Endian.little);
    i += 4;
    if (strLen > 0 && strLen < 10000 && i + strLen <= bytes.length) {
      try {
        final s = utf8.decode(bytes.sublist(i, i + strLen), allowMalformed: true);
        final printable = s.runes.where((r) => r >= 0x20).length;
        if (printable >= s.length * 0.3 && s.trim().isNotEmpty) {
          strings.add(s.trim());
        }
      } catch (_) {}
    }
    i += strLen;
  }
  return strings;
}
