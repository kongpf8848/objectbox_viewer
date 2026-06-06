// ignore_for_file: avoid_print, unused_local_variable

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/objectbox_model.dart';

/// Simplified ObjectBox viewer - focuses on getting data to display
/// Note: This is a legacy viewer; prefer [ObjectBoxService] for full functionality.
class SimpleObjectBoxViewer {
  late Uint8List _data;
  late ByteData _bd;
  late int _pageSize;
  late int _numPages;

  Future<ObjectBoxModel> openDatabase(String dbPath) async {
    final dataFile = File(p.join(dbPath, 'data.mdb'));
    final rawBytes = await dataFile.readAsBytes();

    // Skip 16-byte prefix
    var start = 0;
    if (rawBytes.length >= 16 &&
        ByteData.sublistView(rawBytes, 16).getUint32(0, Endian.little) ==
            0xBEEFC0DE) {
      start = 16;
    }
    _data = rawBytes.sublist(start);
    _bd = ByteData.sublistView(_data);
    _pageSize = _bd.getUint32(24, Endian.little);
    if (_pageSize < 512 || _pageSize > 65536) _pageSize = 4096;
    _numPages = _data.length ~/ _pageSize;

    // Discover entities by string search
    final entities = _discoverEntities();

    final model = ObjectBoxModel.discovered([]);
    for (var i = 0; i < entities.length; i++) {
      final e = entities[i];
      final entityInfo = EntityInfo.discovered(e.name);
      entityInfo.id = (i + 1).toString();

      // Add generic properties (will be renamed when we parse schema)
      for (var j = 0; j < e.propertyCount; j++) {
        entityInfo.properties.add(
          PropertyInfo(
            id: j.toString(),
            uid: 0,
            name: 'field_$j',
            type: PropertyType.string.value,
            flags: j == 0 ? 1 : 0, // First field is likely ID
          ),
        );
      }

      model.entities.add(entityInfo);
    }

    return model;
  }

  List<_SimpleEntity> _discoverEntities() {
    final entities = <_SimpleEntity>[];
    final seen = <String>{};

    // Search for entity name strings
    final namePattern = 'Entity';
    for (var i = 0; i < _data.length - namePattern.length; i++) {
      if (_data[i] >= 65 && _data[i] <= 122) {
        var end = i;
        while (end < _data.length && _data[end] >= 32 && _data[end] <= 122) {
          end++;
        }

        if (end - i >= 5 && end - i <= 50) {
          final str = String.fromCharCodes(_data.sublist(i, end));
          if (str.endsWith('Entity') && !seen.contains(str)) {
            seen.add(str);

            // Try to parse entity FlatBuffer
            final parsed = _parseEntityNearby(i);
            if (parsed != null) {
              entities.add(_SimpleEntity(parsed.name, parsed.propertyCount));
              print(
                'Found entity: ${parsed.name} (${parsed.propertyCount} props)',
              );
            }
          }
        }
        i = end - 1;
      }
    }

    return entities;
  }

  _ParsedEntitySimple? _parseEntityNearby(int strOffset) {
    // Scan backwards to find vtable
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
                      if (strLen > 0 &&
                          strLen < 100 &&
                          strAddr + 4 + strLen <= _data.length) {
                        final name = String.fromCharCodes(
                          _data.sublist(strAddr + 4, strAddr + 4 + strLen),
                        );

                        // Count properties from field[4]
                        var propCount = 0;
                        if (numFields > 4) {
                          final propsFieldOff = _bd.getUint16(
                            vtableStart + 4 + 4 * 2,
                            Endian.little,
                          );
                          if (propsFieldOff > 0) {
                            final propsAddr = j + propsFieldOff;
                            if (propsAddr + 4 <= _data.length) {
                              final vecOff = _bd.getUint32(
                                propsAddr,
                                Endian.little,
                              );
                              if (vecOff > 0 && vecOff < 10000) {
                                final vecTable = propsAddr + vecOff;
                                if (vecTable + 4 <= _data.length) {
                                  propCount = _bd.getUint32(
                                    vecTable,
                                    Endian.little,
                                  );
                                }
                              }
                            }
                          }
                        }

                        return _ParsedEntitySimple(name, propCount);
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

  Future<List<EntityRow>> readEntityData(
    String dbPath,
    EntityInfo entity,
  ) async {
    // For now, return mock data
    // TODO: Implement actual data reading
    return [];
  }
}

class _SimpleEntity {
  final String name;
  final int propertyCount;
  _SimpleEntity(this.name, this.propertyCount);
}

class _ParsedEntitySimple {
  final String name;
  final int propertyCount;
  _ParsedEntitySimple(this.name, this.propertyCount);
}
