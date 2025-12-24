
# Project: Smart Story Album (智能故事相册)

## 1. 项目与架构

**核心理念**: 本地优先 (Local First) + 端云协同。
**业务流程**: 本地 ML Kit 感知 -> 规则时空聚类 -> 意图选图 -> 云端 LLM 写故事。

### 技术栈

* **UI**: Flutter (Material 3)
* **AI (端侧)**: Google ML Kit (离线图像标签/目标检测)
* **AI (云端)**: OpenAI 兼容接口 (仅用于文本生成，**严禁上传图片**)
* **Database**: Isar / SQLite (存储元数据、聚类结果)

## 2. 核心算法逻辑 (Business Logic)

> 在编写业务逻辑代码时，严格遵循以下规则：

### 2.1 时空聚类 (Clustering)

* **策略**: 规则驱动 (Rule-based)，而非 AI 聚类。
* **流程**:
1. **排序**: 按时间戳升序排列。
2. **切分**: 满足任一条件即切分为新事件：
* 时间间隔 > **2小时**。
* 地理距离 > **1km** (若有 GPS)。


3. **兜底**: 若无 GPS，仅依赖时间规则。



### 2.2 智能主题与选图 (Theme & Selection)

* **主题推导**: 基于 ML Kit 标签统计 + 规则匹配 (e.g., `Beach` > 3 & `Day` > 2 -> "海边旅行")。
* **选图评分**: `Score = w1*场景匹配 + w2*标签重合 + w3*情感分`。
* **排序逻辑**: 绝对主轴为**时间顺序**，辅以美学评分微调。

### 2.3 故事生成 (Story Generation)

* **输入**: 构造轻量级 JSON 摘要 (含：时间、场景标签、情感倾向、聚合意图)。
* **Prompt**: 要求 LLM 以“第一人称、回忆录风格”撰写 150-300 字博客。
* **对齐**: UI 渲染时，图片按本地时间顺序排列，文本按段落穿插。

## 3. UI 设计规范 (Design System)

### 3.1 导航结构

* **BottomBar**: [相册 Album] (默认) | [故事 Stories] | [我的 Profile]

### 3.2 页面详细定义

1. **相册流 (AlbumPage)**
* **数据源**: 时空聚类后的 Event 列表。
* **卡片**: 封面拼图 + 自动标题 (e.g., "2024 · 夏天") + 标签 (e.g., "旅行/海滩")。


2. **事件详情 (EventDetailPage)**
* **Header**: 时间范围 + AI 推荐主题 Chips (点击可应用)。
* **Body**: `SliverGrid` 时间序照片网格 (支持多选)。
* **FAB**: `[生成故事]` -> 跳转至配置页。


3. **故事配置 (ConfigPage)**
* **功能**: LLM 请求前的最后确认。
* **表单**: 主题输入框 (支持手动/AI预设) + 篇幅开关 (短/中)。


4. **故事结果 (ResultPage/BlogPage)**
* **风格**: **图文博客 (Blog Style)**。
* **布局**:
* Hero 大封面图 + 主标题。
* 文本段落与图片网格交替渲染 (Rhythm Layout)。


* **操作**: 编辑文本、保存到本地 DB、分享。



## 4. 编码约束

* **隐私红线**: 任何图片文件 (`File`, `Uint8List`) **绝对禁止**发送到云端 API。仅发送 JSON 标签数据。
* **状态管理**: Provider / Riverpod。
* **Mock Data**: UI 开发阶段必须使用 Mock 数据模拟 ML Kit 的返回结果。
* **文件结构**:
* `lib/logic/`: 存放聚类、打分算法 (纯 Dart)。
* `lib/services/`: 存放 LLM API 和 ML Kit 调用。
* `lib/view/`存放页面文件，`widget_tree`是导航页面
