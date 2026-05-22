import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/objectbox_model.dart';

/// Service to read ObjectBox data from data.mdb directly,
/// with NO dependency on objectbox-model.json.
class ObjectBoxService {
  Future<ObjectBoxModel> openDatabase(String dbPath) async {
    final dir = Directory(dbPath);
    if (!await dir.exists()) throw Exception('Database directory not found: $dbPath');
    final dataFile = File(p.join(dbPath, 'data.mdb'));
    if (!await dataFile.exists()) throw Exception('data.mdb not found in $dbPath');
    final bytes = await dataFile.readAsBytes();
    return _ObxParser(bytes).discoverModel();
  }

  Future<Map<String, int>> getDbFileInfo(String dbPath) async {
    final dir = Directory(dbPath);
    final info = <String, int>{};
    if (!await dir.exists()) return info;
    await for (final entity in dir.list()) {
      if (entity is File) info[p.basename(entity.path)] = await entity.length();
    }
    return info;
  }

  Future<List<EntityRow>> readEntityData(String dbPath, EntityInfo entity) async {
    final dataFile = File(p.join(dbPath, 'data.mdb'));
    if (!await dataFile.exists()) throw Exception('data.mdb not found in $dbPath');
    final bytes = await dataFile.readAsBytes();
    return _ObxParser(bytes).readEntityData(entity);
  }
}

// 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕
// LMDB / ObjectBox parser
// 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕

class _ObxParser {
  late final Uint8List _data;
  late final ByteData _bd;
  late int _pageSize;
  late int _numPages;
  late int _magicOffset;

  _ObxParser(Uint8List rawBytes) {
    _data = rawBytes;
    _bd = ByteData.sublistView(_data);
    _magicOffset = 0;
    if (_data.length >= 20 && _bd.getUint32(16, Endian.little) == 0xBEEFC0DE) {
      _magicOffset = 16;
    }

    // ObjectBox keeps the 16-byte file prefix inside page 0, so page boundaries
    // are still aligned to the raw file, not to the LMDB magic offset.
    final pageSizeOffset = _magicOffset == 16 ? 40 : 24;
    _pageSize = _data.length > pageSizeOffset + 4
        ? _bd.getUint32(pageSizeOffset, Endian.little)
        : 4096;
    if (_pageSize < 512 || _pageSize > 65536) _pageSize = 4096;
    _numPages = _data.length ~/ _pageSize;
  }

  bool get isValid =>
      _data.length >= _pageSize &&
      _magicOffset + 4 <= _data.length &&
      _bd.getUint32(_magicOffset, Endian.little) == 0xBEEFC0DE;

  // 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸?Model Discovery 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑?
  ObjectBoxModel discoverModel() {
    if (!isValid) return ObjectBoxModel.discovered([]);

    final schemaEntities = _discoverSchemaEntries();
    if (schemaEntities.isNotEmpty) {
      return _buildModel(schemaEntities);
    }
    
    // APPROACH: String search for entity names in data
    // In discovered mode, schema is stored as raw FlatBuffers
    // We search for known entity name patterns
    
    final entities = <_ParsedEntity>[];
    final seenNames = <String>{};

    // Search for Entity FlatBuffers by looking for name strings
    // Common pattern: entity names end with "Entity" in Dart
    final candidateNames = _findEntityNames();
    
    for (final name in candidateNames) {
      if (seenNames.contains(name)) continue;
      seenNames.add(name);
      
      final entity = _parseEntityByName(name);
      if (entity != null) entities.add(entity);
    }

    // Also try generic scan for FlatBuffer vtables
    if (entities.isEmpty) {
      entities.addAll(_scanForEntityVtables());
    }

    return _buildModel(entities);
  }

