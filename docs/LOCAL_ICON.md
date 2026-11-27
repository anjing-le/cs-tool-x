# macOS 本地图标外观

源 PNG 和 ICNS 有真实透明通道，运行中直接使用 NSApplication.applicationIconImage。本机 macOS 27.0.1 在退出后仍为普通应用图标生成底板；2026-11-27 的系统图标回读与用户截图一致。

FinanceX 的本地预览使用 Finder 自定义图标。这里采用同一平台接口 [NSWorkspace.setIcon](https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:))，仅设置本机正式安装。它支持透明图像，不改变工具箱图案；未修改 FinanceX 项目。

## 应用与恢复

在本仓库运行：

```sh
python3 tools/local-file-icon.py apply
python3 tools/local-file-icon.py inspect
```

apply 要求当前安装先通过严格签名验证、没有既存自定义图标。使用安装内的 Contents/Resources/DockIcon.png，核对操作前后全部 Contents 文件字节和符号链接一致。只允许 /Applications/cs-tool-x.app，不安装应用、不清理全局图标缓存、不重启 Dock、不创建后台任务。

回执、锁、辅助程序及系统图标回读位于 ignored .local/dock-icon/；回执为 0600，记录原属性和文件摘要，不进入源码、应用或更新包。

恢复干净状态：

```sh
python3 tools/local-file-icon.py clear
codesign --verify --deep --strict /Applications/cs-tool-x.app
```

clear 只在安装内容及图标元数据匹配回执时执行，清除本轮设置，将生成的 Icon 文件移到废纸篓，恢复原属性。其他内容或元数据发生变化时停止。已实测 apply → clear → 严格签名通过 → 再 apply。

## 签名与更新边界

自定义图标附加 FinderInfo／资源叉及根目录 Icon\r 文件。即使全部 Contents 字节不变，严格 codesign 也会报告 resource fork / Finder information detritus。不能宣称当前定制状态严格签名通过或已公证，不能仅凭摘要相同忽略其他签名问题。

不关闭签名检查、不重签、不把定制元数据打进发布包。发布、验证上一版本身份、安装包逐文件复核前，必须先 clear 并恢复严格验证通过；OTA 安装完成且新包完整性验证通过后，再 apply。应用更新可能覆盖此本机设置，因此每次由 Codex 升级后重设；手动更新后若出现底板，也需重新 apply。

运行中 Dock、退出后的固定入口、Finder 分别验证。系统图标回读和 Finder 快速查看不能替代真实 Dock 截图；Dock 自动化不可读时由用户核对。当前仅维护本机外观，客户端仍为 0.0.37。
