# 图标与单一安装 · 0.0.4

用户附件原件保留在 assets/AppIcon-original.png。生产图标 assets/AppIcon.png 使用内置 imagegen 去除外部奶油色圆角纸张底块，外围为透明 alpha；袋子、铃铛和内部白色口袋保留。完整编辑提示词在 assets/AppIcon-edit-prompt.txt。这是一份透明抠图派生文件，不声称与原件逐像素相同。

scripts/make-icon.py 只缩放/打包图标为 macOS 的 16–1024px 标准 ICNS，不添加背景、底板、边框或阴影。安装包与 OTA 使用同一 ICNS。

本机正式应用位于 /Applications/cs-tool-x.app。原项目中的 Dev、旧 DataX、0.0.1/0.0.2 备份、0.0.3 构建及最初带底块的 0.0.4 被移入废纸篓；连接配置、个人指针和签名文件未纳入清理操作。Dock 原来的 Dev 固定项替换为正式路径。

已扫描 /Applications、用户 Applications、project、Downloads、Desktop、Documents（排除废纸篓和依赖目录），仅发现一份对应应用。Dock 仅有一个对应固定入口。透明图外围/四角 alpha 为零，内部不透明；正式应用和签名更新 ZIP 中的 ICNS 与生产资源一致，应用通过完整性检查，正式路径启动显示首页。不是对外部磁盘或全卷所有位置的绝对清点。
