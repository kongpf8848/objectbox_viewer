/// Parse ObjectBox IdUid format "id:uid" – extracts just the id part.
/// ObjectBox uses "id:uid" format in objectbox-model.json (e.g. "1:7348726389543").
String _parseIdFromIdUid(dynamic value) {
  if (value == null) return '';
  final str = value.toString();
  if (str.contains(':')) {
    return str.split(':').first;
  }
  return str;
}

int _parseIdIntFromIdUid(dynamic value) {
  final idStr = _parseIdFromIdUid(value);
  return int.tryParse(idStr) ?? 0;
}

/// Parsed ObjectBox model schema from objectbox-model.json,
/// or discovered directly from the LMDB file (no JSON needed).
class ObjectBoxModel {
  final List<EntityInfo> entities;
  final List<IndexInfo> indexes;
  final List<RelationInfo> relations;
  final int lastEntityId;
  final int lastIndexId;
  final int lastRelationId;
  final int modelVersion;
  final bool discovered;

  ObjectBoxModel({
    required this.entities,
    required this.indexes,
    required this.relations,
    required this.lastEntityId,
    required this.lastIndexId,
    required this.lastRelationId,
    required this.modelVersion,
    this.discovered = false,
  });

  factory ObjectBoxModel.fromJson(Map<String, dynamic> json) {
    final entitiesJson = json['entities'] as List<dynamic>? ?? [];
    final indexesJson = json['indexes'] as List<dynamic>? ?? [];
    final relationsJson = json['relations'] as List<dynamic>? ?? [];

    return ObjectBoxModel(
      entities: entitiesJson
          .map((e) => EntityInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      indexes: indexesJson
          .map((e) => IndexInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      relations: relationsJson
          .map((e) => RelationInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastEntityId: _parseIdIntFromIdUid(json['_lastEntityId']),
      lastIndexId: _parseIdIntFromIdUid(json['_lastIndexId']),
      lastRelationId: _parseIdIntFromIdUid(json['_lastRelationId']),
      modelVersion: json['_modelVersion'] ?? 0,
      discovered: false,
    );
  }

  /// Create a "discovered" model when objectbox-model.json is not available.
  /// [subDbNames] are the named sub-databases found in the LMDB file.
  factory ObjectBoxModel.discovered(List<String> subDbNames) {
    final entities = subDbNames.map((name) {
      // Generate generic properties based on common ObjectBox patterns.
      // The parser will discover actual fields from the FlatBuffer VTable at runtime.
      return EntityInfo.discovered(name);
    }).toList();

    return ObjectBoxModel(
      entities: entities,
      indexes: [],
      relations: [],
      lastEntityId: entities.length,
      lastIndexId: 0,
      lastRelationId: 0,
      modelVersion: 0,
      discovered: true,
    );
  }
}

class EntityInfo {
  String id;
  final String name;
  final int lastPropertyId;
  List<PropertyInfo> properties;
  final List<IndexInfo> entityIndexes;
  final bool discovered;

  EntityInfo({
    required this.id,
    required this.name,
    required this.lastPropertyId,
    required this.properties,
    required this.entityIndexes,
    this.discovered = false,
  });

  factory EntityInfo.fromJson(Map<String, dynamic> json) {
    final propsJson = json['properties'] as List<dynamic>? ?? [];
    final idxJson = json['indexes'] as List<dynamic>? ?? [];

    return EntityInfo(
      id: _parseIdFromIdUid(json['id']),
      name: json['name'] ?? '',
      lastPropertyId: _parseIdIntFromIdUid(json['lastPropertyId']),
      properties: propsJson
          .map((p) => PropertyInfo.fromJson(p as Map<String, dynamic>))
          .toList(),
      entityIndexes: idxJson
          .map((i) => IndexInfo.fromJson(i as Map<String, dynamic>))
          .toList(),
      discovered: false,
    );
  }

  /// Create a discovered entity (no objectbox-model.json).
  /// Generic properties will be replaced at runtime by discovered fields.
  factory EntityInfo.discovered(String name) {
    return EntityInfo(
      id: name.hashCode.toString(),
      name: name,
      lastPropertyId: 0,
      properties: [], // will be discovered at runtime from FlatBuffer VTable
      entityIndexes: [],
      discovered: true,
    );
  }
}

enum PropertyType {
  // OBXPropertyType values from ObjectBox C API / objectbox-dart source
  unknown(0, 'Unknown'),
  bool(1, 'bool'),
  byte(2, 'byte'),
  short(3, 'short'),
  char(4, 'char'),
  int_(5, 'int'),
  long(6, 'long'),
  float(7, 'float'),
  double_(8, 'double'),
  string(9, 'String'),
  date(10, 'Date'),
  relation(11, 'Relation'),
  dateNano(12, 'DateNano'),
  flex(13, 'Flex'),
  boolVector(22, 'List<bool>'),
  byteVector(23, 'List<byte>'),
  shortVector(24, 'List<short>'),
  charVector(25, 'List<char>'),
  intVector(26, 'List<int>'),
  longVector(27, 'List<long>'),
  floatVector(28, 'List<float>'),
  doubleVector(29, 'List<double>'),
  stringVector(30, 'List<String>'),
  dateVector(31, 'List<Date>'),
  dateNanoVector(32, 'List<DateNano>'),
  // Discovered types (not in ObjectBox schema, inferred at runtime)
  discoveredInt(100, 'int?'),
  discoveredLong(101, 'long?'),
  discoveredDouble(102, 'double?'),
  discoveredString(103, 'String?'),
  discoveredBool(104, 'bool?'),
  discoveredBytes(105, 'bytes');

  const PropertyType(this.value, this.displayName);
  final int value;
  final String displayName;

  static PropertyType fromValue(int v) {
    return PropertyType.values.firstWhere(
      (e) => e.value == v,
      orElse: () => PropertyType.unknown,
    );
  }
}

class PropertyInfo {
  final String id;
  final String name;
  final int type;
  final int flags;
  final String? indexId;
  final String? relationTarget;

  /// ObjectBox property ID (from schema IdUid, lower 32 bits).
  /// Used to map FlatBuffer field index in data entries: fieldIndex = propertyId - 1.
  /// When 0, falls back to sequential index.
  final int propertyId;

  PropertyInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.flags,
    this.indexId,
    this.relationTarget,
    this.propertyId = 0,
  });

  factory PropertyInfo.fromJson(Map<String, dynamic> json) {
    final idStr = _parseIdFromIdUid(json['id']);
    return PropertyInfo(
      id: idStr,
      name: json['name'] ?? '',
      type: json['type'] ?? 0,
      flags: json['flags'] ?? 0,
      indexId: _parseIdFromIdUid(json['indexId']),
      relationTarget: json['relationTarget'],
      propertyId: int.tryParse(idStr) ?? 0,
    );
  }

  /// Create a discovered property (name = "field_N", type inferred later).
  factory PropertyInfo.discovered(int fieldIndex, PropertyType inferredType) {
    return PropertyInfo(
      id: 'discovered_$fieldIndex',
      name: 'field_$fieldIndex',
      type: inferredType.value,
      flags: 0,
    );
  }

  PropertyType get propertyType => PropertyType.fromValue(type);

  /// OBXPropertyFlags.ID = 1: 64-bit long property representing the entity ID
  bool get isId => (flags & 1) != 0;

  /// OBXPropertyFlags.NON_PRIMITIVE_TYPE = 2: nullable wrapper type (Java/Kotlin)
  bool get isNonPrimitiveType => (flags & 2) != 0;

  /// OBXPropertyFlags.NOT_NULL = 4: property must not be null
  bool get isNotNull => (flags & 4) != 0;

  /// OBXPropertyFlags.INDEXED = 8: property has an index
  bool get isIndexedFlag => (flags & 8) != 0;

  /// OBXPropertyFlags.UNIQUE = 32: property has a unique index
  bool get isUnique => (flags & 32) != 0;

  /// OBXPropertyFlags.ID_SELF_ASSIGNABLE = 128: allows developer-assigned IDs
  bool get isIdSelfAssignable => (flags & 128) != 0;

  /// OBXPropertyFlags.VIRTUAL = 1024: no dedicated field in entity class
  /// (e.g., target ID of ToOne relation)
  bool get isVirtual => (flags & 1024) != 0;

  /// OBXPropertyFlags.UNSIGNED = 8192: integer is treated as unsigned
  bool get isUnsigned => (flags & 8192) != 0;

  /// Backward-compatible: true if property has an index (by flag or indexId)
  bool get isIndexed => isIndexedFlag || indexId != null;

  String get displayType => propertyType.displayName;
}

class IndexInfo {
  final String id;
  final String name;
  final int entityId;
  final List<String> propertyIds;
  final int flags;

