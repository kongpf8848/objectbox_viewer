# ObjectBox Viewer - Breakthrough Session

## Objective
Build a Dart/Flutter ObjectBox viewer that reads data.mdb directly without objectbox-model.json

## Key Discoveries

### 1. LMDB File Structure (data.mdb)
- **16-byte prefix**: First 16 bytes are ObjectBox header, LMDB magic at offset 16
- **Magic**: 0xBEEFC0DE at offset 16 (sliced offset 0)
- **pageSize**: At sliced offset 24 (original offset 40), value = 4096
- **Pages**: 6 total, page size 4096

### 2. Schema Discovery - USE STRING SEARCH
**✅ Working approach**: String search method
- Search for known entity names in raw byte data
- Parse backwards to find vtable header
- Extract entity name at vtable index 3, properties at index 4

**❌ Broken approach**: LMDB entry structure
- Entries with entityId=0 don't follow expected format
- bytes[8-14] not zero, rootOff values are large (~2097191)
- Schema stored differently in discovered mode databases

### 3. Entities Found
All on page 2:
- TodoEntity: offset 11784, vtableSize=24, 10 fields
- UserEntity: offset 11240, vtableSize=24, 10 fields  
- StudentEntity: offset 10964, vtableSize=48, 22 fields

## Next Steps
Rewrite discoverModel() to use string search:
1. Search for entity name strings (or known patterns)
2. For each match, trace back to vtable and parse
3. Extract field[3] (name) and field[4] (properties)