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

## 0.0.4 透明图标与单一安装

完整图案外围去除奶油色底块并设为透明，保留袋子、铃铛与内部口袋。原始附件另存，内置 imagegen 的编辑提示词与派生关系见 [ICON.md](ICON.md)。已从实际安装 ICNS 解包检查全部 10 个尺寸，外围 alpha=0、内部不透明；正式应用与签名 ZIP 中的图标资源一致。

本机只保留 /Applications/cs-tool-x.app；已检查的应用目录、项目、下载、桌面、文档中仅此一份，Spotlight 仅返回该路径，Dock 仅一个对应固定项。旧 Dev、DataX、构建备份与首次带背景的图标构建移入废纸篓。配置目录、个人指针和签名文件未纳入清理；正式路径启动显示首页。

[0.0.4 CI](https://github.com/anjing-le/cs-tool-x/actions/runs/43436395557) 全部通过；构建完整性、0.0.3 → 0.0.4 的标识/公钥/feed/build、更新包与 feed 验签及篡改负例通过。已发布 [0.0.4](https://github.com/anjing-le/cs-tool-x/releases/tag/v0.0.4)，原生 URLSession 匿名下载 ZIP、校验和、feed，与本地已验签原件逐字节一致，latest feed 同样匹配。未把本机直接更换图标描述成 OTA 安装验收。

## 0.0.5 运行时 Dock 覆盖

启动主线程从独立 DockIcon.png 读取 NSImage 并赋给 NSApp.applicationIconImage，ICNS 保留为回退。本机原位更新后首页启动正常，用户现场确认白底已消失、只剩图案。自动化读取 Dock 区域超时，视觉验收结果来自用户反馈，不由 PNG alpha 检查代替。

已检查的应用/项目/下载/桌面/文档目录仅有 /Applications/cs-tool-x.app 一份对应应用，Dock 仅一个对应固定项；安装 PNG 与生产源逐字节一致。旧安装移入废纸篓，配置与个人素材未纳入更新清理。

正式构建、完整性、0.0.4 → 0.0.5 标识/公钥/feed/build、更新包/feed 验签和篡改负例通过。[0.0.5](https://github.com/anjing-le/cs-tool-x/releases/tag/v0.0.5) 已发布，原生 URLSession 匿名下载 ZIP/校验和/feed 与本地已验签原件一致，latest feed 同样匹配。本次基于本机构建、签名检查和用户现场验收发布；记录时 [GitHub CI](https://github.com/anjing-le/cs-tool-x/actions/runs/43449653693) 仍在排队，尚无远端结论。实际 OTA 安装与退出后/Finder 图标未计入本次验收。

## 0.0.6 本机明文 SSH/SFTP 配置

按用户授权读取指定历史部署记录，与本机部署脚本的主机/用户/目录交叉核对。真实连接资料只保存在仓库外的本机 shell.json，公开文档不列地址或密码。该主机为真实线上部署机，本轮没有执行上传、远端文件写入、部署、重启或升级命令。

本机 Swift 测试 9 项，1 项因缺少隔离数据库 fixture 跳过，0 失败；新测试覆盖普通密码读取、端点/ID 不匹配、宽权限配置拒绝、主机确认/私钥口令/OTP 拒绝和 SSH/SFTP 参数保留主机校验。

真实 OpenSSH 使用随包原生 askpass 登录，目录存在检查通过；SFTP 连接与 14 字节只读下载通过。原生客户端实际确认服务器条目、普通文本密码字段及备注，点击后自动登录 SSH 并输出验证标记；SFTP 控制台自动认证、cd/pwd、ls -l 和小文件 get 成功，下载与 CLI fixture 一致。一次 SFTP ls -ld 因不支持 -d 报错，随后使用受支持的 cd/pwd/ls -l 完成目录验证，未将报错计作通过。测试会话已关闭，配置保留。

已核对单一正式安装；运行中透明 Dock PNG 保留。真实地址/密码在暂存源码及更新 ZIP 的扫描均未发现，ZIP 不含 shell.json；此检查不等于通用秘密扫描服务。完整性、0.0.5 → 0.0.6 身份/公钥/feed/build、归档/feed 验签与篡改负例通过。[CI](https://github.com/anjing-le/cs-tool-x/actions/runs/43557918620) 全部通过。[0.0.6](https://github.com/anjing-le/cs-tool-x/releases/tag/v0.0.6) 公开资产经原生 URLSession 匿名下载，与本地已验签 ZIP、校验和、feed 一致，latest feed 匹配。

本轮未验收上传、图形化 SFTP 文件管理器、断线续传、巨大文件性能或完整 OTA 安装；数据库凭据仍不落盘。

## 0.0.7 CLI 基础

新增独立 ToolCLI，复用 ToolCore 的配置、密码助手与 Rust 数据引擎；不链接 AppKit/SwiftUI/SwiftTerm/Sparkle，不启动 GUI。正式包含 CLI，命令安装只创建指向现有包的符号链接。

本机 Swift 16 项测试，1 项隔离数据库 fixture 因环境跳过，0 失败。新增测试覆盖配置原子替换、0600 备份、旧 revision 拒绝、并发更新不丢条目、旧格式配置读取、配置大小限制，以及 stdout/stderr 同时输出、输出超限、超时、stdin 与非零退出。

CLI 隔离回归对 debug 和随包 release 二进制均通过：稳定 JSON/退出码、无参数帮助、未知参数不回显、显式秘密读取、更新/删除 revision、8 个独立 CLI 并发创建、相同 revision 竞争只能成功一次、输入限制、无效远端脚本/路径拒绝、数据库配置禁止保存凭据。模拟引擎证明 hello/connect/run/disconnect、超大整数文本保真及退出后 worker 消失；不代表真实数据库查询已验收。安装脚本验证创建、重复运行及拒绝覆盖其他命令。

使用已授权的本机真实服务器配置执行 SSH 只读标记和 SFTP 当前目录列表，均退出 0，无截断，无远端写入。未新增真实数据库 CLI、上传/下载、大目录/文件、断线续传或服务端取消验收。

release 构建完整性、0.0.6 → 0.0.7 标识/公钥/feed/build 兼容、归档/feed 验签和篡改拒绝通过。对源码与 ZIP 检查本机服务器地址/密码未发现，ZIP 无连接配置。此次尚未安装替换当前 0.0.6 GUI，GUI 配置重载与冲突提示的界面交互未实测；该行为由共享存储检查、编译及测试提供当前证据。日常安装仍一份，临时应用包在完成归档后移入废纸篓；实际 OTA 安装由用户确认。

[0.0.7 CI](https://github.com/anjing-le/cs-tool-x/actions/runs/43562048439) 全部通过，包括 CLI 协议/并发回归与开发包构建。[0.0.7](https://github.com/anjing-le/cs-tool-x/releases/tag/v0.0.7) 已正式发布；首次发布请求因 EOF 未成功，核对仍为草稿后重试成功。公开下载初次命中不可用响应，加入唯一查询参数后用原生 URLSession 匿名取得 ZIP/校验和/feed，与本地已验签文件逐字节一致，latest feed 匹配。

临时 0.0.7 构建已移入废纸篓；递归检查时额外发现 `engine/target/release/bundle/macos/Anjing DataX.app` 旧原型，确认标识 cc.anjing.datax、未运行后按既有单一客户端授权移入废纸篓。正式安装仍为 /Applications/cs-tool-x.app 0.0.6，等待用户确认 OTA 更新；未删除配置或历史 ZIP。

## 0.0.7 本机命令入口与安装后验证

用户明确要求直接更新与配置入口。本轮开始检查时，正式路径及运行中“关于”已经显示 0.0.7（7）；已安装 GUI、CLI、引擎、Info.plist 与 DockIcon.png 均与前轮已验签 ZIP 字节一致，codesign 严格检查通过，因此未重复替换应用或重新构建。

安装后实测发现：直接用符号链接经 PATH 启动 0.0.7，argv[0] 可能是裸命令名，其密码助手程序路径被解析到当前工作目录，SSH 退出 255。修复安装入口为 `~/.local/bin/cs-tool-x` 小脚本，exec 同一应用包内的绝对路径；不修改已签名发布包。更新安装脚本自动识别并替换原同目标链接，拒绝覆盖其他命令，后续同路径 OTA 仍可复用。

修复后通过 PATH 执行 schema、doctor、服务器/数据库配置列表、真实 SSH 只读标记与 SFTP 列目录成功，无截断。已安装 CLI 的完整隔离回归通过；新增入口回归覆盖含空格/单引号的应用路径、参数逐字传递、重复安装、旧符号链接迁移和无关命令拒绝。数据库实际配置为空，数据查询仅沿用模拟引擎回归结果，没有新增真实数据库 CLI 验收。

CLI 临时新增 fixture.invalid 配置后重启 GUI，可见该条目；通过 revision 删除后再次重启，仅保留原服务器。原服务器/分组/密码的 JSON 值完全一致，未尝试连接测试主机。UI 工具切换前台未能提供可靠的重新激活证据，因此这里只确认重启读取共享配置，不声称热重载验收。当前保持正式客户端打开且没有会话。

已递归检查 /Applications、用户 Applications、project、Documents、Downloads、Desktop，匹配正式/Dev/DataX Bundle ID 的应用仅 /Applications/cs-tool-x.app。Dock 中一个对应固定项，运行中一个 GUI 进程，无遗留随包数据 worker。当前交互 shell 能找到 ~/.local/bin/cs-tool-x；未修改 shell 启动文件。

## 0.0.8 分层连接树

显示层按连接身份合并原配置，不修改保存格式、源 UUID、数据库名和传输策略。新增 MySQL/PG databases、PG schemas、按范围 tables 元数据操作，以及 CLI profiles tree / data browse。根连接下保留来源详情；树按需展开、带缓存总量与单次目录上限。

本机 Swift 19 项全部通过（本轮启动隔离 fixture，未跳过大帧检查）；Rust 含隔离适配器联调通过，新增数据库/Schema/表及恶意 scope 绑定检查。CLI 协议回归通过。真实 AppKit 离屏组件检查覆盖连接合并、四层展开、主题行构建、刷新保留展开状态、断开清缓存与过期节点拒绝；初次断言误把未展开的 Redis DB 节点计入可见行数量，修正测试后通过，没有把该断言错误归为产品问题。

本机已有配置的全部 UUID 与原文件 SHA-256 在验证前后保持一致。通过新引擎实际读取 PG 可见库、Schema、目标 Schema 的表，MySQL 可见库与指定库的表；含 SQL 语法的 scope 返回空范围。Redis 有界 SCAN 与 ES 索引目录通过。只读取元数据或无匹配 Key，不执行真实目标 DDL/写入；详细目标、数量和配置只保留本机 ignored 验证记录，不进入公开仓库。

正式 0.0.8 构建与随包 CLI 回归通过，随包新引擎的真实只读目录验证通过；0.0.7 → 0.0.8 标识/公钥/feed/build 兼容、归档/feed Ed25519 验签与篡改拒绝通过。源码与 ZIP 对本机测试目标/密码字面量扫描未发现，ZIP 不含连接配置。当前窗口自动化工具不可用，尚未将离屏组件检查描述为安装后界面验收；实际安装与点击验收状态另行记录。

[0.0.8 CI](https://github.com/anjing-le/cs-tool-x/actions/runs/43591614403) 全部通过，包含新增的离屏数据树组件与键盘展开/收起回归。[0.0.8](https://github.com/anjing-le/cs-tool-x/releases/tag/v0.0.8) 已发布，原生 URLSession 匿名下载 ZIP/校验和/feed，与本地已验签原件一致，latest feed 匹配。临时应用构建已移入废纸篓；检查时正式路径仍为 0.0.7，因窗口自动化工具不可用，已请用户在现有客户端完成更新后继续核对，未声称已完成安装后界面验收。

用户随后确认完成 OTA 更新与重启。已从正式路径核对 0.0.8（8），codesign 严格验证通过；GUI、CLI、引擎、Info.plist 和透明 Dock PNG 与已验签发布 ZIP 字节一致。命令入口仍指向同一正式包，安装后的分组结果与原 profile UUID 集合一致，配置文件 SHA-256 不变。使用正式包 CLI/引擎再次完成真实 PG 库/Schema/表、MySQL 库/表及绑定 scope、Redis SCAN、ES 索引只读检查。应用/项目/文档/下载/桌面目录仅一份对应客户端，Dock 一个固定项，正式 GUI 进程一个。自动窗口点击工具仍不可用，安装后树的鼠标键盘操作未列入本轮自动验收。

## 0.0.9 浏览 / 查询与本机连接收敛

参考 Elasticvue v1.8.0 的对象筛选表与查询编辑器/结果分区，以本项目 Swift/AppKit 独立实现。固定连接选择器避免展开大量库后难以切换目标；默认对象表替代原配置清单与大段说明，工作区在浏览和查询间切换并保留草稿。结果筛选保留原行索引，表预览的 SQL 草稿正确引用标识符，用户改过的草稿不覆盖。新增 Redis INFO keyspace 目录，明确只代表有数据的 DB。

按用户指定，本机仅保留 PG、MySQL、Redis、ES 各一个可用连接，其他连接元数据先全量归档到仓库外 Application Support/archives 的 0600 文件，再通过 CLI revision 检查移除；原始来源文件未修改。应用没有硬编码连接数量限制或公司目标。四个所选条目的原 UUID、地址、账号、库与传输设置保留，只简化显示名称。

Swift 22 项测试通过，1 项隔离数据库大帧 fixture 本轮未启动而跳过；Rust 3 项单测通过，隔离适配器 fixture 本轮跳过。新增检查包括筛选后原行映射、完整已加载字段搜索、SQL 标识符引用、Redis DB 元数据解析与 500 行/8 MiB 限制。AppKit 离屏组件检查通过连接筛选、浏览对象筛选、查询入口、模式切换保留草稿、新数据库连接保留兄弟目录及目录预算清理；未把离屏检查当作安装后点击验收。

debug 与正式包 CLI 回归通过；正式包新引擎对四个已选目标完成目录读取和只读查询：SQL SELECT 1、Redis 有界无匹配 SCAN、ES size=0 搜索，不读取业务记录正文。连接配置在检查前后不变，完整归档可读且权限为 0600；具体地址、账号、密码及目录清单只保留本机 ignored 记录。

[0.0.9 CI](https://github.com/anjing-le/cs-tool-x/actions/runs/43595387662) 全部通过，包含新浏览/查询组件、连接过滤、草稿保留和元数据预算回归。[0.0.9](https://github.com/anjing-le/cs-tool-x/releases/tag/v0.0.9) 已发布；0.0.8 → 0.0.9 标识、公钥、feed 与递增 build 验证、归档/feed 签名及篡改拒绝通过，公开 ZIP/校验和/feed 与本地已验签文件一致，latest feed 匹配。临时 .app 已移入废纸篓，历史 ZIP 保留。安装后验收等待用户在现有客户端完成更新，窗口操作工具当前不可用。

用户确认安装并重启后，正式路径核对为 0.0.9（9）。GUI、CLI、引擎、Info.plist 与透明 Dock PNG 均与已验签 ZIP 字节一致，codesign 严格检查通过。安装后的 CLI 确认只有 PG/MySQL/Redis/ES 四个连接，原全量归档完整且权限 0600；使用正式包再次通过四种连接的只读目录/查询检查，配置内容不变。已检查的应用/项目/文档/下载/桌面目录仅一个对应客户端，Dock 一个固定项，正式 GUI 进程一个。窗口点击仍未自动验收，没有把 CLI 验证扩写为 GUI 操作验收。
