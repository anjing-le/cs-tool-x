启动时直接使用透明 PNG 设置运行中的 Dock 图标，去掉系统 bundle 图标显示路径附加的底板。

- 打包独立 DockIcon.png，保留透明通道；ICNS 保留为基础图标与加载失败回退。
- 本机更新同一个 /Applications/cs-tool-x.app，不安装 Dev 或额外客户端。
- 此覆盖作用于运行中的 Dock 图标；退出后的固定图标、Finder 显示分别由系统处理。

凭据、连接配置和更新验签规则保持原有行为。
