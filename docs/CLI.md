# CLI 与 Agent 接入

GUI 与 CLI 共用 ToolCore、同一份本地配置和数据引擎。CLI 不启动窗口、不依赖 GUI 正在运行，不创建常驻服务。每条网络命令独立连接，用完退出；不会操纵客户端里已经打开的标签或会话。

## 安装与自检

0.0.7 起，正式包内包含 `Contents/MacOS/cs-tool-x`。先安装/更新客户端。有源码时可运行：

```sh
python3 scripts/install-cli.py
cs-tool-x schema
cs-tool-x doctor
cs-tool-x servers list
cs-tool-x profiles list
```

没有源码时可直接用完整路径调用，或取得仓库中的 `scripts/install-cli.py` 安装命令入口。0.0.7 不建议手工创建直接指向二进制的符号链接：通过 PATH 启动时 argv[0] 可能只有命令名，导致其密码助手找错程序路径。安装脚本生成的小脚本会 `exec` 应用包内的绝对路径，旧版同目标链接会自动替换。

安装脚本只在 `~/.local/bin` 创建一个小型命令入口，拒绝覆盖其他命令；以后 OTA 替换同一路径的应用，入口继续有效。若目录不在 PATH，脚本提示手动添加。无需第二个客户端。未安装命令时也可直接执行 `/Applications/cs-tool-x.app/Contents/MacOS/cs-tool-x`。

开发时：

```sh
swift build --disable-keychain --force-resolved-versions --product cs-tool-x
.build/debug/cs-tool-x schema
```

叶子命令支持 `--config-dir DIRECTORY` 隔离测试配置；数据命令支持 `--engine EXECUTABLE` 覆盖引擎路径。这两个参数放在 `list`、`put`、`query` 等叶子命令之后。默认配置是 `~/Library/Application Support/cs-tool-x`。

## 第一版能力

| 命令 | 行为 |
| --- | --- |
| `schema` / `doctor` | 机器可读的命令说明；本地路径、组件与配置数量检查，无网络连接 |
| `servers list/show/put/delete` | SSH/SFTP 共享服务器配置 |
| `profiles tree` | 按连接身份分组返回原配置，原 UUID 保留；不连接远端 |
| `profiles list/show/put/delete` | MySQL、PG、ES、Redis 连接元数据 |
| `data browse UUID --level databases/schemas/tables` | MySQL/PG 分层元数据、Redis 有数据的 DB；tables 用 `--scope` 指定 MySQL 库或 PG Schema |
| `data query/catalog UUID` | 使用现有引擎执行单次查询或目录读取，SQL 仍为只读模式 |
| `ssh exec ID` | 执行远端 sh 脚本，返回有界 stdout/stderr 和退出码 |
| `sftp ls ID` | 列目录，返回系统 SFTP 文本输出，尚非结构化文件对象 |

输入用 `--input FILE` 或 `--input -`（默认）读取 JSON；管道必须关闭以提供 EOF，不弹交互问题。输入最大 1 MiB。不要把真实密码拼进命令参数或 shell 历史，使用私有文件或由 Agent 通过进程 stdin 传入。

例如，创建不含凭据的演示配置：

```sh
printf '%s' '{"name":"演示","host":"example.invalid","user":"demo"}' | cs-tool-x servers put
printf '%s' '{"kind":"pg","name":"本地开发","host":"localhost","port":5432,"database":"demo","username":"demo"}' | cs-tool-x profiles put
```

服务器 ID 与数据库 UUID 从 list 读取。执行远端命令前先核对目标和用户授权；下例仅展示格式，不应照抄到未知目标：

```sh
printf '%s' '{"command":"pwd"}' | cs-tool-x ssh exec 0 --timeout 10 --max-output-bytes 65536
printf '%s' '{"path":"."}' | cs-tool-x sftp ls 0
```

数据库 query 输入字段为 `text`、可选 `password/apiKey/target/cursor`，catalog 支持 `text/password/apiKey`。显式提供的凭据只在该次进程内存；未提供 password/apiKey 时读取本机已保存的凭据。显式提供任一字段（包括空字符串）即覆盖整份保存凭据，不拼接旧 API Key。连接元数据仍不含凭据。`kind` 为 `mysql/pg/es/redis`，具体引擎查询语义和兼容范围沿用 [性能与兼容契约](PERFORMANCE_COMPATIBILITY.md)。

## 稳定输出与并发修改

