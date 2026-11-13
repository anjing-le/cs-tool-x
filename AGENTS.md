# cs-tool-x

- 原生 macOS 14+ 开发工作台。Swift/AppKit/SwiftUI 宿主、Rust 数据进程、SwiftTerm/OpenSSH、Sparkle；不恢复旧 Tauri 原型，不默认加入账号、云同步或插件市场。
- 首页沿用 FinanceX 的等宽卡片结构，配色使用 ShellX 暖纸张、鼠尾草绿和浅色分隔线，目前只有 Shell、数据。无首页说明墙、设置卡片或常驻侧栏；SSH 与文件传输必须位于同一个 Shell 工作区，右侧文件栏，不拆成首页两个模块。进入后各模块独立布局，Cmd+1 返回首页。Shell 复用 anjing-shell 的服务器分组、搜索、同窗编辑、标签和分屏，不迁入假服务器/日志/传输成功状态或私人指针素材。保持兄弟项目不变。
- 不使用系统钥匙串：客户端密码/API Key 仅在当前会话内存，SSH 密钥由用户自己的文件/Agent 管理，明确传 UseKeychain=no / AddKeysToAgent=no，不自动导入保存。连接元数据可保存但不含秘密字段。
- OTA 不使用钥匙串。私钥只允许放在仓库外、当前用户所有的 0600 普通文件，签名工具用 --ed-key-file 读取；绝不输出内容、进入仓库或打进 app。固定 Ed25519 公钥与 feed，从首个发布版本起保持稳定。
- 应用使用 ad-hoc 完整性签名；OTA 来源认证使用签名 feed 和先验签的 Ed25519 更新包。不声称有证书身份或 Apple Developer ID / 公证。缺失更新私钥时停止发布，不降级为未验签更新。
- 正式 Bundle ID cc.anjing.cs-tool-x，执行文件 CSToolX；开发包 .dev，配置空间分离且关闭 OTA。版本与 build 同时递增，核对前后真实包的完整性、应用标识、公钥和更新源。用户自行确认更新安装，不替用户覆盖已安装应用。
- UI 主线程不做网络、数据库、SSH I/O 或大结果转换。按需启动、资源有界，返回首页/切换标签保留会话；关闭分屏/标签/退出释放进程；过期回调不能覆盖新状态。
- 数据查询模式不是 SQL 沙箱；客户端超时不等于服务端取消。保持 SSH 主机指纹校验。SFTP 控制台不能描述成已完成的图形化文件管理器。
- Public 仓库 anjing-le/cs-tool-x，Git remote 使用 git@anjing-le:anjing-le/cs-tool-x.git。只提交源码/文档/公有资源，排除 .local、dist、私钥、真实配置、数据库 fixture 数据与个人素材。
- 验证范围见 docs/VALIDATION.md。自动检查、模拟协议、真实环境和实际 OTA 安装分别报告；不把规划或性能目标写成已完成。真实目标、TLS、读写范围不确定时先核实，不推定破坏性授权。

- 客户端指针走统一 WritingCursors：普通、按钮、文本、拖动、禁用与分隔线使用缓存自定义对象；不新增空闲轮询或全局鼠标监听。个人同款图片与 NOTICE 仅存本机 Application Support/<app>/Cursors（或 ignored .local 原件），不可进入源码、app 或 OTA。公开包使用代码绘制的替代族。系统窗口边缘交互保持 macOS 管理。

- 客户端自有表单、按钮、勾选、下拉、提示与详情使用 PaperControls/Theme，不重新引入系统 bezel、强调色焦点框、NSAlert 或 NSPopUpButton。Shell 的 Ink 主色从 Theme 读取。下拉须保持键盘选择、Escape/外部点击关闭，关闭连接表单时清理子菜单与监听；密码仍使用安全文本编辑语义。系统文件面板、菜单栏和 Sparkle 自带更新窗口是当前外部 UI 边界，未自绘。

- 本机日常入口只保留 /Applications/cs-tool-x.app。用户已要求清理 Dev、旧 DataX 与构建备份的可运行副本；不再额外启动或固定 Dev。后续构建仅作临时产物，结束后清理多余 .app，历史发布保留 ZIP；不得删除连接配置、个人指针或发布私钥。常规 OTA 安装仍由用户确认。本次图标更换与收敛为一个正式安装已获用户授权。图标原始附件 assets/AppIcon-original.png；生产图标 assets/AppIcon.png 是去掉外部奶油色底块的透明图案。不得添加任何背景、圆角底板或图标 bezel，保留袋子/铃铛/口袋完整轮廓与内部白色。使用 scripts/make-icon.py 打包。