  IndexInfo({
    required this.id,
    required this.name,
    required this.entityId,
    required this.propertyIds,
    required this.flags,
  });

  factory IndexInfo.fromJson(Map<String, dynamic> json) {
    final propIds = json['propertyIds'] as List<dynamic>? ?? [];
    return IndexInfo(
      id: _parseIdFromIdUid(json['id']),
      name: json['name'] ?? '',
      entityId: _parseIdIntFromIdUid(json['entityId']),
      propertyIds: propIds.map((e) => _parseIdFromIdUid(e)).toList(),
      flags: json['flags'] ?? 0,
    );
  }
}

class RelationInfo {
  final String id;
  final String name;
  final int sourceEntityId;
  final int targetEntityId;

  RelationInfo({
    required this.id,
    required this.name,
    required this.sourceEntityId,
    required this.targetEntityId,
  });

  factory RelationInfo.fromJson(Map<String, dynamic> json) {
    return RelationInfo(
      id: _parseIdFromIdUid(json['id']),
      name: json['name'] ?? '',
      sourceEntityId: _parseIdIntFromIdUid(json['sourceEntityId']),
      targetEntityId: _parseIdIntFromIdUid(json['targetEntityId']),
    );
  }
}

/// A single row of data from an ObjectBox entity box
class EntityRow {
  final int id;
  final Map<String, dynamic> values;

  EntityRow({required this.id, required this.values});
}
