# cs-tool-x

一个极简的原生 macOS 开发工作台。把连接服务器、查看数据、文件传输以及后续常用开发操作，收进同一个客户端。

长期目标是逐步承接 SSH 终端、SFTP 文件工具、数据库客户端、接口调试和开发小工具的常用流程。当前是 **0.0.27 基础版本**，功能按真实使用逐步打磨，不承诺已完整替代 Xshell、Xftp 或 DataGrip。

[下载最新版](https://github.com/anjing-le/cs-tool-x/releases/latest) · [项目规划](docs/PLAN.md) · [架构](docs/ARCHITECTURE.md) · [更新与发布](docs/RELEASING.md)

## 当前可用

| 工作区 | 当前能力 | 后续方向 |
| --- | --- | --- |
| 数据 | MySQL / PostgreSQL 单条只读查询、目录与表预览；ES 索引与 JSON 搜索；Redis SCAN 与类型预览 | 查询体验、分页、导出、事务与编辑 |
| 终端 | 复用 anjing-shell 的服务器分组、搜索、标签与分屏；真实 SwiftTerm / 本地 zsh / 系统 OpenSSH | 会话体验、跳板与隧道管理 |
| Shell 文件栏 | 与终端同一工作区，当前提供附属 SFTP 控制台 | 图形化目录、传输队列、取消与重试 |
| 接口 / 工具 | 尚未放入首页 | 按日常使用确定具体范围 |

首页沿用 FinanceX 的等宽卡片结构，配色采用 ShellX 暖纸张；Shell、数据、Git 为三个独立入口，进入后为各自工作区，⌘1 返回首页。连接信息可保存在本机；数据库密码/API Key 可按用户选择保存在本机 `data-credentials.json`（0600，不留备份），或只保留在本次会话；SSH 密码可按用户选择明文保存在本机 `shell.json`，编辑界面直接显示，SSH/SFTP 共用。不使用钥匙串。终端和查询历史只在内存中保留。后台没有常驻 HTTP 服务，数据进程与 SSH/SFTP 会话按需启动。

当前面向 **macOS 14+、Apple Silicon**。Release 使用本地 ad-hoc 完整性签名，OTA 使用 Ed25519 更新包/feed 签名；发布私钥存仓库外 0600 文件，不使用钥匙串。尚未取得 Apple Developer ID 签名与公证；这与下载内容验签、功能验收分别处理。第三方 Mac 的首次启动体验仍待验证。

## 数据浏览与查询

左上切换连接，左侧展开目录，右侧提供“浏览 / 查询”：浏览对象表支持筛选与刷新，点击表、索引或 Key 查看数据；查询模式显示编辑器和结果，切换保留草稿。界面保留暖纸张配色，不搬入集群管理、分片、快照等完整管理界面。

## 数据连接树

同类型、地址、端口、账号和环境显示为一个入口，下面按 MySQL 库 → 表、PostgreSQL 库 → Schema → 表、Redis DB → Keys、ES 索引展开。原始配置与 UUID 保留，TLS 参数按原配置分别使用；展开目录才读取元数据，不启动全库扫描。具体交互和边界见 [连接树](docs/DATA_TREE.md)。

## CLI 与 Agent

应用内附带独立 `cs-tool-x` 命令。支持机器可读 schema/doctor、服务器和数据库配置管理、单次数据查询、SSH 执行及 SFTP 列目录；与 GUI 共用有锁和版本检查的配置。无需窗口或常驻服务。安装及 Agent 提示词见 [CLI 文档](docs/CLI.md)。

## 技术栈

- Swift / SwiftUI / AppKit：卡片首页、复用的 Shell 交互、原生数据编辑区与复用表格。
- Rust / Tokio / SQLx / Reqwest / Redis：独立数据进程、数据库连接池与有界结果处理。
- SwiftTerm + 系统 OpenSSH：PTY 终端与 SSH/SFTP，保持系统主机指纹校验。
- Sparkle 2.10：GitHub Releases 稳定通道、Ed25519 更新包和 feed 验签，用户确认安装。

数据库能力从最初的 DataX 原型迁移；旧 Tauri/Web 原型仅保留在开发者本地归档，发布版采用原生界面。此项目与 `macos-x` 独立：Bundle ID、配置、凭据条目、更新密钥和 feed 分开。

## 本地构建

需要 macOS 开发工具、Swift 6.1+ 和 Rust（当前锁定依赖在 Rust 1.93 上验证）。

```sh
swift package --disable-keychain resolve
swift build --disable-keychain --product CSToolX
```

开发包使用独立 `.dev` 标识与配置空间，关闭 OTA。正式发布需要仓库外的更新私钥文件，具体见发布文档；缺失时停止发布。

## 检查

```sh
cargo test --manifest-path engine/Cargo.toml
cargo build --manifest-path engine/Cargo.toml
CSTOOLX_ENGINE="$PWD/engine/target/debug/cs-tool-engine" swift test --disable-keychain
```

隔离的本地数据库联调可选，需要 Homebrew MySQL、PostgreSQL 16 和 Redis：

```sh
python3 scripts/fixtures.py start
cargo test --manifest-path engine/Cargo.toml -- --include-ignored
python3 scripts/fixtures.py stop
```

ES fixture 只模拟 HTTP 协议，不代表真实 ES 服务端已验收。验证状态见 [记录](docs/VALIDATION.md)。

## 当前边界

SQL 第一版使用只读事务，并限制为单条查询；真实环境优先使用只读账号。查询模式不构成 SQL 沙箱。最多展示 500 行；结果上限不能限制数据库扫描成本或单个巨大字段的接收峰值。客户端超时不代表服务端已停止。

暂未提供 SQL 写操作、手动事务、服务端取消、通用分页、导出、图形化 SFTP、SSH 隧道管理、自定义 CA 和 Redis Cluster/Sentinel。性能目标需要在 release 包和真实环境中测量，尚无超越其他客户端的对比结论。

MIT License。依赖与分发说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 本机指针主题

客户端可读取 `~/Library/Application Support/cs-tool-x/Cursors/` 的本机个人主题，普通/点击图片沿用其他客户端相同的 24pt 尺寸与热点；文本、拖动、分隔线由统一自定义指针层管理。该目录在应用包外，OTA 更新会保留。开发包使用 `cs-tool-x-dev/Cursors`。

现有 Old Roblox 素材说明禁止直接再分发，因此不会出现在 public 源码或更新包中。缺少本机图片时使用代码绘制的自定义替代族。系统窗口边缘不接管。开发者可将合法自备图片、cursors.json 与 NOTICE.txt 放入 ignored `.local/cursor-preview` 后运行 `python3 scripts/install-local-cursors.py`。

连接弹窗、下拉、按钮、输入框、勾选、应用提示和数据详情沿用暖纸张/鼠尾草绿主题，键盘焦点和文本选区不跟随系统强调色；详见 [UI 约定](docs/UI.md)。

本机只保留 `/Applications/cs-tool-x.app` 一个日常入口，不额外安装或固定 Dev。构建时的 `.app` 是临时产物，验证后清理；历史发布保留 ZIP。图标透明版本在 `assets/AppIcon.png`，原始附件保存在 `assets/AppIcon-original.png`，执行 `python3 scripts/make-icon.py` 可重新打包 ICNS。

运行中的 Dock 图标由启动回调直接加载透明 `DockIcon.png`，基础 ICNS 保留为回退；退出后的固定项、Finder 显示另行验证。

性能边界、驱动来源、实际验证范围与尚未完成的兼容/压力测试见 [长期性能与兼容契约](docs/PERFORMANCE_COMPATIBILITY.md)。执行 `python3 tools/dependency-inventory.py` 可查看锁定的实际组件版本、来源与校验和；应用不在运行时下载数据库驱动。

Git 入口选择目录后发现各 Git 仓库，展示当前分支、本地/远程分支树和彩色提交历史，支持仓库、分支、作者、日期和提交文本/哈希筛选，点击提交查看详情与变更文件。只读取本地仓库，不 fetch 或执行 Git 写操作；[范围和性能边界](docs/GIT_BROWSER.md)。
