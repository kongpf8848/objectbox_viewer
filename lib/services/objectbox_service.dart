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
    if (!await dir.exists())
      throw Exception('Database directory not found: $dbPath');
    final dataFile = File(p.join(dbPath, 'data.mdb'));
    if (!await dataFile.exists())
      throw Exception('data.mdb not found in $dbPath');
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

  Future<List<EntityRow>> readEntityData(
    String dbPath,
    EntityInfo entity,
  ) async {
    final dataFile = File(p.join(dbPath, 'data.mdb'));
    if (!await dataFile.exists())
      throw Exception('data.mdb not found in $dbPath');
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
  late final Set<int> _freedPages;

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
    _freedPages = _collectFreedPages();
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
        entityInfo.properties.add(
          PropertyInfo(
            id: f.propId.toString(),
            name: f.name,
            type: f.obxType,
            flags: f.isId ? 1 : 0,
          ),
        );
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
      if (_data[i] >= 65 && _data[i] <= 122) {
        // Start of potential string
        var end = i;
        while (end < _data.length && _data[end] >= 32 && _data[end] <= 122) {
          end++;
        }

        if (end - i >= 5 && end - i <= 50) {
          final str = utf8.decode(_data.sublist(i, end), allowMalformed: true);
          if (str.endsWith('Entity') &&
              _isPrintable(str) &&
              !found.contains(str)) {
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
        if (_data[i + j] != nameBytes[j]) {
          match = false;
          break;
        }
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
              final nameFieldOff = _bd.getUint16(
                vtableStart + 4 + 3 * 2,
                Endian.little,
              );
              if (nameFieldOff > 0) {
                final nameAddr = j + nameFieldOff;
                if (nameAddr + 4 <= _data.length) {
                  final strOff = _bd.getUint32(nameAddr, Endian.little);
                  if (strOff > 0) {
                    final strAddr = nameAddr + strOff;
                    if (strAddr + 4 <= _data.length) {
                      final strLen = _bd.getUint32(strAddr, Endian.little);
                      if (strLen > 0 && strLen < 100) {
                        final name = utf8.decode(
                          _data.sublist(strAddr + 4, strAddr + 4 + strLen),
                          allowMalformed: true,
                        );
                        if (_isPrintable(name)) {
                          // Successfully parsed entity!
                          final props = <_ParsedProperty>[];

                          // Try to read properties from field[4]
                          if (numFields > 4) {
                            final propsFieldOff = _bd.getUint16(
                              vtableStart + 4 + 4 * 2,
                              Endian.little,
                            );
                            if (propsFieldOff > 0) {
                              props.addAll(
                                _parsePropertiesVector(j + propsFieldOff),
                              );
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
      final nameFieldOff = _bd.getUint16(
        vtableStart + 4 + 3 * 2,
        Endian.little,
      );
      if (nameFieldOff > 0) {
        final nameAddr = tableStart + nameFieldOff;
        if (nameAddr + 4 <= _data.length) {
          final strOff = _bd.getUint32(nameAddr, Endian.little);
          if (strOff > 0) {
            final strAddr = nameAddr + strOff;
            if (strAddr + 4 <= _data.length) {
              final strLen = _bd.getUint32(strAddr, Endian.little);
              if (strLen > 0 &&
                  strLen < 100 &&
                  strAddr + 4 + strLen <= _data.length) {
                final name = utf8.decode(
                  _data.sublist(strAddr + 4, strAddr + 4 + strLen),
                  allowMalformed: true,
                );
                if (_isPrintable(name)) {
                  final props = <_ParsedProperty>[];

                  if (numFields > 4) {
                    final propsFieldOff = _bd.getUint16(
                      vtableStart + 4 + 4 * 2,
                      Endian.little,
                    );
                    if (propsFieldOff > 0) {
                      props.addAll(
                        _parsePropertiesVector(tableStart + propsFieldOff),
                      );
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
    // LMDB B+tree uses copy-on-write, so the same record can appear on
    // multiple pages. We keep only the version from the highest page number
    // (most recent write), keyed by objectId.
    final rowMap = <int, (int pgno, EntityRow row)>{};

    // ObjectBox stores ALL entities in a single LMDB B-tree, sorted by objectId.
    // There is NO entityId in the data entry key — byte 15 of the key is the
    // FlatBuffer objectId (same as field[0] in the value), used for sort order.
    // The only reliable way to distinguish entries from different entities is by
    // comparing the FlatBuffer vtable field count against the entity's schema.
    //
    // Empirically, FlatBuffer numFields = entity.properties.length + 1.
    // The "+1" accounts for an extra ObjectBox-internal field slot in the vtable
    // (likely the objectId field stored at field index 0, which the schema parser
    // counts separately as the "id" property but the vtable always has the slot).
    // More precisely: schema properties includes the id property (flags & 1),
    // and the FlatBuffer vtable also has it, but OBX internally adds one extra
    // slot for metadata — hence numFields is always schema.length + 1.
    final schemaFieldCount = entity.properties.length + 1;

    for (var pgno = 0; pgno < _numPages; pgno++) {
      if (_freedPages.contains(pgno)) continue;
      final page = _readPage(pgno);
      if (page == null) continue;

      for (final entry in page.entries) {
        if (entry.isSchema) continue;

        // Pre-filter: check FlatBuffer field count matches schema before full parse.
        // This distinguishes entries from different entities sharing the same B-tree.
        if (schemaFieldCount > 0 &&
            !_entryMatchesSchema(entry, schemaFieldCount)) {
          continue;
        }

        final row = _parseDataEntry(entry, entity);
        if (row == null) continue;

        // If parsed row has extra discovered fields, it doesn't match this entity schema
        final hasExtraFields = row.values.keys.any(
          (k) => k.startsWith('field_'),
        );
        if (hasExtraFields) continue;

        // Skip invalid/empty entries with objectId == 0
        if (row.id == 0) continue;

        // Keep the version from the highest page number (most recent)
        final existing = rowMap[row.id];
        if (existing == null || pgno > existing.$1) {
          rowMap[row.id] = (pgno, row);
        }
      }
    }

    final rows = rowMap.values.map((e) => e.$2).toList();
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
      final entryEnd = (i + 1 < uniquePtrs.length)
          ? uniquePtrs[i + 1]
          : _pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;
      entries.add(_EntryData(off, entryStart, entryLen, _data, _bd));
    }
    return _PageData(pgno, entries);
  }

  Set<int> _collectFreedPages() {
    final freed = <int>{};
    if (_numPages < 2) return freed;

    // Read both meta pages and pick the active one (higher txnid)
    final meta0Off = 0;
    final meta1Off = _pageSize;

    int activeMetaOff;
    final txnid0 = _readMetaTxnId(meta0Off);
    final txnid1 = _readMetaTxnId(meta1Off);
    if (txnid1 > txnid0) {
      activeMetaOff = meta1Off;
    } else {
      activeMetaOff = meta0Off;
    }

    // MDB_meta::mm_dbs[0] is freeDB, md_root is at offset 40 within MDB_db
    final freeDbOff = activeMetaOff + 16 + 24;
    final freeRoot = _bd.getUint64(freeDbOff + 40, Endian.little);
    if (freeRoot <= 0 || freeRoot >= _numPages) return freed;

    _traverseFreeDb(freeRoot, freed);
    return freed;
  }

  int _readMetaTxnId(int metaPageOff) {
    // MDB_meta::mm_txnid is at offset 24+48+48+8 = 128 from meta page start
    final txnidOff = metaPageOff + 16 + 24 + 48 + 48 + 8;
    if (txnidOff + 8 > _data.length) return 0;
    return _bd.getUint64(txnidOff, Endian.little);
  }

  void _traverseFreeDb(int pgno, Set<int> freed) {
    final off = pgno * _pageSize;
    if (off + 16 > _data.length) return;

    final type = _bd.getUint16(off + 10, Endian.little);

    if (type == 2) {
      // P_LEAF — parse entries directly
      _parseFreeDbLeafPage(pgno, freed);
    } else if (type == 1) {
      // P_BRANCH — read child page numbers from nodes
      final lower = _bd.getUint16(off + 12, Endian.little);
      final numPtrs = (lower - 16) ~/ 2;
      for (var i = 0; i < numPtrs; i++) {
        final ptr = _bd.getUint16(off + 16 + i * 2, Endian.little);
        if (ptr <= 0 || ptr >= _pageSize) continue;
        final entryEnd = (i + 1 < numPtrs)
            ? _bd.getUint16(off + 16 + (i + 1) * 2, Endian.little)
            : _pageSize;
        final entryLen = entryEnd - ptr;
        if (entryLen >= 8) {
          // Child pgno is the last 8 bytes of the branch node
          final childPgno = _bd.getUint64(
            off + ptr + entryLen - 8,
            Endian.little,
          );
          if (childPgno > 0 &&
              childPgno < _numPages &&
              !freed.contains(childPgno)) {
            _traverseFreeDb(childPgno, freed);
          }
        }
      }
    }
  }

  void _parseFreeDbLeafPage(int pgno, Set<int> freed) {
    final off = pgno * _pageSize;
    final lower = _bd.getUint16(off + 12, Endian.little);
    if (lower < 16 || lower > _pageSize) return;

    final numPtrs = (lower - 16) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = _bd.getUint16(off + 16 + i * 2, Endian.little);
      if (ptr > 0 && ptr < _pageSize) ptrs.add(ptr);
    }
    if (ptrs.isEmpty) return;
    ptrs.sort();
    final uniquePtrs = <int>[ptrs.first];
    for (var i = 1; i < ptrs.length; i++) {
      if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
    }

    for (var i = 0; i < uniquePtrs.length; i++) {
      final entryStart = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length)
          ? uniquePtrs[i + 1]
          : _pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;

      final valLen = entryLen - 16;
      if (valLen < 8) continue;

      final valStart = off + entryStart + 16;
      // FreeDB value format: [numPages (uint64), pgno1 (uint64), pgno2, ...]
      final numPages = _bd.getUint64(valStart, Endian.little);
      for (var j = 0; j < numPages; j++) {
        final pgnoOffset = valStart + 8 + j * 8;
        if (pgnoOffset + 8 > off + entryEnd) break;
        final freedPgno = _bd.getUint64(pgnoOffset, Endian.little);
        if (freedPgno > 0 && freedPgno < _numPages) {
          freed.add(freedPgno);
        }
      }
    }
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

    if (vtableStart < valStart || vtableStart + 4 > valStart + valLen)
      return null;

    final vtableSize = _bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 4 || vtableSize > 256) return null;
    final numFields = (vtableSize - 4) ~/ 2;

    String? entityName;
    List<_ParsedProperty> properties = [];

    // ObjectBox Entity FlatBuffer field layout (from actual data analysis):
    //   Modern schema: field[3] = name, field[4] = properties vector
    //   Older schema:  field[1] = name, field[2] = properties vector
    // Try modern layout first (more properties = better match).
    for (final nameFieldIndex in const [3, 1]) {
      if (entityName != null && entityName.isNotEmpty) break;
      if (numFields <= nameFieldIndex) continue;
      final nameFieldOff = _bd.getUint16(
        vtableStart + 4 + nameFieldIndex * 2,
        Endian.little,
      );
      if (nameFieldOff > 0) {
        final name = _readFbString(
          valStart,
          tableStart + nameFieldOff,
          valStart + valLen,
        );
        if (name != null && name.isNotEmpty) entityName = name;
      }
    }

    for (final propsFieldIndex in const [4, 2]) {
      if (properties.isNotEmpty) break;
      if (numFields <= propsFieldIndex) continue;
      final propsFieldOff = _bd.getUint16(
        vtableStart + 4 + propsFieldIndex * 2,
        Endian.little,
      );
      if (propsFieldOff > 0) {
        properties = _parsePropertiesVector(tableStart + propsFieldOff);
      }
    }

    if (entityName == null || entityName.isEmpty) {
      for (var fi = 0; fi < numFields; fi++) {
        final fieldOff = _bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
        if (fieldOff == 0) continue;
        final candidate = _readFbString(
          valStart,
          tableStart + fieldOff,
          valStart + valLen,
        );
        if (candidate != null &&
            candidate.length > 2 &&
            _isPrintable(candidate)) {
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
    if (vtableSOff == 0) return null;
    // FlatBuffer allows negative vtableSOff (vtable after table in memory)
    final vtableStart = tableStart - vtableSOff;
    if (vtableStart < 0 || vtableStart + 2 > _data.length) return null;

    final vtableSize = _bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 8 || vtableSize > 128) return null;
    final numFields = (vtableSize - 4) ~/ 2;

    String? name;
    int obxType = 0;
    int flags = 0;

    // ObjectBox Property FlatBuffer field layout (from actual data analysis):
    //   Modern schema: field[1] = id, field[6] = name, field[7] = type
    //   Older schema:  field[0] = id, field[1] = name, field[2] = type
    // Try modern layout first.

    // Try field[6] for name (modern), then field[1] (older)
    if (numFields > 6) {
      final nameOff = _bd.getUint16(vtableStart + 4 + 6 * 2, Endian.little);
      if (nameOff > 0) {
        final nameFieldAddr = tableStart + nameOff;
        name = _readFbStringInline(nameFieldAddr);
      }
    }
    if (name == null || name.isEmpty) {
      if (numFields > 1) {
        final nameOff = _bd.getUint16(vtableStart + 4 + 1 * 2, Endian.little);
        if (nameOff > 0) {
          final nameFieldAddr = tableStart + nameOff;
          name = _readFbStringInline(nameFieldAddr);
        }
      }
    }

    // Try field[7] for type (modern), then field[2] (older)
    if (numFields > 7) {
      final typeOff = _bd.getUint16(vtableStart + 4 + 7 * 2, Endian.little);
      if (typeOff > 0) {
        final typeFieldAddr = tableStart + typeOff;
        if (typeFieldAddr < _data.length) {
          // Type is stored as the low byte of a uint64 value
          obxType = _data[typeFieldAddr];
        }
      }
    }
    if (obxType == 0 && numFields > 2) {
      final typeOff = _bd.getUint16(vtableStart + 4 + 2 * 2, Endian.little);
      if (typeOff > 0) {
        final typeFieldAddr = tableStart + typeOff;
        if (typeFieldAddr + 4 <= _data.length) {
          final candidateType = _bd.getInt32(typeFieldAddr, Endian.little);
          // Only accept if it looks like a valid OBXPropertyType (1-15)
          if (candidateType >= 1 && candidateType <= 15) {
            obxType = candidateType;
          }
        }
      }
    }

    // Try field[3] for flags (older schema)
    if (numFields > 3) {
      final flagsOff = _bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
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
    return String.fromCharCodes(
      _data.sublist(strAddr + 4, strAddr + 4 + strLen),
    );
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
    if (strLen <= 0 || strLen > 10000 || strAddr + 4 + strLen > valEnd)
      return null;
    try {
      final str = utf8.decode(
        _data.sublist(strAddr + 4, strAddr + 4 + strLen),
        allowMalformed: true,
      );
      return str.isNotEmpty ? str : null;
    } catch (_) {
      return null;
    }
  }

  // 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸?Data Entry Parsing 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜?
  /// Quick check: parse the FlatBuffer vtable of [entry] and return true only if
  /// the vtable field count equals [expectedFieldCount].
  /// This is the cheapest way to distinguish entries from different entities that
  /// share the same LMDB B-tree.
  bool _entryMatchesSchema(_EntryData entry, int expectedFieldCount) {
    final absEntry = entry.absEntry;
    final valStart = absEntry + 16;
    final valLen = entry.length - 16;
    if (valLen < 8) return false;

    final rootOffset = _bd.getUint32(valStart, Endian.little);
    if (rootOffset == 0 || rootOffset >= valLen) {
      return expectedFieldCount == 0;
    }

    final tableStart = valStart + rootOffset;
    if (tableStart + 4 > valStart + valLen) return false;

    final vtableSOff = _bd.getInt32(tableStart, Endian.little);
    if (vtableSOff == 0) return false;
    final vtableStart = tableStart - vtableSOff;
    if (vtableStart < 0 || vtableStart + 4 > valStart + valLen) return false;

    final vtableSize = _bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 4 || vtableSize > 256) return false;
    final numFields = (vtableSize - 4) ~/ 2;
    return numFields == expectedFieldCount;
  }

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
    if (vtableSOff == 0) return null;
    // FlatBuffer allows negative vtableSOff (vtable after table in memory)
    final vtableStart = tableStart - vtableSOff;
    if (vtableStart < 0 || vtableStart + 4 > valStart + valLen) return null;

    final vtableSize = _bd.getUint16(vtableStart, Endian.little);
    if (vtableSize < 4 || vtableSize > 256) return null;
    final numFields = (vtableSize - 4) ~/ 2;

    // Read the object ID from FlatBuffer field[0] (int64).
    // This is the actual ObjectBox object ID, not the LMDB key bytes.
    final valEnd = valStart + valLen;
    int objectId = entry.objectId;
    if (numFields > 0) {
      final idFieldOff = _bd.getUint16(vtableStart + 4, Endian.little);
      if (idFieldOff > 0) {
        final idFieldAddr = tableStart + idFieldOff;
        if (idFieldAddr + 8 <= valEnd) {
          objectId = _bd.getInt64(idFieldAddr, Endian.little);
          entry.objectId = objectId;
        }
      }
    }

    final values = <String, dynamic>{'id': objectId};
    final props = List<PropertyInfo>.from(entity.properties);

    for (var fi = 0; fi < numFields; fi++) {
      final fieldOff = _bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
      if (fieldOff == 0) continue;

      final fieldAddr = tableStart + fieldOff;
      if (fieldAddr + 1 > valEnd) continue; // at least 1 byte needed

      final PropertyInfo prop;
      if (fi < props.length) {
        prop = props[fi];
        if (prop.isId) continue; // id already extracted from key
      } else {
        while (props.length <= fi) {
          props.add(
            PropertyInfo.discovered(props.length, PropertyType.unknown),
          );
        }
        prop = props[fi];
      }

      final val = _readFieldValue(valStart, fieldAddr, valEnd, prop.type);
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

  /// Read a field value using the known [propertyType] from schema.
  /// When the type is unknown (discovered mode), falls back to heuristics.
  dynamic _readFieldValue(
    int valStart,
    int addr,
    int valEnd, [
    int? propertyType,
  ]) {
    // ObjectBox PropertyType values aligned with OBXPropertyType from C API:
    //   1=bool, 2=byte, 3=short, 4=char, 5=int,
    //   6=long, 7=float, 8=double, 9=string, 10=date,
    //   11=relation, 12=dateNano, 13=flex,
    //   22=boolVector, 23=byteVector, 24=shortVector, 25=charVector,
    //   26=intVector, 27=longVector, 28=floatVector, 29=doubleVector,
    //   30=stringVector, 31=dateVector, 32=dateNanoVector
    final pt = propertyType ?? 0;
    switch (pt) {
      case 1: // bool
        if (addr + 1 > valEnd) return null;
        return _data[addr] != 0;
      case 2: // byte
        if (addr + 1 > valEnd) return null;
        return _data[addr];
      case 3: // short (int16)
        if (addr + 2 > valEnd) return null;
        return _bd.getInt16(addr, Endian.little);
      case 4: // char (16-bit character)
        if (addr + 2 > valEnd) return null;
        return _bd.getUint16(addr, Endian.little);
      case 5: // int (int32)
        if (addr + 4 > valEnd) return null;
        return _bd.getInt32(addr, Endian.little);
      case 6: // long (int64)
        if (addr + 8 > valEnd) return null;
        return _bd.getInt64(addr, Endian.little);
      case 7: // float
        if (addr + 4 > valEnd) return null;
        return _bd.getFloat32(addr, Endian.little);
      case 8: // double
        if (addr + 8 > valEnd) return null;
        return _bd.getFloat64(addr, Endian.little);
      case 9: // string
        return _readFbString(valStart, addr, valEnd);
      case 10: // date (ms since epoch, int64)
        if (addr + 8 > valEnd) return null;
        return _bd.getInt64(addr, Endian.little);
      case 11: // relation (int64 target ID)
        if (addr + 8 > valEnd) return null;
        return _bd.getInt64(addr, Endian.little);
      case 12: // dateNano (ns since epoch, int64)
        if (addr + 8 > valEnd) return null;
        return _bd.getInt64(addr, Endian.little);
      case 13: // flex (FlexBuffer encoded)
        return _readFlexBufferField(addr, valEnd);
      // Vector types: stored as FlatBuffer vector with length prefix
      case 22: // boolVector
        return _readFbVector<bool>(addr, valEnd, 1, (a) => _data[a] != 0);
      case 23: // byteVector
        return _readFbVector<int>(addr, valEnd, 1, (a) => _data[a]);
      case 24: // shortVector
        return _readFbVector<int>(
          addr,
          valEnd,
          2,
          (a) => _bd.getInt16(a, Endian.little),
        );
      case 25: // charVector
        return _readFbVector<int>(
          addr,
          valEnd,
          2,
          (a) => _bd.getUint16(a, Endian.little),
        );
      case 26: // intVector
        return _readFbVector<int>(
          addr,
          valEnd,
          4,
          (a) => _bd.getInt32(a, Endian.little),
        );
      case 27: // longVector
        return _readFbVector<int>(
          addr,
          valEnd,
          8,
          (a) => _bd.getInt64(a, Endian.little),
        );
      case 28: // floatVector
        return _readFbVector<double>(
          addr,
          valEnd,
          4,
          (a) => _bd.getFloat32(a, Endian.little),
        );
      case 29: // doubleVector
        return _readFbVector<double>(
          addr,
          valEnd,
          8,
          (a) => _bd.getFloat64(a, Endian.little),
        );
      case 30: // stringVector
        return _readFbStringVector(addr, valEnd);
      case 31: // dateVector (list of int64 ms timestamps)
        return _readFbVector<int>(
          addr,
          valEnd,
          8,
          (a) => _bd.getInt64(a, Endian.little),
        );
      case 32: // dateNanoVector (list of int64 ns timestamps)
        return _readFbVector<int>(
          addr,
          valEnd,
          8,
          (a) => _bd.getInt64(a, Endian.little),
        );
    }

    // Unknown type – heuristic fallback
    // 1) Try long (int64) — most common scalar in ObjectBox
    try {
      if (addr + 8 <= valEnd) {
        final v = _bd.getInt64(addr, Endian.little);
        if (v != 0 && v != 0x7FFFFFFFFFFFFFFF && v != -1) {
          return v;
        }
      }
    } catch (_) {}

    // 2) Try string
    try {
      final str = _readFbString(valStart, addr, valEnd);
      if (str != null && str.isNotEmpty) return str;
    } catch (_) {}

    // 3) Try double
    try {
      if (addr + 8 <= valEnd) {
        final v = _bd.getFloat64(addr, Endian.little);
        if (v.isFinite && v.abs() > 1e-10 && v.abs() < 1e20) return v;
      }
    } catch (_) {}

    // 4) Try int32
    try {
      if (addr + 4 <= valEnd) return _bd.getInt32(addr, Endian.little);
    } catch (_) {}

    // 5) Try bool
    try {
      if (addr + 1 <= valEnd) {
        final b = _data[addr];
        if (b <= 1) return b == 1;
      }
    } catch (_) {}

    return null;
  }

  // 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸?Helpers 闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑鎾绘煃閸忓浜鹃梺鍐插帨閸嬫捇鏌嶉崗澶婁壕闂佸啿鍘滈崑?
  /// Read a FlatBuffer vector of numeric values.
  /// [elementSize] is the size of each element in bytes.
  /// [readElement] reads a single element at the given absolute offset.
  List<T>? _readFbVector<T>(
    int fieldAddr,
    int valEnd,
    int elementSize,
    T Function(int addr) readElement,
  ) {
    if (fieldAddr + 4 > valEnd) return null;
    final vecOff = _bd.getUint32(fieldAddr, Endian.little);
    if (vecOff < 4 || vecOff > 100000) return null;
    final vecAddr = fieldAddr + vecOff;
    if (vecAddr + 4 > valEnd) return null;
    final vecLen = _bd.getUint32(vecAddr, Endian.little);
    if (vecLen > 10000) return null; // sanity check
    final result = <T>[];
    final dataStart = vecAddr + 4;
    for (var i = 0; i < vecLen; i++) {
      final elemAddr = dataStart + i * elementSize;
      if (elemAddr + elementSize > valEnd) break;
      result.add(readElement(elemAddr));
    }
    return result;
  }

  /// Read a FlatBuffer vector of strings.
  List<String>? _readFbStringVector(int fieldAddr, int valEnd) {
    if (fieldAddr + 4 > valEnd) return null;
    final vecOff = _bd.getUint32(fieldAddr, Endian.little);
    if (vecOff < 4 || vecOff > 100000) return null;
    final vecAddr = fieldAddr + vecOff;
    if (vecAddr + 4 > valEnd) return null;
    final vecLen = _bd.getUint32(vecAddr, Endian.little);
    if (vecLen > 10000) return null;
    final result = <String>[];
    // String vector: each element is a uint32 offset to a FlatBuffer string
    for (var i = 0; i < vecLen; i++) {
      final elemOffAddr = vecAddr + 4 + i * 4;
      if (elemOffAddr + 4 > valEnd) break;
      final strOff = _bd.getUint32(elemOffAddr, Endian.little);
      if (strOff == 0) continue;
      final strAddr = elemOffAddr + strOff;
      if (strAddr + 4 > valEnd) continue;
      final strLen = _bd.getUint32(strAddr, Endian.little);
      if (strLen > 0 && strLen < 10000 && strAddr + 4 + strLen <= valEnd) {
        try {
          final s = utf8.decode(
            _data.sublist(strAddr + 4, strAddr + 4 + strLen),
            allowMalformed: true,
          );
          result.add(s);
        } catch (_) {}
      }
    }
    return result;
  }

  /// Read a Flex type field (OBXPropertyType_Flex = 13).
  /// Flex fields use FlexBuffer encoding, a compact binary format
  /// that supports dynamic types (maps, lists, scalars, strings).
  /// Since we don't have a full FlexBuffer decoder, we attempt basic parsing
  /// and fall back to showing raw bytes as a hex string.
  dynamic _readFlexBufferField(int fieldAddr, int valEnd) {
    if (fieldAddr + 4 > valEnd) return null;
    final vecOff = _bd.getUint32(fieldAddr, Endian.little);
    if (vecOff < 4 || vecOff > 100000) return null;
    final dataAddr = fieldAddr + vecOff;
    if (dataAddr + 4 > valEnd) return null;
    // Flex fields are stored as a byte vector in FlatBuffer
    final vecLen = _bd.getUint32(dataAddr, Endian.little);
    if (vecLen <= 0 || vecLen > 100000) return null;
    final dataStart = dataAddr + 4;
    if (dataStart + vecLen > valEnd) return null;
    // Try to parse as FlexBuffer
    try {
      return _parseFlexBuffer(dataStart, vecLen);
    } catch (_) {
      // Fallback: return as hex string
      final bytes = _data.sublist(dataStart, dataStart + vecLen);
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  /// Minimal FlexBuffer parser supporting common types.
  /// FlexBuffer format: [data...][byte1: value byte][byte2: type << 2 | width]
  /// The last byte encodes the type and width of the root value.
  dynamic _parseFlexBuffer(int start, int length) {
    if (length < 2) return null;
    // The last byte encodes type and indirect width
    final lastByte = _data[start + length - 1];
    final typeNibble = lastByte >> 2;
    final width = (lastByte & 3) + 1; // 1, 2, 4, or 8 bytes

    // FlexBuffer types
    const int fbtNull = 0;
    const int fbtInt = 1;
    const int fbtUInt = 2;
    const int fbtFloat = 3;
    const int fbtString = 5;
    const int fbtMap = 9;
    const int fbtVector = 10;
    const int fbtBool = 26;

    switch (typeNibble) {
      case fbtNull:
        return null;
      case fbtInt:
        return _readFlexInt(start + length - 1 - width, width);
      case fbtUInt:
        return _readFlexUInt(start + length - 1 - width, width);
      case fbtFloat:
        if (width == 4) {
          return _bd.getFloat32(start + length - 1 - width, Endian.little);
        } else if (width == 8) {
          return _bd.getFloat64(start + length - 1 - width, Endian.little);
        }
        return null;
      case fbtString:
        final strLen = _readFlexUInt(start + length - 1 - width * 2, width);
        final strStart = start + length - 1 - width * 2 - strLen;
        if (strStart >= start && strStart + strLen <= start + length) {
          return utf8.decode(
            _data.sublist(strStart, strStart + strLen),
            allowMalformed: true,
          );
        }
        return null;
      case fbtBool:
        return _data[start + length - 1 - 1] != 0;
      case fbtVector:
      case fbtMap:
        // For vectors and maps, return a descriptive string since
        // full parsing is complex.
        final sizeAddr = start + length - 1 - width;
        final size = _readFlexUInt(sizeAddr, width);
        if (typeNibble == fbtVector) {
          return '<$size items>';
        } else {
          return '<$size keys>';
        }
      default:
        // Unsupported FlexBuffer type, return hex
        final bytes = _data.sublist(start, start + length);
        return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  int _readFlexInt(int addr, int width) {
    switch (width) {
      case 1:
        return _data[addr].toSigned(8);
      case 2:
        return _bd.getInt16(addr, Endian.little);
      case 4:
        return _bd.getInt32(addr, Endian.little);
      case 8:
        return _bd.getInt64(addr, Endian.little);
      default:
        return 0;
    }
  }

  int _readFlexUInt(int addr, int width) {
    switch (width) {
      case 1:
        return _data[addr];
      case 2:
        return _bd.getUint16(addr, Endian.little);
      case 4:
        return _bd.getUint32(addr, Endian.little);
      case 8:
        return _bd.getUint64(addr, Endian.little);
      default:
        return 0;
    }
  }

  bool _isPrintable(String s) {
    return s.runes.every(
      (r) => (r >= 0x20 && r <= 0x7E) || (r >= 0x4E00 && r <= 0x9FFF),
    );
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
            if (s.trim().isNotEmpty && _isMostlyPrintable(s))
              strings.add(s.trim());
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
    final printable = s.runes
        .where((r) => r >= 0x20 && r <= 0x7E || r >= 0x4E00 && r <= 0x9FFF)
        .length;
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

  _EntryData(
    this.pageOffset,
    this.entryOffset,
    this.length,
    this._data,
    this._bd,
  );

  int get absEntry => pageOffset + entryOffset;

  int get entityId => _data[absEntry + 15];

  /// ObjectBox object ID: decoded from the FlatBuffer value data.
  ///
  /// The object ID is stored as field[0] (int64) inside the FlatBuffer value,
  /// NOT in the LMDB key. The key bytes contain ObjectBox internal metadata
  /// (cursor position, put flags) rather than the logical object ID.
  int get objectId => _objectId ?? 0;

  int? _objectId;

  /// Set the objectId after parsing the FlatBuffer value.
  set objectId(int value) => _objectId = value;

  bool get isSchema {
    // ObjectBox LMDB key layout (16 bytes):
    //   bytes 0-1:  key prefix / flags
    //   bytes 2-7:  object ID (for data entries)
    //   bytes 8-14: padding / metadata
    //   byte 15:    entity ID
    //
    // Schema entries are stored in the special "0" sub-DB where
    // bytes 8-14 (padding) are all zero. Data entries always have
    // non-zero bytes in 8-14 (they contain put flags/size info like
    // byte[8]=0x18). This is the reliable way to distinguish them.
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
  _ParsedProperty({
    required this.propId,
    required this.name,
    required this.obxType,
    required this.isId,
  });
}
