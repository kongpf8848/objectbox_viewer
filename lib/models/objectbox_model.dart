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
      entities: entitiesJson.map((e) => EntityInfo.fromJson(e as Map<String, dynamic>)).toList(),
      indexes: indexesJson.map((e) => IndexInfo.fromJson(e as Map<String, dynamic>)).toList(),
      relations: relationsJson.map((e) => RelationInfo.fromJson(e as Map<String, dynamic>)).toList(),
      lastEntityId: json['_lastEntityId'] ?? 0,
      lastIndexId: json['_lastIndexId'] ?? 0,
      lastRelationId: json['_lastRelationId'] ?? 0,
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
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      lastPropertyId: json['lastPropertyId'] ?? 0,
      properties: propsJson.map((p) => PropertyInfo.fromJson(p as Map<String, dynamic>)).toList(),
      entityIndexes: idxJson.map((i) => IndexInfo.fromJson(i as Map<String, dynamic>)).toList(),
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
  dateNano(11, 'DateNano'),
  relation(12, 'Relation'),
  vectorFloat32(13, 'List<float>'),
  byteVector(14, 'List<byte>'),
  byteVectorCompressed(15, 'List<byte>(compressed)'),
  unknown(0, 'Unknown'),
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

  PropertyInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.flags,
    this.indexId,
    this.relationTarget,
  });

  factory PropertyInfo.fromJson(Map<String, dynamic> json) {
    return PropertyInfo(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 0,
      flags: json['flags'] ?? 0,
      indexId: json['indexId']?.toString(),
      relationTarget: json['relationTarget'],
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

  bool get isId => (flags & 1) != 0;
  bool get isNonNull => (flags & 2) != 0;
  bool get isIndexed => indexId != null;

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
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      entityId: json['entityId'] ?? 0,
      propertyIds: propIds.map((e) => e.toString()).toList(),
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
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      sourceEntityId: json['sourceEntityId'] ?? 0,
      targetEntityId: json['targetEntityId'] ?? 0,
    );
  }
}

/// A single row of data from an ObjectBox entity box
class EntityRow {
  final int id;
  final Map<String, dynamic> values;

  EntityRow({required this.id, required this.values});
}
