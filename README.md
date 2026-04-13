# LaunchDeck

一个模仿 macOS 启动台（Launchpad）交互风格的 macOS 应用示例，支持：

- 扫描本机 `.app` 应用并展示为分页图标网格
- 搜索过滤应用
- 点击图标直接启动应用
- 类启动台的沉浸背景、圆点分页和悬停动效
- 横向滑动翻页（无上一页/下一页按钮）
- 拖拽图标重排顺序（含跨页边缘拖放）
- 长按进入编辑态，图标抖动动效
- 拖拽至边缘自动翻页，随悬停时长加速（速度曲线）
- 拖到图标中心区域创建/加入文件夹
- 文件夹重命名、文件夹内拖拽重排
- 文件夹内分页与滑动翻页
- 文件夹弹层展开与过渡动画
- 布局持久化（图标顺序、文件夹分组、文件夹名称）
- 布局 schema 版本迁移（自动从 v1 升级到 v2）

## 运行

```bash
./script/build_and_run.sh
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
- `Sources/Services`: 应用扫描、图标缓存、应用启动
- `script/build_and_run.sh`: 统一构建和运行脚本
- `.codex/environments/environment.toml`: Codex Run 按钮配置
