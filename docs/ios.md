# iOS 模拟器开发与验证

2026-11-01 已在本机 iPhone 16 / iOS 18.5 模拟器运行 0.1.4。宿主为 Apple M4 Pro，Xcode 26.3 / SDK 26.2、Godot 4.6.1。没有中心服务器，模拟器和桌面均运行完整客户端。模拟器共享 Mac 网络，本次对端使用 127.0.0.1；这不替代真实 iPhone 的 Wi-Fi、局域网权限和后台行为测试。

## 启动和构建

```sh
xcrun simctl list devices available
xcrun simctl boot <UDID>
xcrun simctl bootstatus <UDID> -b
open -a Simulator
python3 tools/build_ios_simulator.py --device <UDID> --install --launch
```

产物为 `build/ios/SimulatorBuild/NovaParty.app`。预设 `iOS Simulator Debug` 携带 `novaparty_debug`，包括本地网络用途说明。只面向开发模拟器，不含分发签名；其中的占位 Team ID 不代表已配置真机签名。

本机官方 Godot 4.6.1 iOS 模板的 simulator xcframework 目录标为 arm64+x86_64，但 `lipo -info` 显示实际静态库只有 x86_64。脚本检查真实架构，在本机使用 Rosetta 运行；未验证原生 arm64 模拟器。相关 [Godot 问题记录](https://github.com/godotengine/godot/issues/118161)。

本机安装的 iOS 18.5 runtime 与 SDK 26.2 不匹配，常规 scheme 构建的资源编译工具会要求 iOS 26 runtime。脚本仅在生成的模拟器 Xcode 工程里移除启动 storyboard 和图标资源编译项，使用空 `UILaunchScreen`，直接构建 simulator target。没有修改系统 Xcode；没有正式图标/启动画面的验证。后续真机与发布构建应恢复常规资源编译、设置真实签名并单独验证。

## 网络调试

模拟器启动后，读取应用私有数据目录中的连接文件（包含令牌，不提交仓库）：

```sh
container=$(xcrun simctl get_app_container <UDID> org.novaparty.prototype data)
(umask 077; cp "$container/Documents/debug/connection.json" /tmp/novaparty-iphone.connection.json)
python3 tools/nvctl.py --connection /tmp/novaparty-iphone.connection.json device.info
python3 tools/nvctl.py --connection /tmp/novaparty-iphone.connection.json room.create '{"game_id":"gomoku","port":27840,"nickname":"iPhone"}'
```

`user://` 在本次模拟器映射到 Documents。每次进程重启后重新取连接文件；不要依赖固定容器 UUID。Debug 默认监听 Mac 的 LAN 地址，注意避免与桌面实例的 Debug 端口冲突。桌面测试实例使用独立 127.0.0.1 临时端口。

完整复现（会离开模拟器中的现有测试房间）：

```sh
python3 tests/ios_simulator.py --device <UDID>
```

## 实测结果

- iPhone 作为房主，桌面加入，两个独立常驻策略进程自动完成 225 手五子棋，双方最终棋盘一致。它们无需聊天唤醒；最后一次策略计算至最终回执分别约 83 / 118 毫秒，不代表所有落子的统计延迟。
- 已有两颗棋子时，通过网络上传可信 Mod，切换棋盘 JSON 颜色资源并回滚：应用实例、对局、版本、座位、玩家和棋盘保持一致，随后继续完整对局。
- 终止并重新启动应用，已选 Mod 从私有文件恢复；可回退至内置版本。这是 Mod 恢复，不是进行中的对局恢复。
- iPhone 作为加入方完成暗牌示例三轮、6 次提交；只读取自己手牌，双方终局一致。暗牌是协议示例，不是完整扑克规则。
- 捆绑 Noto Sans SC 后中文不再缺字，按原生像素与逻辑视口比例映射安全区域，避开 Dynamic Island 和底部手势条。变量字体使用数值 OpenType 标签设置正常字重，规避本版字符串标签未生效的问题。

证据在 `build/validation/ios-simulator.json`、`iphone-hot-update.png`、`iphone-lobby.png`。本次没有验证真实 iPhone、蓝牙、后台挂起、网络切换、App Store 分发以及 iOS 原生文件导入。

最终正常字重构建补测：通过 Simulator UI 点击创建房间，桌面加入后点击棋盘，RPC 校验黑棋只落一颗、版本只推进到 1；截图 `build/validation/iphone-touch.png`。这是模拟器点击生成的触控事件，非真实触屏硬件。

## 0.1.5 联机恢复补测

已安装模拟器新构建，使用 `tests/recovery_integration.py --ios-device <UDID>` 验证游戏 TCP 明确断开以及静默、单向丢包时的心跳与自动凭据重连。具体结果和边界见 [联机恢复](recovery.md)；不推断真实设备后台或网络切换能力。
