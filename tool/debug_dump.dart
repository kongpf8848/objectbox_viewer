import 'dart:io';
import 'dart:typed_data';

void main() {
  final bytes = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  
  final magic = bd.getUint32(16, Endian.little);
  print('Magic: 0x${magic.toRadixString(16)}');
  if (magic != 0xBEEFC0DE) { print('Not ObjectBox'); return; }
  
  final pageSize = bd.getUint32(40, Endian.little);
  print('Page size: $pageSize');
  final numPages = bytes.length ~/ pageSize;
  print('Total pages: $numPages');
  
  // Scan all pages for entries
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
      
      // Read 16-byte key
      final key = bytes.sublist(absEntry, absEntry + 16);
      
      // Object ID = first 8 bytes as uint64
      final objectId = bd.getUint64(absEntry, Endian.little);
      // Entity ID = byte 15
      final entityId = bytes[absEntry + 15];
      // Is schema? bytes 8-14 all zero
      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) { isSchema = false; break; }
      }
      
      final valueLen = entryLen - 16;
      
      if (isSchema) {
        print('\n=== SCHEMA ENTRY: entityId=$entityId objectId=$objectId valueLen=$valueLen ===');
        // Print first 100 bytes of value as hex
        final valStart = absEntry + 16;
        final showLen = valueLen > 100 ? 100 : valueLen;
        final hex = bytes.sublist(valStart, valStart + showLen).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        print('Value hex: $hex');
        // Try to find strings
        final str = _extractStrings(bytes, valStart, valueLen);
        if (str.isNotEmpty) print('Strings: $str');
      } else {
        print('\n--- DATA ENTRY: entityId=$entityId objectId=$objectId valueLen=$valueLen ---');
        // Parse FlatBuffer
        final valStart = absEntry + 16;
        if (valueLen >= 4) {
          final rootOff = bd.getUint32(valStart, Endian.little);
          print('  rootOffset: $rootOff');
          if (rootOff > 0 && rootOff < valueLen) {
            final tableStart = valStart + rootOff;
            final vtableSOff = bd.getInt32(tableStart, Endian.little);
            print('  vtableSignedOffset: $vtableSOff');
            if (vtableSOff > 0) {
              final vtableStart = tableStart - vtableSOff;
              final vtableSize = bd.getUint16(vtableStart, Endian.little);
              final tableInline = bd.getUint16(vtableStart + 2, Endian.little);
              print('  vtableSize: $vtableSize tableInline: $tableInline');
              final numFields = (vtableSize - 4) ~/ 2;
              for (var fi = 0; fi < numFields; fi++) {
                final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
                if (fieldOff == 0) continue;
                final fieldAddr = tableStart + fieldOff;
                print('  field[$fi] offset=$fieldOff');
                
                // Try string
                final strOff = bd.getUint32(fieldAddr, Endian.little);
                if (strOff >= 4 && strOff < valueLen) {
                  final strAddr = fieldAddr + strOff;
                  if (strAddr + 4 <= bytes.length) {
                    final strLen = bd.getUint32(strAddr, Endian.little);
                    if (strLen > 0 && strLen < 10000 && strAddr + 4 + strLen <= bytes.length) {
                      try {
                        final s = String.fromCharCodes(bytes.sublist(strAddr + 4, strAddr + 4 + strLen));
                        final printable = s.runes.where((r) => r >= 0x20 && r <= 0x7e).length;
                        if (printable >= s.length * 0.3 && s.trim().isNotEmpty) {
                          print('    → STRING: "$s"');
                        }
                      } catch (_) {}
                    }
                  }
                }
                
                // Try int64
                final i64 = bd.getInt64(fieldAddr, Endian.little);
                if (i64 > 0 && i64 < 0x7FFFFFFFFFFFFFFF) {
                  print('    → INT64: $i64');
                  // Check timestamp
                  if (i64 > 1700000000000000000 && i64 < 1800000000000000000) {
                    print('    → TIMESTAMP(ns): ${DateTime.fromMicrosecondsSinceEpoch(i64 ~/ 1000)}');
                  } else if (i64 > 1700000000000 && i64 < 1800000000000) {
                    print('    → TIMESTAMP(ms): ${DateTime.fromMillisecondsSinceEpoch(i64.toInt())}');
                  }
                }
                
                // Try bool
                final b0 = bytes[fieldAddr];
                if (b0 <= 1) print('    → BOOL?: $b0');
              }
            }
          }
        }
      }
    }
  }
}

List<String> _extractStrings(Uint8List bytes, int start, int len) {
  final strings = <String>[];
  final buf = <int>[];
  for (var i = start; i < start + len && i < bytes.length; i++) {
    final b = bytes[i];
    if (b >= 32 && b < 127) {
      buf.add(b);
    } else {
      if (buf.length >= 3) {
        try {
          strings.add(String.fromCharCodes(buf));
        } catch (_) {}
      }
      buf.clear();
    }
  }
  if (buf.length >= 3) {
    try { strings.add(String.fromCharCodes(buf)); } catch (_) {}
  }
  return strings;
}
