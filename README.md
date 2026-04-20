# LaunchDeck

一个模仿 macOS 启动台（Launchpad）交互风格的 macOS 应用示例，支持：

- 扫描本机 `.app` 应用并展示为分页图标网格
- 搜索过滤应用
- 点击图标直接启动应用
- 类启动台的沉浸背景、圆点分页和悬停动效
- 横向滑动翻页（无上一页/下一页按钮）
- 拖拽图标重排顺序（含跨页边缘拖放）
- 拖拽至边缘自动翻页，随悬停时长加速（速度曲线）
- 拖到图标中心区域创建/加入文件夹
- 文件夹重命名、文件夹内拖拽重排
- 文件夹内分页与滑动翻页
- 文件夹弹层展开与过渡动画
- 布局持久化（图标顺序、文件夹分组、文件夹名称）
- 布局 schema 版本迁移（自动从 v1 升级到 v2）
- 偏好设置（滚轮翻页、搜索聚焦、预取深度、文件夹分页）
- 偏好默认值一键恢复
- 会话恢复（搜索词、当前页、当前文件夹）
- 诊断报告导出（布局、偏好、会话、运行环境摘要）
- 统一日志埋点（扫描、持久化、生命周期、启动应用）
- 中英文本地化资源与资源 bundle 打包
- 本地检查脚本与 GitHub Actions CI

## 系统要求

- **macOS 26 (Tahoe) 及以上**
- Xcode 17 / Swift 6.2 工具链

### 为什么坚持 macOS 26？

本项目 `Package.swift` 将 deployment target 固定为 `.macOS(.v26)`，**不向下兼容**。这是一项明确的工程决策，不是疏忽：

- **`.onDrag { … } preview: { … }` 的高保真拖拽预览**需要 v26 上最新的 SwiftUI drag/drop 管线，旧系统的降级路径会丢失 `.compositingGroup()` + `matchedGeometryEffect` 的视觉连续性。
- **`accessibilityReduceMotion` 与 `NSWorkspace.accessibilityDisplayShouldReduceMotion` 的语义**在 v26 上才与动画调度器完美对齐，低版本会出现 reduce-motion 状态延迟一帧的问题。
- **`Task.sleep(nanoseconds:)` 的调度精度**、`@MainActor` 隔离的诊断、以及 `os.Logger` 的 structured metadata 在 v26 工具链下才是"零成本"抽象。
- 项目定位为个人启动台，没有向企业旧设备分发的需求；与其花精力维护多条兼容路径，不如把表达力预算花在 UX 细节上。

如果需要在更低版本上运行，请 fork 后自行替换相关 API——我们不会接受 "降低 deployment target" 的 PR。

## 运行

```bash
./script/build_and_run.sh
```

## 工程检查

```bash
./script/check.sh
```

## 常用调试模式

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

## 目录结构

- `Sources/App`: App 入口与启动行为
- `Sources/Views`: 视图层
- `Sources/Models`: 数据模型
- `Sources/Stores`: 状态管理
- `Sources/Services`: 应用扫描、图标缓存、持久化、诊断导出
- `Sources/Support`: 本地化、分页、交互辅助
- `Sources/Resources`: 本地化资源
- `script/build_and_run.sh`: 统一构建和运行脚本
- `script/check.sh`: 本地 build/test 检查
- `.github/workflows/ci.yml`: 持续集成
- `.codex/environments/environment.toml`: Codex Run 按钮配置