除 `--help/--version` 外，每次在 stdout 输出一个 JSON 对象：

```json
{"schemaVersion":1,"ok":true,"result":{"...":"..."}}
```

失败时 `ok=false`，含 `error.code/message`，远端失败可含有界的 `error.details`。实际可选字段可能省略；消费者应忽略未知字段，不依赖 JSON 键顺序或中文错误文本。成功结构以 `schema` 为准；后续兼容扩展添加字段，破坏性变更提高协议版本。`--version` 当前返回协议版本 `schema-1`，应用版本由 `doctor` 返回。

| 退出码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 2 | 参数或输入无效 |
| 3 | 配置无效或目标不存在 |
| 4 | 配置已变更或锁等待超过 2 秒 |
| 5 | 操作失败或远端非零退出 |
| 6 | SSH/SFTP 超时 |
| 7 | SSH/SFTP 输出超限或未完整收集 |

`servers/profiles list/show` 返回整份文件的 `revision`。更新现有条目和删除必须带 `--if-revision TOKEN`；先读后改，冲突时重新读取并判断，不覆盖别人的修改。创建条目会在文件锁内合并。GUI 保存同样检查版本；切回应用时重载配置，正在编辑的表单不会被 CLI 强行覆盖，打开的会话保持原连接。GUI 出现保存冲突时先保留草稿、关闭表单并重新读取后处理。

写入先落临时文件并同步，再原子替换，文件权限 0600。元数据与 SSH 配置各保留一个 `.backup`，也是 0600，内容可能含原有 SSH 明文密码。锁和配置各有大小/等待预算；不是跨多文件事务。旧配置直接兼容，不自动迁移到钥匙串。

列表默认不输出密码；`servers show ID --show-secrets` 明确要求时返回本机明文密码。此选择避免普通诊断意外复制凭据，存储本身仍是用户选择的明文。远端脚本自身输出的秘密不会自动识别或脱敏。

## 性能与权限边界

SSH/SFTP 默认 15 秒、stdout+stderr 合计 1 MiB；可设置 1…120 秒和最多 8 MiB。两路输出并发收集，超限/超时停止本地进程；这不证明服务端任务已取消。脚本最大 64 KiB。返回 UTF-8 文本，不用于二进制文件传输；列出特别大的目录也可能触发上限。

保持主机指纹校验；未知主机不自动接受。密码助手按目标 ID/主机/用户/端口核对本机配置，秘密不进入 argv/env；没有密码时使用已有 SSH 密钥/Agent，禁用交互提示。配置错误、主机首次信任需由用户处理，不添加绕过检查的自动降级。

数据继承现有引擎的查询限制、帧大小和逐次调用超时；CLI 没有统一的服务端查询取消。输出上限不是数据库扫描成本上限。SSH 是任意远端命令能力，能写数据和文件；schema 中的 capability 不代表用户授权，不能靠命令分类充当沙箱。

SFTP 上传/下载/断点续传、文件范围读取、流式 tail、GUI 会话复用、后台 daemon 和 MCP 尚未暴露为 CLI 能力。先稳住本地命令协议，再按真实需求增加适配层；未来 MCP 应复用同一服务层。

## 给 Codex 或其他 Agent 的通用说明

```text
使用 cs-tool-x 操作本机开发工具。先运行 schema 和 doctor，按 list 返回的 ID/UUID 选择目标。
优先使用现有 CLI 能力；只执行用户任务范围内的操作，远端写操作先核对目标及授权。
配置修改先读取 revision，用 --if-revision 更新或删除，完成后读取核对；遇到冲突重新判断。
JSON 通过 stdin 或私有输入文件传递，不把密码放进命令行，不把本机配置或秘密提交到仓库。
检查 JSON ok、error.code 和进程退出码。超时/输出超限时远端完成状态未知，禁止盲目重试写操作。
CLI 暂未覆盖的能力明确说明；不要虚构已连接、已传输或已取消。
```

验证：`python3 tools/cli-regression.py --binary .build/debug/cs-tool-x` 使用临时目录与模拟引擎，覆盖输入/协议、秘密字段、并发与版本冲突，不接触真实服务。Core 测试另覆盖双路输出、超时、退出码和文件权限。实际远端验证单列于 [VALIDATION.md](VALIDATION.md)。

