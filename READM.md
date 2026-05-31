# ObjectBox Viewer

[English](README.md)

一个跨平台桌面工具，用于浏览和检查 [ObjectBox](https://objectbox.io/) Dart 数据库，基于 Flutter 构建。

ObjectBox Viewer 直接在二进制层面读取 `data.mdb`（LMDB + FlatBuffers），**无需依赖 `objectbox-model.json`** —— 它能从数据本身自动发现实体并推断属性类型。

## 功能特性

- **自动发现** — 打开任意 ObjectBox 数据库目录，即使没有 `objectbox-model.json`，也能直接从 `data.mdb` 中发现实体结构
- **Schema 感知** — 当 `objectbox-model.json` 存在时，使用完整的 Schema 信息（属性名称、类型、标志位、索引、关联关系）进行精确展示
- **数据浏览** — 以分页表格查看实体数据，支持类型感知渲染（bool、int、long、double、string、date、dateNano、Flex、向量类型等）
- **Schema 检查** — 浏览实体 Schema，查看属性类型、标志位（ID、NotNull、Indexed、Unique、Virtual、Unsigned 等）、索引和关联关系
- **CSV/JSON 导出** — 导出实体数据，支持类型格式化（Date 字段输出 ISO 8601、字节数组输出十六进制等）
- **暗色模式** — 跟随系统主题，采用 Material 3 设计
- **可调面板** — 拖拽分隔线调整实体列表宽度，收窄时自动隐藏

## 支持平台

| 平台   | 状态       |
|--------|-----------|
| macOS  | ✅ 已支持  |
| Linux  | ✅ 已支持  |
| Windows| ✅ 已支持  |

## 快速开始

### 环境要求

- Flutter SDK >= 3.11.4
- 一个 ObjectBox 数据库目录（包含 `data.mdb`）

### 安装依赖

```bash
flutter pub get
```

### 运行

```bash
flutter run -d macos   # 或 -d linux / -d windows
```

### 构建发布版本

```bash
flutter build macos    # 或 linux / windows
```

## 使用方法

1. 启动应用
2. 点击 **Open Database Directory**（或工具栏中的文件夹图标）
3. 选择包含 ObjectBox 数据库文件的目录
4. 在左侧面板浏览实体，切换 **Data** / **Schema** 视图
5. 使用数据表格中的导出按钮，保存为 CSV 或 JSON

## 项目架构

```
lib/
├── main.dart                  # 应用入口、主题、数据库打开逻辑
├── bloc/
│   └── db_bloc.dart           # BLoC 状态管理（打开/选择/刷新）
├── models/
│   └── objectbox_model.dart   # 数据模型：ObjectBoxModel、EntityInfo、PropertyInfo、PropertyType
├── services/
│   ├── objectbox_service.dart # 核心解析器：LMDB 页面扫描、FlatBuffer 解码、FlexBuffer 支持
│   └── simple_viewer.dart     # 独立查看器（非 Flutter 入口）
└── widgets/
    ├── home_page.dart         # 主布局，可调整大小的分栏面板
    ├── entity_list_panel.dart # 左侧面板：实体列表 + Data/Schema 切换
    ├── data_table_panel.dart  # 数据表格，支持分页和导出
    ├── entity_schema_panel.dart # 实体 Schema 详情视图
    └── schema_detail_panel.dart # 整体 Schema 概览
```

### 核心技术细节

- **LMDB 解析** — 直接读取 `data.mdb`，扫描 B-tree 页面，处理 ObjectBox 16 字节前缀（`0xBEEFC0DE` 魔数），基于 Freelist 过滤幽灵条目
- **FlatBuffer 解码** — 解析每个对象条目的 VTable + 字段数据，支持所有 OBXPropertyType 值（1–32），包括向量类型和 Flex
- **FlexBuffer 支持** — 解码 Flex（type 13）属性：整数、浮点数、字符串、布尔值、null 及嵌套 Map/Vector
- **IdUid 解析** — 正确处理 ObjectBox 的 `"id:uid"` 格式（来自 `objectbox-model.json`）
- **Property Flags** — 完整支持 OBXPropertyFlags：ID、NonPrimitiveType、NotNull、Indexed、Unique、IdSelfAssignable、Virtual、Unsigned 等

## 依赖说明

| 包名                   | 用途                           |
|-----------------------|-------------------------------|
| flutter_bloc          | 状态管理（BLoC 模式）            |
| ffi                   | FFI 绑定，用于原生库访问           |
| file_picker           | 目录选择对话框                    |
| path_provider         | 系统路径                         |
| equatable             | BLoC 状态的值相等性比较           |
| path                  | 跨平台路径工具                    |
| objectbox             | ObjectBox Dart SDK（参考）      |
| objectbox_flutter_libs| ObjectBox 原生库                |

## 许可证

本项目使用MIT协议