  ObjectBoxModel _buildModel(List<_ParsedEntity> entities) {
    entities.sort((a, b) {
      if (a.id == 0 && b.id == 0) return 0;
      if (a.id == 0) return 1;
      if (b.id == 0) return -1;
      return a.id.compareTo(b.id);
    });
    final model = ObjectBoxModel.discovered([]);
    var entityIdCounter = 1;
    for (final e in entities) {
      final entityInfo = EntityInfo.discovered(e.name);
      entityInfo.id = (e.id > 0 ? e.id : entityIdCounter).toString();
      entityInfo.properties.clear();
      for (final f in e.properties) {
        entityInfo.properties.add(PropertyInfo(
          id: f.propId.toString(),
          name: f.name,
          type: f.obxType,
          flags: f.isId ? 1 : 0,
        ));
      }
      model.entities.add(entityInfo);
      entityIdCounter++;
    }
    return model;
  }

  List<_ParsedEntity> _discoverSchemaEntries() {
    final entitiesById = <int, _ParsedEntity>{};
    for (var pgno = 0; pgno < _numPages; pgno++) {
      final page = _readPage(pgno);
      if (page == null) continue;
      for (final entry in page.entries) {
        if (!entry.isSchema || entry.entityId == 0) continue;
        final parsed = _parseSchemaEntry(entry);
        if (parsed == null || parsed.name.isEmpty) continue;
        if (parsed.name.length < 2 || !_isPrintable(parsed.name)) continue;
        entitiesById[entry.entityId] = parsed;
      }
    }
    return entitiesById.values.toList();
  }

  List<String> _findEntityNames() {
    final names = <String>[];
    final found = <String>{};
    
    // Search for strings ending with "Entity" (Dart convention)
    for (var i = 0; i < _data.length - 20; i++) {
      if (_data[i] >= 65 && _data[i] <= 122) {  // Start of potential string
        var end = i;
        while (end < _data.length && _data[end] >= 32 && _data[end] <= 122) {
          end++;
        }
        
        if (end - i >= 5 && end - i <= 50) {
          final str = utf8.decode(_data.sublist(i, end), allowMalformed: true);
          if (str.endsWith('Entity') && _isPrintable(str) && !found.contains(str)) {
            found.add(str);
            names.add(str);
          }
        }
        i = end - 1;
      }
    }
    
    return names;
  }

  List<_ParsedEntity> _scanForEntityVtables() {
    final entities = <_ParsedEntity>[];
    final seen = <int>{};
    var entityIdCounter = 1;
    
    // Scan for vtable headers (size between 4-256, even)
    for (var i = 0; i < _data.length - 4; i++) {
      final vtableSize = _bd.getUint16(i, Endian.little);
      if (vtableSize >= 8 && vtableSize <= 128 && vtableSize % 2 == 0) {
        // Possible vtable, check if it's followed by table
        if (i + vtableSize <= _data.length) {
          // Look for table start (usually a few bytes after vtable)
          final tableStart = i + vtableSize;
          if (tableStart + 4 <= _data.length) {
            final vtableSOff = _bd.getInt32(tableStart, Endian.little);
            if (vtableSOff > 0 && vtableSOff <= vtableSize) {
              // This looks like a FlatBuffer table
              final parsed = _tryParseEntityAt(tableStart, entityIdCounter);
              if (parsed != null && !seen.contains(parsed.id)) {
                seen.add(parsed.id);
                entities.add(parsed);
                entityIdCounter++;
              }
            }
          }
        }
      }
    }
    
    return entities;
  }

  _ParsedEntity? _parseEntityByName(String name) {
    // Search for the name string in data
    final nameBytes = utf8.encode(name);
    
    for (var i = 0; i < _data.length - nameBytes.length; i++) {
      var match = true;
      for (var j = 0; j < nameBytes.length; j++) {
        if (_data[i + j] != nameBytes[j]) { match = false; break; }
      }
      
      if (match) {
        // Found the string, try to parse Entity FlatBuffer backwards
        return _tryParseEntityNearby(i);
      }
    }
    
    return null;
  }