0.0.8 起 `profiles tree` 返回 `connections[].identity/profiles` 与 revision；分组只是显示模型，不修改保存格式。`data browse` 输入仅接收 password/apiKey，`--level` 为 databases、schemas（PG）或 tables，tables 必须提供 `--scope`。元数据范围参数使用绑定值，不拼接 SQL；最多返回 500 行并标记截断。完整连接树约定见 [DATA_TREE.md](DATA_TREE.md)。

0.0.9 起 Redis 的 `data browse --level databases` 读取 INFO keyspace，只表示有数据的 DB；未列出的空 DB 不应推断为不存在。UI 模式和本机筛选不会改变 CLI 查询、凭据或授权边界。

## 0.0.10 本机预配置登录

`profiles credentials status UUID` 返回保存状态、是否有密码/API Key 及凭据文件 revision，不返回秘密。`profiles credentials set UUID --if-revision REV --input -` 从 stdin 接收 `{password, apiKey}`，明确保存为本机明文；可保存空对象表示有意使用空凭据。`profiles credentials clear UUID --if-revision REV` 删除对应登录信息。同账号、地址、环境、传输策略下的不同数据库共享凭据；清除会影响这些数据库的下次连接。

凭据文件独立于元数据，权限 0600，不留 `.backup`。set/clear 必须先 status 并携带 revision，冲突后重新读取。数据命令若未提供两个认证字段则使用已保存信息；显式提供任一字段会整份覆盖，不与旧凭据拼接。GUI 保存连接时可勾选本机保存，下次双击即可直连。存储是用户明确选择的明文，不声称加密。

## 0.0.11 Git 浏览

`git scan` 递归发现目录下的仓库；`git refs` 读取当前分支和引用；`git log` 提供拓扑历史、分页及仓库内的分支/文本/作者/日期筛选；`git show` 读取提交说明与变更文件。全部只读、不联网、不改分支或索引，GUI 与 CLI 共享实现。具体参数由当前安装版本 schema 获取，[预算及显示语义](GIT_BROWSER.md) 单独维护。


## 0.0.28 离线百宝箱

`toolbox list` 发现十项工具及真实模式，`toolbox run --input -` 接收 JSON；具体字段、上限和副作用以 schema 为准。GUI 与 CLI 共用 ToolCore 和同一工作进程，不访问网络、不写配置、不自动复制内容。文件 Hash 仅读取显式提供的普通文件，采用 256 KiB 分块；其他工具只处理本次文本。正则采用 ICU，与 JavaScript 正则语义可能不同。

计算在独立进程中执行：普通计算 4 秒，文件 Hash 30 秒；到期终止进程。单个文本 48 KiB、编码后的工作请求 128 KiB、结果 384 KiB。JSON 最大 128 层，比较每侧 1000 行；正则最多 500 匹配/32 捕获，替换超出预算报错，不返回半份替换结果。SHA1/MD5 仅用于旧式文件校验。随机密码使用系统安全随机源，拒绝采样、保证四类字符并安全打乱，不用于替代密码存储 Hash。

`python3 tools/toolbox-regression.py --binary .build/debug/cs-tool-x` 覆盖所有模式、流式文件校验、特殊文件拒绝、复杂正则的实际进程超时与恢复；Core 测试覆盖 Unicode、边界、字幕数字原文、时间单位与随机字符组成。无密码 Hash、图片编辑、Chart.js 执行或手柄能力，未用空入口冒充实现。


## 0.0.29 临时文本

GUI 在百宝箱中提供“临时文本”，纯文本/Markdown 预览切换，文本只在当前运行的内存中保存。退出清空；无保存、自动恢复、历史或云同步。显式导入只读取原文件，清空/替换前保留确认。CLI 不读取或修改 GUI 的临时手稿。

`text inspect FILE` 只读 UTF-8 文件，返回文本大小、UTF-16 长度和是否处于 Markdown 字节预算内；该布尔值不代表复杂度检查已经通过。`text preview FILE` 输出离线 HTML 与页面策略。具体输入/输出以 schema 为准。编辑/导入总量 32 MiB、单行 128 KiB，完整预览 4 MiB；读取工作进程 15 秒，解析 5 秒，HTML 8 MiB、AST 30000 节点/256 层。CommonMark 与表格、任务列表、删除线、自动链接由锁定的官方 swift-cmark 0.9.0 提供，COPYING 随包；源码 HTML/不安全链接默认省略，应用预览禁脚本和外部资源，图片不加载。无数学公式、流程图、实时所见即所得或图片附件编辑。
