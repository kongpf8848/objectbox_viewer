# ObjectBox Viewer

[中文文档](README_CN.md)

A cross-platform desktop tool for browsing and inspecting [ObjectBox](https://objectbox.io/) Dart databases, built with Flutter.

ObjectBox Viewer reads `data.mdb` directly at the binary level (LMDB + FlatBuffers), with **no dependency on `objectbox-model.json`** — it can auto-discover entities and infer property types from the data itself.

## Features

- **Auto-discovery** — Open any ObjectBox database directory; entity schemas are discovered directly from `data.mdb`, even without `objectbox-model.json`
- **Schema-aware** — When `objectbox-model.json` is present, full schema info (property names, types, flags, indexes, relations) is used for accurate display
- **Data browsing** — View entity data in a paginated table with type-aware rendering (bool, int, long, double, string, date, dateNano, Flex, vectors, etc.)
- **Schema inspection** — Browse entity schemas with property types, flags (ID, NotNull, Indexed, Unique, Virtual, Unsigned, etc.), indexes, and relations
- **CSV/JSON export** — Export entity data with proper type formatting (Date fields as ISO 8601, byte arrays as hex, etc.)
- **Dark mode** — Follows system theme with Material 3 design
- **Resizable panels** — Drag the divider to resize the entity list; auto-hide when collapsed

## Supported Platforms

| Platform | Status |
|----------|--------|
| macOS    | ✅ Supported |
| Linux    | ✅ Supported |
| Windows  | ✅ Supported |

## Screenshots

*Left panel: entity list with Data/Schema toggle. Right panel: data table or schema detail.*

## Getting Started

### Prerequisites

- Flutter SDK >= 3.11.4
- An ObjectBox database directory (containing `data.mdb`)

### Install Dependencies

```bash
flutter pub get
```

### Run

```bash
flutter run -d macos   # or -d linux / -d windows
```

### Build Release

```bash
flutter build macos    # or linux / windows
```

## Usage

1. Launch the app
2. Click **Open Database Directory** (or the folder icon in the toolbar)
3. Select the directory containing your ObjectBox database files
4. Browse entities in the left panel, switch between **Data** and **Schema** views
5. Use the export button in the data table to save as CSV or JSON

## Architecture

```
lib/
├── main.dart                  # App entry, theme, database open logic
├── bloc/
│   └── db_bloc.dart           # BLoC state management (open/select/refresh)
├── models/
│   └── objectbox_model.dart   # Data models: ObjectBoxModel, EntityInfo, PropertyInfo, PropertyType
├── services/
│   ├── objectbox_service.dart # Core parser: LMDB page scan, FlatBuffer decode, FlexBuffer support
│   └── simple_viewer.dart     # Standalone viewer (non-Flutter entry point)
└── widgets/
    ├── home_page.dart         # Main layout with resizable split panels
    ├── entity_list_panel.dart # Left panel: entity list + Data/Schema toggle
    ├── data_table_panel.dart  # Data table with pagination and export
    ├── entity_schema_panel.dart # Entity schema detail view
    └── schema_detail_panel.dart # Overall schema overview
```

### Key Technical Details

- **LMDB Parsing** — Reads `data.mdb` directly, scans B-tree pages, handles ObjectBox 16-byte prefix (`0xBEEFC0DE` magic), freelist-based ghost entry filtering
- **FlatBuffer Decoding** — Parses VTable + field data for each object entry, supports all OBXPropertyType values (1–32) including vectors and Flex
- **FlexBuffer Support** — Decodes Flex (type 13) properties: integers, floats, strings, booleans, null, and nested maps/vectors
- **IdUid Parsing** — Correctly handles ObjectBox `"id:uid"` format from `objectbox-model.json`
- **Property Flags** — Full OBXPropertyFlags support: ID, NonPrimitiveType, NotNull, Indexed, Unique, IdSelfAssignable, Virtual, Unsigned, etc.

## Dependencies

| Package                 | Purpose                        |
|-------------------------|--------------------------------|
| flutter_bloc            | State management (BLoC pattern) |
| ffi                     | FFI bindings for native access  |
| file_picker             | Directory selection dialog      |
| path_provider           | System paths                    |
| equatable               | Value equality for BLoC states  |
| path                    | Cross-platform path utilities   |
| objectbox               | ObjectBox Dart SDK (reference)  |
| objectbox_flutter_libs  | ObjectBox native libraries      |

## License

This project is for personal use and not intended for publication.
