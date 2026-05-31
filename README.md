# ObjectBox Viewer

一个跨平台桌面工具，用于浏览和检查 [ObjectBox](https://objectbox.io/) 数据库，基于 Flutter 构建。

ObjectBox Viewer 直接在二进制层面读取 `data.mdb`（LMDB + FlatBuffers），**无需依赖 `objectbox-model.json`** —— 它能从数据本身自动发现实体并推断属性类型。

## 功能特性

- **自动发现** — 打开任意 ObjectBox 数据库目录，即使没有 `objectbox-model.json`，也能直接从 `data.mdb` 中发现实体结构
- **Schema 感知** — 当 `objectbox-model.json` 存在时，使用完整的 Schema 信息（属性名称、类型、标志位、索引、关联关系）进行精确展示
- **数据浏览** — 以分页表格查看实体数据，支持类型感知渲染（bool、int、long、double、string、date、dateNano、Flex、向量类型等）
- **Schema 检查** — 浏览实体 Schema，查看属性类型、标志位（ID、NotNull、Indexed、Unique、Virtual、Unsigned 等）、索引和关联关系
- **CSV/JSON 导出** — 导出实体数据，支持类型格式化（Date 字段输出 ISO 8601、字节数组输出十六进制等）

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

## 核心技术细节

- **LMDB 解析** — 直接读取 `data.mdb`，扫描 B-tree 页面，处理 ObjectBox 16 字节前缀（`0xBEEFC0DE` 魔数），基于 Freelist 过滤幽灵条目
- **FlatBuffer 解码** — 解析每个对象条目的 VTable + 字段数据，支持所有 OBXPropertyType 值（1–32），包括向量类型和 Flex
- **FlexBuffer 支持** — 解码 Flex（type 13）属性：整数、浮点数、字符串、布尔值、null 及嵌套 Map/Vector
- **IdUid 解析** — 正确处理 ObjectBox 的 `"id:uid"` 格式（来自 `objectbox-model.json`）
- **Property Flags** — 完整支持 OBXPropertyFlags：ID、NonPrimitiveType、NotNull、Indexed、Unique、IdSelfAssignable、Virtual、Unsigned 等

## 许可证

本项目使用MIT协议
