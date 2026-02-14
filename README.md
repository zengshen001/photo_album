# Smart Story Album

智能故事相册（Flutter + Isar + ML Kit + LLM）。

## 项目简介

- 本地扫描系统相册，按时间与空间聚类事件。
- 使用 Google ML Kit 做离线标签与人脸分析。
- 仅上传结构化摘要到远程 LLM 生成故事（不上传图片二进制）。
- 支持 Isar 本地存储与故事回查。

## 目录结构

- `lib/view/`：页面与 UI 组件
- `lib/service/`：扫描、聚类、地址解析、AI 与故事服务
- `lib/models/`：UI 模型与 Isar 实体
- `lib/data/`：Mock 数据
- `doc/`：任务拆解、验收与测试数据文档

## 快速开始

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

## 常用命令

```bash
# 格式化
dart format .

# 静态检查
flutter analyze

# 全量测试
flutter test

# 单个测试文件
flutter test test/widget_test.dart

# 单个测试用例
flutter test test/widget_test.dart --plain-name "Create page shows placeholder content"
```

## 运行配置

### 1) 高德逆地理编码

地址解析通过高德 WebService，启动时传入：

```bash
flutter run --dart-define=AMAP_WEB_KEY=YOUR_AMAP_WEB_KEY
```

### 2) 第三方 LLM 中转（OpenAI Responses 风格）

```bash
flutter run \
  --dart-define=LLM_BASE_URL=http://your-gateway/v1 \
  --dart-define=LLM_API_PATH=/responses \
  --dart-define=LLM_MODEL=gpt-5.1-codex \
  --dart-define=LLM_API_KEY=YOUR_API_KEY
```

## iOS 调试说明

- iOS 26 真机建议使用 `--profile`（debug 模式存在兼容问题）。
- 启动示例：

```bash
flutter run -d <iphone_device_id> --profile
```

## 隐私约束（必须遵守）

- 禁止上传图片二进制到云端模型（`File`/`Uint8List`）。
- 仅允许上传结构化摘要（时间、地点、标签、情感分等文本数据）。

## 测试文档

- 改造任务：`doc/task/`
- 实机验收：`doc/实机验收流程规划.md`
- 模拟器测试数据：`doc/simulator_seed_plan/`
- 高德与缓存改造：`doc/amap_cache_reset_update/`
