# 0.0.1 验证记录 · 2026-11-13

## 已完成的代码与协议检查

- Rust 检查 3 项通过，包含隔离适配器联调。测试服务为本机 MySQL 9.6.0、PostgreSQL 16.11、Redis 8.0.2；ES 使用协议模拟服务。
- Swift 检查 7 项通过：SSH 参数隔离与主机校验选项、配置不含秘密字段及 0600 权限、JSON 大整数/NULL、端点校验、缺失引擎错误、真实进程协议/并发/重启，以及通过真实 MySQL 引擎并发接收 65,500 字符大帧。
- 适配器联调覆盖中文、NULL、超出 JavaScript 安全整数范围的 BIGINT、600 行结果截断为 500 行、70,000 字符单元格截断、错误与截断后复用连接。
- PG 数据修改 CTE 被只读事务拒绝；DML、多条语句和 SELECT INTO 被入口拒绝。
- ES 协议模拟验证索引列表、POST 搜索、size 上限与索引路径边界。没有真实 ES 服务端兼容性结论。

旧 DataX Web 原型的 Playwright 检查不计作新原生 UI 验收；旧原型已归档在本机，未发布进仓库。

## 发布检查

release 应用通过 `codesign --verify --deep --strict`。更新私钥从仓库外 0600 本地文件读取，未使用钥匙串；ZIP 已用随包公钥通过 Ed25519 验证，signed appcast 验证通过，修改归档和 feed 内版本内容的负例均被拒绝。线上发布后重新下载公开 ZIP、SHA-256 和 appcast，已核对归档公钥验签、feed 验签、版本、长度与下载 URL；使用 macOS 原生 URLSession、不携带鉴权信息匿名访问 latest/download/appcast.xml，取得与签名原件一致的内容。当时 curl / Python TLS 请求曾握手失败，该命令行网络结果与后续原生请求成功分别记录。

## 原生界面验证

- 无标题栏暖纸张框体；首页仅 Shell / 数据两张卡片，⌘1 返回首页。
- Shell 多标签和左右分屏均使用真实本地 PTY；执行 printf 返回标记文本。关闭左分屏后保留右分屏的进程与输出，关闭标签后返回空状态。
- 右侧文件栏与终端处于同一 Shell 工作区，没有独立文件首页卡片；图形目录待接入状态可见。
- 原生数据界面通过私有进程协议连接本地隔离 MySQL，执行 SELECT、读取对象目录、点击表预览，界面显示完整 BIGINT `9007199254740993` 和中文值。
- 连接表单只有保存元数据的选项，未提供钥匙串保存；测试未保存连接配置。结束后断开测试数据库并恢复首页。

## 尚未验收

真实业务地址、TLS/CA、VPN、数据库版本与权限、真实 ES、SSH 远程交互与 SFTP 文件收发、完整 OTA 下载/确认安装/重启，以及其他 Mac 的首次下载启动。

尚无 release 冷启动、空闲内存、交互 p95 或与传统客户端同条件对比的性能结论。验收目标见 PLAN，不把目标当作测得结果。


## GitHub 干净环境

[macOS checks](https://github.com/anjing-le/cs-tool-x/actions/runs/43390521111) 全部通过：Rust、Swift 测试/真实进程协议及开发包构建。CI 的隔离数据库大帧测试按环境跳过，本机带 fixture 的七项 Swift 检查已经通过。

已发布 [0.0.1](https://github.com/anjing-le/cs-tool-x/releases/tag/v0.0.1)。这证明公开资产和验签流程可用，不代表实际更新安装、第三方 Mac 启动或性能目标已经验收。


## 0.0.2 指针更新

新增独立指针回归检查，角色、尺寸、热点、缓存和生命周期均通过；与可用兄弟客户端的本机素材字节一致性已核对。正式应用与更新包验证通过，0.0.1 → 0.0.2 的标识、公钥、feed 与递增 build 一致性通过；更新包中未发现个人指针图片。详见 CURSORS.md。实际 OTA 安装仍由用户验收。

[0.0.2 CI](https://github.com/anjing-le/cs-tool-x/actions/runs/43394185954) 已通过，包括独立指针回归。原生界面复核了首页跳转、Shell 搜索/标签/分屏、连接弹窗密码输入与取消，没有连接真实远端。公开发布后重新下载 ZIP、校验和与 feed，签名、版本、长度和 URL 验证通过；原生 URLSession 匿名取得的 latest feed 与 0.0.2 签名原件一致。一次 gh 下载请求遇到 EOF，重试成功。已发布 [0.0.2](https://github.com/anjing-le/cs-tool-x/releases/tag/v0.0.2)。

## 0.0.3 主题控件

连接弹窗、按钮、勾选、普通/安全字段、下拉、错误/提示与单元格详情改用主题控件，表头和选区同步主题色，Shell 主色引用同一 Theme。原生 UI 验证范围与剩余框架界面见 [UI.md](UI.md)。本轮没有新增真实业务连接或查询验收。

正式包构建、指针回归、0.0.2 → 0.0.3 标识/公钥/feed/build 兼容检查、归档/feed 签名与篡改负例通过，归档未包含个人指针图片。[0.0.3 CI](https://github.com/anjing-le/cs-tool-x/actions/runs/43396532370) 全部通过。

已发布 [0.0.3](https://github.com/anjing-le/cs-tool-x/releases/tag/v0.0.3)。公开 ZIP 与 SHA-256 通过 gh 下载；命令行 feed 下载及一次重试遇到 EOF，改用不带鉴权的原生 URLSession 取得 feed，并确认与签名原件字节一致。对这三份实际下载文件再次核对校验和、版本、长度、URL、归档公钥验签与 feed 验签，全部通过。实际 OTA 安装仍待用户验收。
