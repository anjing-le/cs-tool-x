# 指针一致性 · 0.0.2

普通与点击状态使用本机其他客户端相同的图片、24pt 逻辑尺寸和归一化热点。个人主题安装在 Application Support/cs-tool-x/Cursors，应用与 OTA 不包含图片；目录会在更新后保留。开发包使用 cs-tool-x-dev/Cursors。

自定义指针角色覆盖普通区域、SwiftUI 首页卡片、原生/自绘按钮、编辑和只读可选文本、密码框、禁用控件、窗口拖动、终端与分隔线。文本和缩放使用自绘语义形状；物理窗口边缘与系统管理的外部面板不接管。

所有角色由缓存对象提供，使用 cursorUpdate 事件和控件实际命中位置解析。SwiftUI 卡片使用不拦截点击的透明角色区域；弱引用注册表不保留已经移除的视图。窗口与本进程事件协调层在嵌套控件处理之后统一指针，处理终端库不可覆写的 I-beam 处理器。不新增空闲轮询或全局鼠标监听。

可运行的检查：

```sh
mkdir -p .local
swiftc -parse-as-library Sources/CSToolX/WritingCursors.swift Sources/CSToolX/WritingCursorPreviewTheme.swift Sources/CSToolX/WritingDragCursor.swift tools/cursor-regression.swift -o .local/cursor-regression
.local/cursor-regression
```

本机可额外传入合法个人素材目录，验证尺寸、热点和整个主题成对加载。已验证 FinanceX、EnglishX、ShellX / createX 的可用本机素材与当前副本一致。检查覆盖普通/按钮/文本/密码/禁用/父级角色、缓存身份、替代族均为自定义对象与一致尺寸、两个缩放方向、透明区域不吞点击和弱引用生命周期。

个人素材说明禁止直接再分发。只在本机安装，不将图片或 NOTICE 打进公开仓库、应用和更新包；公开包无本机主题时使用代码绘制的替代族。
