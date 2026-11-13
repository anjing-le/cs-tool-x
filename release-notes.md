cs-tool-x 的第一个原生 macOS 基础版本。

- 首页采用 FinanceX 卡片结构与 ShellX 暖纸张配色，Shell、数据两张卡片，进入后为各自独立工作区，⌘1 返回首页。
- Shell 迁入 anjing-shell 的服务器分组、搜索、标签与分屏交互，接上 SwiftTerm 和系统 OpenSSH；不包含示例服务器、假日志或假传输。
- MySQL / PostgreSQL 查询、目录和表预览；Elasticsearch 索引和 JSON 搜索；Redis SCAN 与类型预览。
- 文件功能整合在 Shell 的右侧栏；SFTP 控制台位于同一 Shell 的附属面板中，图形化双栏目录与传输队列尚未接入。
- 客户端不使用钥匙串，密码/API Key 只在本次会话保留；连接元数据可本地保存。
- OTA 私钥位于仓库外 0600 本地文件，Sparkle 验证 Ed25519 更新包和 signed feed，由用户确认安装。

需要 macOS 14+、Apple Silicon。应用使用 ad-hoc 完整性签名，未提供 Apple Developer ID 或公证。真实业务环境、跨机器启动、完整 OTA 安装与性能对比仍待验收。
