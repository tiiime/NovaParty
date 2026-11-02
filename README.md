# NovaParty（星星大作战）

基于 Godot 的无中心服务器联机游戏平台原型。每台设备运行完整客户端，游戏规则和界面作为可信 Mod 加载。

当前基础客户端为 **0.1.13**，安装包仅内置五子棋，包含最新选择流程、音效和焦点效果。跳绳与暗牌示例保留源码，可独立打包后通过“添加游戏”或局域网传递安装。已完成、验证边界、未完成事项及代码状态统一见 [开发现状](docs/status.md)。

已在 **macOS + Godot 4.6.1**、**Android 13 / Mi 11** 和 **Android 9 / TCL ARM32 电视** 上验证联机。手机支持触屏、外部 Mod 导入、重启恢复和凭据重连；电视已完成横屏、遥控器及棋牌对局。另已通过 iPhone 16 / iOS 18.5 **模拟器**联机、热更新和恢复测试；真实 iPhone 尚未验证。

## UI 设计规范

星星大作战的 v0.3 UI 采用亮黄星星、饱和蓝天空与蓝白玩具质感，增加派对式庆祝层次。客户端 UI 开发先读 [Design Cheat Sheet 与规范](docs/design/README.md)，其中包含可编辑 SVG、手机/电视示意、设计参数及已确认需求。大厅保持统一，各游戏保留自己的美术风格。0.1.6 已实现真实动态首页、中英文切换与减少动态效果，见 [UI 实现与 i18n](docs/ui.md)。

## 启动

用 Godot 4.6.1 打开 `project.godot`，运行项目；或：

```sh
Godot --path .
```

macOS 本机 Godot 位于 `/Applications/Godot.app/Contents/MacOS/Godot`，可代替上述 `Godot`。

一台设备通过“选择游戏 → 启动游戏”发起对局，另一台在“加入游戏”中搜索附近游戏、扫码，或手动填写地址加入。缺少兼容 Mod 时先确认下载，校验安装后继续加入。无账号、无中心服务，每局由发起设备主持。

同一电脑模拟两台设备时，为第二个实例使用独立档案：

```sh
Godot --path . -- --profile=guest
```

五子棋支持点击落子、方向键移动和确认落子。暗牌示例由双方各选一张牌，同时揭晓，三轮结算；它用于验证私有状态与并行响应，不是标准扑克玩法。

参与者断线后，在原应用进程、原房间仍存在时点击“重连”。恢复凭据暂只保存在内存中。房主退出后不能恢复原房间；没有房主迁移。

## 本地开发配置

首次运行复制 `cp .env.example .env`，填写自己的设备序列号、电视 adb 地址和工具路径。Python 构建及设备测试工具自动读取配置，命令行参数优先；`.env` 不提交，也不导出到应用。详见[开发配置](docs/development.md)。

## Mod 开发与打包

参考 `mods/gomoku`（公开棋盘）和 `mods/hidden_cards`（私有手牌），阅读 [SDK 契约](docs/sdk.md) 与 [AI 开发 Skill](skills/novaparty-mod/SKILL.md)。客户端仅内置五子棋。默认棋牌会话为两位玩家；可选 Drop-in 模式支持动态加入/离开，外部跳绳 Mod 已使用最多五台设备的配置。

```sh
python3 tools/pack_mod.py mods/gomoku build/gomoku.zip
```

普通 ZIP 目录为 `mods/<id>/...`；网络共享与热更新使用不可变的 `mod_versions/<id>/<build_id>/`。点击“添加游戏”选择可信 ZIP，客户端复制到私有目录并在重启后加载。不同版本不覆盖已挂载内容。打包、指纹兼容与传递流程见 [SDK 契约](docs/sdk.md)及[局域网共享](docs/lan-sharing.md)。Android 真机已通过系统文件选择器导入、重启恢复与联机验证。

Mod 支持清单列出的 GDScript 与原始文件；通用 Godot 导入资源流水线尚未统一。客户端 UI 热更新已验证可移植图片、字体和音频。可信代码可以执行，尚无第三方代码沙箱。

## Android

```sh
python3 tools/build_android.py
```