  _ParsedEntity? _tryParseEntityNearby(int strOffset) {
    var entityId = 0;
    
    // Scan backwards from string to find vtable
    for (var j = strOffset; j > strOffset - 500 && j >= 0; j -= 4) {
      final vtableSOff = _bd.getInt32(j, Endian.little);
      if (vtableSOff > 0 && vtableSOff < 256) {
        final vtableStart = j - vtableSOff;
        if (vtableStart >= 0 && vtableStart + 2 <= _data.length) {
          final vtableSize = _bd.getUint16(vtableStart, Endian.little);
          if (vtableSize >= 8 && vtableSize <= 128) {
            final numFields = (vtableSize - 4) ~/ 2;
            
            // Try to read field[3] as name
            if (numFields > 3) {
              final nameFieldOff = _bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
              if (nameFieldOff > 0) {
                final nameAddr = j + nameFieldOff;
                if (nameAddr + 4 <= _data.length) {
                  final strOff = _bd.getUint32(nameAddr, Endian.little);
                  if (strOff > 0) {
                    final strAddr = nameAddr + strOff;
                    if (strAddr + 4 <= _data.length) {
                      final strLen = _bd.getUint32(strAddr, Endian.little);
                      if (strLen > 0 && strLen < 100) {
                        final name = utf8.decode(_data.sublist(strAddr + 4, strAddr + 4 + strLen), allowMalformed: true);
                        if (_isPrintable(name)) {
                          // Successfully parsed entity!
                          final props = <_ParsedProperty>[];
                          
                          // Try to read properties from field[4]
                          if (numFields > 4) {
                            final propsFieldOff = _bd.getUint16(vtableStart + 4 + 4 * 2, Endian.little);
                            if (propsFieldOff > 0) {
                              props.addAll(_parsePropertiesVector(j + propsFieldOff));
                            }
                          }
                          
                          return _ParsedEntity(entityId, name, props);
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
    
    return null;
  }

  _ParsedEntity? _tryParseEntityAt(int tableStart, int entityId) {
    if (tableStart + 4 > _data.length) return null;
    
    final vtableSOff = _bd.getInt32(tableStart, Endian.little);
    if (vtableSOff <= 0 || vtableSOff > 256) return null;
    
    final vtableStart = tableStart - vtableSOff;
    if (vtableStart < 0 || vtableStart + 2 > _data.length) return null;
    
    final vtableSize = _bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 8 || vtableSize > 128) return null;
    
    final numFields = (vtableSize - 4) ~/ 2;
    
    // Try field[3] for name
    if (numFields > 3) {
      final nameFieldOff = _bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
      if (nameFieldOff > 0) {
        final nameAddr = tableStart + nameFieldOff;
        if (nameAddr + 4 <= _data.length) {
          final strOff = _bd.getUint32(nameAddr, Endian.little);
          if (strOff > 0) {
            final strAddr = nameAddr + strOff;
            if (strAddr + 4 <= _data.length) {
              final strLen = _bd.getUint32(strAddr, Endian.little);
              if (strLen > 0 && strLen < 100 && strAddr + 4 + strLen <= _data.length) {
                final name = utf8.decode(_data.sublist(strAddr + 4, strAddr + 4 + strLen), allowMalformed: true);
                if (_isPrintable(name)) {
                  final props = <_ParsedProperty>[];
                  
                  if (numFields > 4) {
                    final propsFieldOff = _bd.getUint16(vtableStart + 4 + 4 * 2, Endian.little);
                    if (propsFieldOff > 0) {
                      props.addAll(_parsePropertiesVector(tableStart + propsFieldOff));
                    }
                  }
                  
                  return _ParsedEntity(entityId, name, props);
                }
              }
            }
          }
        }
      }
    }
    
    return null;
  }

  // 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸?Entity Data 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑?
  List<EntityRow> readEntityData(EntityInfo entity) {
    if (!isValid) return [];
    final rowMap = <int, EntityRow>{};

    final entityId = int.tryParse(entity.id);
    for (var pgno = 0; pgno < _numPages; pgno++) {
      final page = _readPage(pgno);
      if (page == null) continue;

      for (final entry in page.entries) {
        if (entry.isSchema) continue;
        if (entityId != null && entry.entityId != entityId) continue;

        final row = _parseDataEntry(entry, entity);
        if (row == null) continue;
        rowMap[row.id] = row;
      }
    }
    
    final rows = rowMap.values.toList();
    rows.sort((a, b) => a.id.compareTo(b.id));
    return rows;
  }

  // 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸?Page Reading 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕

  _PageData? _readPage(int pgno) {
    if (pgno < 0 || pgno >= _numPages) return null;
    final off = pgno * _pageSize;
    if (off + 16 > _data.length) return null;

    // ObjectBox LMDB page header: pgno(8) + flags(2) + type(2) +
    // lower(2) + upper(2), then 16-bit entry pointers.
    final lower = _bd.getUint16(off + 12, Endian.little);
    if (lower < 16 || lower > _pageSize) return null;

    final numPtrs = (lower - 16) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = _bd.getUint16(off + 16 + i * 2, Endian.little);
      if (ptr > 0 && ptr < _pageSize) ptrs.add(ptr);
    }
    if (ptrs.isEmpty) return _PageData(pgno, []);
    ptrs.sort();
    final uniquePtrs = <int>[ptrs.first];
    for (var i = 1; i < ptrs.length; i++) {
      if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
    }
    final entries = <_EntryData>[];
    for (var i = 0; i < uniquePtrs.length; i++) {
      final entryStart = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length) ? uniquePtrs[i + 1] : _pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;
      entries.add(_EntryData(off, entryStart, entryLen, _data, _bd));
    }
    return _PageData(pgno, entries);
  }

  // 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸?Schema Parsing 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜?  // All address parameters are ABSOLUTE offsets into _data/_bd.

  _ParsedEntity? _parseSchemaEntry(_EntryData entry) {
    final absEntry = entry.absEntry;
    final valStart = absEntry + 16;
    final valLen = entry.length - 16;
    if (valLen < 8) return null;

    final rootOff = _bd.getUint32(valStart, Endian.little);
    if (rootOff == 0 || rootOff >= valLen) return null;
    final tableStart = valStart + rootOff;

    final vtableSOff = _bd.getInt32(tableStart, Endian.little);
    int vtableStart;
    if (vtableSOff > 0) {
      vtableStart = tableStart - vtableSOff;
    } else if (vtableSOff < 0) {
      vtableStart = tableStart - vtableSOff;
    } else {
      return null;
    }

    if (vtableStart < valStart || vtableStart + 4 > valStart + valLen) return null;

    final vtableSize = _bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 4 || vtableSize > 256) return null;
    final numFields = (vtableSize - 4) ~/ 2;

    String? entityName;
    List<_ParsedProperty> properties = [];

    // Schema entries in ObjectBox DBs use field[1]/field[2] for name/properties.
    // Some raw schema fragments found by string scanning use field[3]/field[4].
    for (final nameFieldIndex in const [1, 3]) {
      if (entityName != null && entityName.isNotEmpty) break;
      if (numFields <= nameFieldIndex) continue;
      final nameFieldOff =
          _bd.getUint16(vtableStart + 4 + nameFieldIndex * 2, Endian.little);
      if (nameFieldOff > 0) {
        final name = _readFbString(valStart, tableStart + nameFieldOff, valStart + valLen);
        if (name != null && name.isNotEmpty) entityName = name;
      }
    }

    for (final propsFieldIndex in const [2, 4]) {
      if (properties.isNotEmpty) break;
      if (numFields <= propsFieldIndex) continue;
      final propsFieldOff =
          _bd.getUint16(vtableStart + 4 + propsFieldIndex * 2, Endian.little);
      if (propsFieldOff > 0) {
        properties = _parsePropertiesVector(tableStart + propsFieldOff);
      }
    }

    if (entityName == null || entityName.isEmpty) {
      for (var fi = 0; fi < numFields; fi++) {
        final fieldOff = _bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
        if (fieldOff == 0) continue;
        final candidate = _readFbString(valStart, tableStart + fieldOff, valStart + valLen);
        if (candidate != null && candidate.length > 2 && _isPrintable(candidate)) {
          entityName = candidate;
          break;
        }
      }
    }

    if (entityName == null || entityName.isEmpty) {
      final strings = _extractPrintableStrings(valStart, valStart + valLen, 2);
      if (strings.isEmpty) return null;
      entityName = strings.first;
    }

    return _ParsedEntity(entry.entityId, entityName, properties);
  }

  List<_ParsedProperty> _parsePropertiesVector(int fieldAddr) {
    final result = <_ParsedProperty>[];

    if (fieldAddr + 4 > _data.length) return result;
    final vecOff = _bd.getUint32(fieldAddr, Endian.little);
    if (vecOff < 4 || vecOff > 10000) return result;

    final vecAddr = fieldAddr + vecOff;
    if (vecAddr + 4 > _data.length) return result;

    final vecLen = _bd.getUint32(vecAddr, Endian.little);
    if (vecLen <= 0 || vecLen > 100) return result;

    for (var i = 0; i < vecLen; i++) {
      final elemOffAddr = vecAddr + 4 + i * 4;
      if (elemOffAddr + 4 > _data.length) break;

      final elemOff = _bd.getUint32(elemOffAddr, Endian.little);
      if (elemOff == 0) continue;

      final propTableAddr = elemOffAddr + elemOff;
      if (propTableAddr + 4 > _data.length) continue;

      final prop = _parsePropertyTable(propTableAddr, i);
      if (prop != null) result.add(prop);
    }

    return result;
  }

  _ParsedProperty? _parsePropertyTable(int tableStart, int propIndex) {
    if (tableStart + 4 > _data.length) return null;

    final vtableSOff = _bd.getInt32(tableStart, Endian.little);
    if (vtableSOff <= 0) return null;

    final vtableStart = tableStart - vtableSOff;
    if (vtableStart < 0 || vtableStart + 2 > _data.length) return null;

    final vtableSize = _bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 8 || vtableSize > 128) return null;
    final numFields = (vtableSize - 4) ~/ 2;

    String? name;
    int obxType = 0;
    int flags = 0;

    if (numFields > 0) {
      final nameOff = _bd.getUint16(vtableStart + 4, Endian.little);
      if (nameOff > 0) {
        final nameFieldAddr = tableStart + nameOff;
        name = _readFbStringInline(nameFieldAddr);
      }
    }

    if (numFields > 1) {
      final typeOff = _bd.getUint16(vtableStart + 4 + 1 * 2, Endian.little);
      if (typeOff > 0) {
        final typeFieldAddr = tableStart + typeOff;
        if (typeFieldAddr + 4 <= _data.length) {
          obxType = _bd.getInt32(typeFieldAddr, Endian.little);
        }
      }
    }

    if (numFields > 2) {
      final flagsOff = _bd.getUint16(vtableStart + 4 + 2 * 2, Endian.little);
      if (flagsOff > 0) {
        final flagsFieldAddr = tableStart + flagsOff;
        if (flagsFieldAddr + 4 <= _data.length) {
          flags = _bd.getInt32(flagsFieldAddr, Endian.little);
        }
      }
    }

    if (name == null || name.isEmpty) return null;

    return _ParsedProperty(
      propId: propIndex + 1,
      name: name,
      obxType: obxType,
      isId: name == 'id' || (flags & 1) != 0,
    );
  }

  String? _readFbStringInline(int fieldAddr) {
    if (fieldAddr + 4 > _data.length) return null;
    final strOff = _bd.getUint32(fieldAddr, Endian.little);
    if (strOff < 4 || strOff > 10000) return null;
    final strAddr = fieldAddr + strOff;
    if (strAddr + 4 > _data.length) return null;
    final strLen = _bd.getUint32(strAddr, Endian.little);
    if (strLen <= 0 || strLen > 1000) return null;
    if (strAddr + 4 + strLen > _data.length) return null;
    return String.fromCharCodes(_data.sublist(strAddr + 4, strAddr + 4 + strLen));
  }

  // [valStart]=absolute start of value, [fieldAddr]=absolute address of uint32 string offset
  // [valEnd]=absolute end of value
  String? _readFbString(int valStart, int fieldAddr, int valEnd) {
    if (fieldAddr + 4 > valEnd) return null;
    final strOff = _bd.getUint32(fieldAddr, Endian.little);
    if (strOff == 0) return null;
    final strAddr = fieldAddr + strOff;
    if (strAddr < valStart || strAddr + 4 > valEnd) return null;
    final strLen = _bd.getUint32(strAddr, Endian.little);
    if (strLen <= 0 || strLen > 10000 || strAddr + 4 + strLen > valEnd) return null;
    try {
      final str = utf8.decode(_data.sublist(strAddr + 4, strAddr + 4 + strLen), allowMalformed: true);
      return str.isNotEmpty ? str : null;
    } catch (_) {
      return null;
    }
  }

  // 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸?Data Entry Parsing 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜?
  EntityRow? _parseDataEntry(_EntryData entry, EntityInfo entity) {
    final absEntry = entry.absEntry;
    final valStart = absEntry + 16;
    final valLen = entry.length - 16;
    if (valLen < 4) return null;

    final rootOffset = _bd.getUint32(valStart, Endian.little);
    if (rootOffset == 0 || rootOffset >= valLen) {
      final strings = _extractPrintableStrings(valStart, valStart + valLen, 1);
      final values = <String, dynamic>{'id': entry.objectId};
      for (var i = 0; i < strings.length && i < 10; i++) {
        values['field_$i'] = strings[i];
      }
      return EntityRow(id: entry.objectId, values: values);
    }

    final tableStart = valStart + rootOffset;
    if (tableStart + 4 > valStart + valLen) return null;

    final vtableSOff = _bd.getInt32(tableStart, Endian.little);
    if (vtableSOff <= 0) return null;

    final vtableStart = tableStart - vtableSOff;
    if (vtableStart < valStart || vtableStart + 4 > valStart + valLen) return null;

    final vtableSize = _bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 4 || vtableSize > 256) return null;
    final numFields = (vtableSize - 4) ~/ 2;

    final values = <String, dynamic>{'id': entry.objectId};
    final props = entity.properties;

    for (var fi = 0; fi < numFields; fi++) {
      final fieldOff = _bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
      if (fieldOff == 0) continue;

      final fieldAddr = tableStart + fieldOff;
      if (fieldAddr + 8 > valStart + valLen) continue;

      final PropertyInfo prop;
      if (fi < props.length) {
        prop = props[fi];
        if (prop.isId) continue;
      } else {
        while (props.length <= fi) {
          props.add(PropertyInfo.discovered(props.length, PropertyType.unknown));
        }
        prop = props[fi];
      }

      final val = _readFieldValue(valStart, fieldAddr, valStart + valLen);
      if (val != null) {
        values[prop.name] = val;
        if (prop.type == PropertyType.unknown.value) {
          props[fi] = PropertyInfo.discovered(fi, _inferPropertyType(val));
        }
      }
    }

    return EntityRow(id: entry.objectId, values: values);
  }

  PropertyType _inferPropertyType(dynamic value) {
    if (value is bool) return PropertyType.discoveredBool;
    if (value is int) return PropertyType.discoveredLong;
    if (value is double) return PropertyType.discoveredDouble;
    if (value is String) return PropertyType.discoveredString;
    return PropertyType.unknown;
  }

  dynamic _readFieldValue(int valStart, int addr, int valEnd) {
    // 1) Try string
    try {
      final strOff = _bd.getUint32(addr, Endian.little);
      if (strOff >= 4) {
        final strAddr = addr + strOff;
        if (strAddr + 4 <= valEnd) {
          final strLen = _bd.getUint32(strAddr, Endian.little);
          if (strLen > 0 && strLen < 10000 && strAddr + 4 + strLen <= valEnd) {
            final str = utf8.decode(_data.sublist(strAddr + 4, strAddr + 4 + strLen), allowMalformed: true);
            if (str.isNotEmpty) return str;
          }
        }
      }
    } catch (_) {}

    // 2) Try bool
    try {
      final b = _data[addr];
      if (b <= 1) {
        if (addr + 1 < _data.length && _data[addr + 1] == 0) {
          return b == 1;
        }
      }
    } catch (_) {}

    // 3) Try int64 / timestamp
    try {
      final v = _bd.getInt64(addr, Endian.little);
      if (v > 0 && v < 0x7FFFFFFFFFFFFFFF) {
        if (v > 1577836800000000000 && v < 1893456000000000000) {
          return DateTime.fromMicrosecondsSinceEpoch(v ~/ 1000).toIso8601String();
        }
        if (v > 1577836800000 && v < 1893456000000) {
          return DateTime.fromMillisecondsSinceEpoch(v).toIso8601String();
        }
        return v;
      }
    } catch (_) {}

    // 4) Try int32
    try {
      final v = _bd.getInt32(addr, Endian.little);
      return v;
    } catch (_) {}

    // 5) Try double
    try {
      final v = _bd.getFloat64(addr, Endian.little);
      if (v.isFinite && v.abs() > 1e-10 && v.abs() < 1e20) return v;
    } catch (_) {}

    return null;
  }

  // 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸?Helpers 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑?
  bool _isPrintable(String s) {
    return s.runes.every((r) => (r >= 0x20 && r <= 0x7E) || (r >= 0x4E00 && r <= 0x9FFF));
  }

  List<String> _extractPrintableStrings(int start, int end, int minLen) {
    final strings = <String>[];
    final buf = <int>[];
    for (var i = start; i < end && i < _data.length; i++) {
      final b = _data[i];
      if (b >= 32 && b < 127 || b >= 0x80) {
        buf.add(b);
      } else {
        if (buf.length >= minLen) {
          try {
            final s = utf8.decode(buf, allowMalformed: true);
            if (s.trim().isNotEmpty && _isMostlyPrintable(s)) strings.add(s.trim());
          } catch (_) {}
        }
        buf.clear();
      }
    }
    if (buf.length >= minLen) {
      try {
        final s = utf8.decode(buf, allowMalformed: true);
        if (s.trim().isNotEmpty && _isMostlyPrintable(s)) strings.add(s.trim());
      } catch (_) {}
    }
    return strings;
  }

  bool _isMostlyPrintable(String s) {
    if (s.isEmpty) return false;
    final printable = s.runes.where((r) => r >= 0x20 && r <= 0x7E || r >= 0x4E00 && r <= 0x9FFF).length;
    return printable >= s.length * 0.4;
  }
}

// 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸?Data Structures 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕

class _PageData {
  final int pgno;
  final List<_EntryData> entries;
  _PageData(this.pgno, this.entries);
}

class _EntryData {
  final int pageOffset;
  final int entryOffset;
  final int length;
  final Uint8List _data;
  final ByteData _bd;

  _EntryData(this.pageOffset, this.entryOffset, this.length, this._data, this._bd);

  int get absEntry => pageOffset + entryOffset;

  int get entityId => _data[absEntry + 15];

  int get objectId => absEntry;

  bool get isSchema {
    // Schema entry: key bytes 8-14 are zero and the value is a FlatBuffer.
    // Byte 15 stores the real entity ID and must not be required to be zero.
    for (var i = 8; i <= 14; i++) {
      if (_data[absEntry + i] != 0) return false;
    }
    final valLen = length - 16;
    if (valLen < 4) return false;
    final rootOff = _bd.getUint32(absEntry + 16, Endian.little);
    return rootOff > 0 && rootOff < valLen;
  }

  Uint8List get value {
    final abs = absEntry + 16;
    final valLen = length - 16;
    if (valLen <= 0) return Uint8List(0);
    return Uint8List.sublistView(_data, abs, abs + valLen);
  }
}

class _ParsedEntity {
  final int id;
  final String name;
  final List<_ParsedProperty> properties;
  _ParsedEntity(this.id, this.name, this.properties);
}

class _ParsedProperty {
  final int propId;
  final String name;
  final int obxType;
  final bool isId;
  _ParsedProperty({required this.propId, required this.name, required this.obxType, required this.isId});
}