输出 `build/android/novaparty-debug.apk`，包含 ARM32 与 ARM64。已构建的最新基础包位于 `build/android/novaparty-0.1.13-debug.apk`，历史 Release 原型包为 `build/android/novaparty-0.1.13-release.apk`。Android/iOS 导出均只保留五子棋 Mod；项目导出插件使用白名单，其他 Mod 源码留作外部包。本次已直接将工程、包 ID、原生桥接、发现服务与二维码协议统一为 NovaParty；Android ARM64 与 iOS 模拟器已安装新包并完成发现、二维码解析和加入验证。电视上的旧包需首次手动安装新包，之后继续使用同包更新。构建与设备边界见 [Android 指南](docs/android.md)和[开发现状](docs/status.md)。

GitHub 自动打包、正式签名 Secrets 和下载产物的方法见 [GitHub Actions 指南](docs/github-actions.md)。

## 网络 Debug

0.1.3 Debug 包提供令牌认证、玩家可见快照、合法操作、状态订阅及带最终回执的提交接口，配套 `tools/nvctl.py` 供人和 AI 调用。参见 [连接与 RPC 契约](docs/debug.md)。支持网络上传 Mod、局中替换界面/原始资源、回退和重启恢复，见 [热更新指南](docs/hot-updates.md)。规则变化可在大厅选择用于下一局，局中规则迁移尚未实现。Release 排除开发服务。

## iPhone 模拟器与常驻玩家

[iOS 指南](docs/ios.md) 包含可复现的构建、安装及完整测试。常驻玩家通过 Debug SDK 独立持续行动，支持暂停、恢复和回执重试，聊天结束后仍可运行，见 [使用说明](docs/player.md)。0.1.5 已实现协商心跳与断线恢复，支持静默丢包后的凭据重连，详见 [恢复边界](docs/recovery.md)。

## 验证

```sh
Godot --headless --path . --script tests/run.gd
GODOT=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/integration.py
python3 tests/i18n.py
python3 tests/debug_integration.py
python3 tests/hot_integration.py
python3 tests/player_integration.py
python3 tests/recovery_integration.py
# macOS 原生导出隔离验证
python3 tests/debug_exports.py
```

第一项执行规则和界面实例化检查。第二项启动真实 Godot TCP 房主和客户端，验证完整对局、身份恢复、私有状态、协议异常，以及外部 ZIP 中新规则与界面的运行时加载。Python 需要 3.9 或以上版本，测试会监听临时本地端口。

截图检查（需要图形会话）：

```sh
Godot --path . --script tests/capture.gd
```

输出 `/tmp/novaparty-ui-0.png` 与 `/tmp/novaparty-ui-1.png`。

## 文档

- [开发现状与下一阶段建议](docs/status.md)
- [需求草案](docs/requirements.md)
- [SDK 与 Mod 契约](docs/sdk.md)
- [协议草案](docs/protocol.md)
- [验证结果与后续步骤](docs/validation.md)
- [Android 构建与真机测试](docs/android.md)
- [电视验证与待回归项](docs/tv.md)
- [Debug 网络接口与热更新规划](docs/debug-design.md)

当前不包含蓝牙、麻将具体玩法、存档回放、普通客户端动作自动重发与加密传输。局域网原型使用明文 TCP；隐藏手牌过滤约束的是消息接收者，不提供网络旁路监听保护。

客户端基础包 0.1.7 起支持完整平台 UI 网络热更新：参见 [打包、更新与回滚](docs/client-ui-updates.md)。旧电视先安装一次新基础包，之后封面列表、设置、首页、平台文案与 UI 资源可直接更新。

五子棋 0.2.0 支持电视/手机专门布局、双方累计用时、胜者弹窗和双方同意再开一局，详见 [五子棋说明](docs/gomoku.md)。权威累计计时需要发起端使用 0.1.8 SDK；纯界面仍可热更新。

跳绳 Mod 支持大屏展示与手机体感控制器，随时加入/离开；需要 0.1.9 基础客户端。玩法、动作识别与兼容边界见 [跳绳](docs/jump-rope.md)。

0.1.11 已加入系统 mDNS 游戏发现、普通 SDK 的设备间 Mod 传递与确认下载、二维码生成及相机扫码加入。缺少游戏时下载校验后自动加入；游戏可以控制二维码布局。参见 [局域网共享与二维码 SDK](docs/lan-sharing.md)。新原生能力需安装一次 0.1.11 基础包，之后仍支持 UI / Mod 热更新。

Android Debug 0.1.12 支持通过认证 HTTP 上传 APK 并触发系统安装，默认端口 27842，提供 `tools/apkctl.py`。参见 [APK 网络更新](docs/apk-updates.md)。Release 不包含该服务与安装权限。
