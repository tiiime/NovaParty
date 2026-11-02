# 原型验证记录

更新日期：2026-11-01。引擎：Godot 4.6.1 stable。

测试设备：macOS / Apple M4 Pro，M2011K2G（Mi 11 / venus）、Android 13、1440×3200、Adreno 660，以及 TCL ak30a5、Android 9、1920×1080、Mali-G31。当前 APK 同时支持 ARM32 与 ARM64。

## 已通过

| 验证项目 | 结果 |
| --- | --- |
| 规则与界面检查 | 50 项检查通过；包含非法操作、五连胜、私有状态、恢复凭据，以及触屏/模拟鼠标去重和方向键确认 |
| UI 行为检查 | 10 项通过，新增中文字形与横竖屏安全区域，另含：横竖屏缩放、根窗口返回通知/信号、返回大厅和选牌焦点恢复；不替代真实 Android 返回键回归 |
| 桌面真实 TCP | 分片 UTF-8、指纹兼容、重复请求、过期版本、凭据重连、无效和超限帧通过 |
| 桌面完整对局 | 两个真实 Godot 进程完成五子棋和暗牌示例 |
| 桌面外部 ZIP | 运行时加载原本不在宿主中的规则和界面；安装后由新进程恢复通过 |
| Android 构建与安装 | APK 构建、签名、adb 安装及启动成功；中文界面和竖屏棋盘可用 |
| APK 内容一致性 | 两个内置 Mod 的清单和脚本与源码逐字节一致，未打入 tests/tools |
| 手机作为房主 | 电脑 Godot 客户端通过实际 Wi-Fi 地址加入；手机触屏完成五子棋，版本 0→9，黑棋获胜 |
| 手机暗牌对局 | 电脑通过 Wi-Fi 加入，双方完成三轮，版本 0→6；手机只显示本方手牌，双方提交后揭牌 |
| 手机作为加入方 | 手机输入电脑 Wi-Fi 地址并加入，完成整局五子棋；未使用 adb forward/reverse |
| 后台返回 | 手机参与者按 Home 切后台约 2 秒，再回到应用继续落子并完成对局 |
| Android 外部包导入 | 通过系统文件选择器选中下载目录中的独立 mobile_gomoku ZIP，以内容 URI 读取并复制到应用私有目录 |
| Android 重启恢复 | 结束应用进程并重新启动，外部 Mod 仍在列表，本地玩家短代号保持一致 |
| 外部包跨设备对局 | 手机重启后加载导入的 Mod，电脑加载同一 ZIP，通过指纹握手并完成整局 |
| 手机凭据重连 | 测试房主在版本 3 主动关闭 TCP；手机点击“重连”恢复玩家二及版本 3 棋盘，再完成对局至版本 9 |
| 修复后运行日志 | 最终 APK 的五子棋、重连和暗牌回归中，Godot 脚本与节点生命周期错误为 0 |

暗牌游戏是协议示例，不是标准扑克玩法。上述私有状态结论结合规则测试、逐玩家快照实现及真机界面检查；不代表提供旁路监听保护或防恶意房主作弊。

## 电视实测补充

电视已作为房主与手机完成五子棋（版本 9），作为加入方与电脑完成五子棋（版本 9），并与电脑完成遥控器暗牌三轮（版本 6）。横屏棋盘、方向键、确认和选牌焦点已实测。详细边界见 [电视验证记录](tv.md)。

测试发现已安装的 0.1.0 在 Android 返回时直接退出。0.1.1 已关闭默认返回退出并接入根窗口返回信号；桌面模拟行为检查通过，真实电视返回键需要用户通过 USB 更新后验证。电视安装校验设置未改动。

## 真机发现并修复的问题

1. Android 原生选包能力检测在该设备上退回引擎文件框。Android 分支改为直接调用 DisplayServer 的系统文件选择器，实际系统选包和内容 URI 导入通过。
2. 暗牌界面在按钮点击信号中同步销毁按钮，引发 `can_process / !is_inside_tree` 错误。改为延迟提交，最终 APK 三轮回归无此错误。
3. 触摸事件与其模拟鼠标事件都提交落子，远端模式下会产生多余拒绝和快照。忽略模拟事件；新增三项输入检查，真机修复后每次触屏只推进一次玩家操作。
4. JSON 数值导致界面出现“玩家 2.0”和版本“1.0”。显示时转为整数。
5. 断线时继续点击可能无反馈。Session 在运输连接不存在时直接提示先重连。

## 证据与复现

真机截图及电脑对端日志位于 `build/android/evidence/`，不会打包进 APK。可下载的应用位于 `build/android/novaparty-debug.apk`。

[Android 指南](android.md) 包含构建、安装与手动测试步骤。桌面回归运行：

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/integration.py
```

真机对手脚本支持指定手机地址和独立包：

```sh
Godot --headless --path . --script tests/bot.gd -- gomoku 27840 <手机Wi-Fi地址> 180
Godot --headless --path . --script tests/bot.gd -- mobile_gomoku 27840 <手机Wi-Fi地址> 180 <ZIP绝对路径>
```

电脑主持重连测试：

```sh
Godot --headless --path . --script tools/host.gd -- gomoku 27840 autoplay trace drop_once
```

第三版状态后只断开一次连接，房间与凭据保留。它验证的是主动 TCP 断开，不是 Wi-Fi 静默失联或网络切换。

## 未验证或未实现

- iPhone 真机、iOS 原生 arm64 模拟器与分发约束；电视标准 Leanback 启动入口。
- 电视外部 Mod 导入、标准 Leanback 启动入口和屏幕键盘的完整遥控器输入。
- 蓝牙、自动房间发现、跨网连接。
- 长时间后台、进程被系统回收、休眠、Wi-Fi 关闭和网络切换。
- 持久化对局恢复凭据、房主迁移、应用进程重启后恢复进行中的对局。
- 导入纹理、音频、场景资源；当前 Mod 示例使用脚本绘制和原始清单。
- 麻将具体规则、多于两位玩家、响应优先级、定时结算。
- Mod 更新/卸载、大型快照、观战、存档回放。
- 传输加密、普通客户端自动重发和第三方代码沙箱；0.1.5 协商心跳及常驻控制器的精确重试见后文。

当前结论覆盖一台 Android 手机、一台 TCL 电视与一台 Mac；不能推广为所有设备兼容或产品已完成。

## 历史：0.1.2 网络 Debug（2026-11-01）

- 原有规则 50 项、界面 7 项，以及 TCP 协议、两种完整对局、外部 Mod 安装恢复回归通过。
- `python3 tests/debug_integration.py`：真实 Godot 房主/加入方分别启用 Debug，验证认证、私有状态与动作过滤、双方最终回执、幂等重试、版本/对局保护、事件订阅与缓存溢出重同步、连接恢复，以及通过 CLI `--wait` 完成五子棋和暗牌整局。
- `python3 tests/debug_exports.py`：实际导出 Debug / Release PCK，分别由 Godot 4.6.1 macOS Debug / Release 原生模板执行；四种组合均加载主场景，只有 Debug 模板 + Debug 资源启用服务。Release 导出资源不含 debug/、tests/、tools/。该测试使用本机已安装的 macOS 模板。
- 0.1.2 ARM32 / ARM64 通用 APK 已构建；当前手机与电视上的旧对局未被中断。新 Debug 包的手机/电视网络连接、adb 首次取凭据和返回键回归，需更新安装后验证。
- 当时尚未实现 D2 / D3；0.1.2 接口报告 `hot_update: false`。后续状态见下节。

## 0.1.3 网络热更新（2026-11-01）

- macOS 真实双客户端：网络分块上传（超过 24 KiB）、分块重试、完整 SHA-256、路径/清单/大小/并行上传限制、唯一构建命名空间、局中界面与原始 JSON 资源更新、手动回退、重启恢复通过。
- 同一五子棋对局热更新前后，对局 ID、代次、版本、座位、玩家列表与棋盘完全一致；光标和焦点保持，输入信号只有一条连接。双方在单端更新后继续落子通过。
- 暗牌示例中，一方已提交且另一方等待响应时替换加入方界面，私有手牌、焦点与局面保持，三轮全部完成。
- 规则不同的候选在对局中被拒绝；大厅可选择规则新版本供下一局使用。协议 2 已验证不同表现构建可正常加入，协议 1 的完整包匹配回归通过。
- Android 13 / Mi 11：已安装 0.1.3，通过局域网读取凭据后上传、激活和回退；含两颗棋子的局面保持不变，Android PID 未变，继续完成九手五子棋整局。强制停止/重新启动后恢复所选构建，再创建房间验证蓝色资源加载，随后回退并返回大厅。见 `tests/android_hot.py` 与 `build/validation/android-hot-update.png`。
- 实际 Debug / Release 导出资源与 macOS 原生模板四种组合通过；只有 Debug 模板 + Debug 特性启用服务，Release 不携带热更新代码。既有 Debug 整局、规则/界面、网络与外部 ZIP 回归通过。
- TCL ARM32 电视安装 0.1.3 后，已通过遥控器方向键/确认键落子、LAN 热更新、九手整局、回退、强制停止重启恢复及真实返回键回到大厅。见 `build/validation/tv-hot-update.png`。iPhone 仍未验证。
- 局中规则迁移、原生/平台 SDK 自更新、完整 Godot 导入资源流水线和任意脚本异常自动回滚尚未实现。

## 0.1.4 常驻玩家与 iOS 模拟器（2026-11-01）

- iPhone 16 / iOS 18.5 模拟器构建、安装、运行；修复中文缺字和安全区域遮挡。SDK 26.2 与 runtime 18.5 不一致，采用开发工程资源编译调整；官方 4.6.1 模板实际为 x86_64，通过 Rosetta 运行。具体复现和限制见 [iOS 指南](ios.md)。
- iPhone 房主与桌面参与者独立自动完成 225 手五子棋；iPhone 加入桌面暗牌房间，完成三轮 6 次提交，验证私有手牌过滤。
- iOS 有棋子局面网络热更新与回滚保持对局不变；进程终止重启后恢复所选 Mod，再回退内置构建。证据 `build/validation/ios-simulator.json` 及截图。没有验证真实 iPhone/后台/网络切换。
- 独立常驻玩家通过本地策略持续行动；双真实客户端通过暂停恢复、进程锁、SIGKILL 重启恢复、换房保护；模拟落子已发出但回执丢失并断线，重连查询原请求后只确认一次行动。两种游戏完整对局通过。见 [常驻玩家](player.md)。
- 房间管理 API 校验应用实例、房间代次和本地 Session；精确请求重试、ID 复用拒绝、旧上下文拒绝、已有房间保护通过。
- 规则 50 项、UI 10 项、既有 TCP / 外部 ZIP / Debug / 热更新完整回归通过。Android 0.1.4 包已构建，尚未覆盖安装电视；0.1.3 真机证据沿用历史版本记录。

最终正常字重构建补测：通过 Simulator UI 点击创建房间，桌面加入后点击棋盘，RPC 校验黑棋只落一颗、版本只推进到 1；截图 `build/validation/iphone-touch.png`。这是模拟器点击生成的触控事件，非真实触屏硬件。

## 0.1.5 游戏链路恢复（2026-11-01）

新增可选 `heartbeat_v1`：协议 2 双方协商后启用，2 秒挑战、8 秒未确认断开；参与者 10 秒无 welcome 结束握手。旧对端不启用。常驻控制器对未确认操作采用退避重试，凭据重连后重置同一请求的发送预算。

真实桌面进程和 iPhone 16 / iOS 18.5 模拟器验证：健康空闲连接保持；TCP 关闭、双向静默丢包、上行/下行单向丢包后自动恢复原座位、同一棋盘与版本；已接受落子的回执丢失后，自动恢复并重复原请求，只执行一次。桌面额外验证协议 1 长时间空闲兼容、伪造 pong 不保活、无 welcome 握手超时。代理注入不等同于真实 Wi-Fi 切换或 iOS 后台回收。

旧 0.1.4 iOS 房主与新桌面客户端空闲 10 秒并继续落子通过。规则/UI、既有网络、Debug、热更新回归通过。复现见 [联机恢复](recovery.md)，诊断见 `build/validation/recovery.json` 与 `ios-recovery.json`。0.1.5 Android 通用包已生成，未覆盖安装电视；真实 iPhone 尚未验证。

## 0.1.6 动态首页与 i18n（2026-11-01）

- 星际派对首页已由真实 Godot 控件实现，包含小星星椭圆公转、轻微缩放和主角浮动；手机竖屏与电视逻辑横屏适配。隐藏首页暂停处理，减少动态效果冻结并保存。
- 平台英文 / 简体中文 key、格式占位符和导出目录检查；内置游戏的独立文案目录在清空平台翻译后仍能显示两种语言，未知语言回退英文，不修改过滤状态。
- UI 25 项、规则 50 项、TCP / 完整对局 / 外部 ZIP / Debug / 表现热更新与原生 Debug / Release 导出隔离通过。热更新与外部包安装回归应顺序运行，避免共享用户目录的临时包清理竞态。
- iPhone 16 / iOS 18.5 模拟器已实际启动中英文界面，验证动态时间与轨道位置推进、进房暂停、离开恢复，并录制 6 秒视频。证据见 `build/validation/home-ios.json`、`iphone-home-motion.mp4` 及同目录真实截图。
- 0.1.6 Android ARM32 / ARM64 包已生成；电视未覆盖安装，本版尚未做真实 iPhone / 电视动效性能回归。当前加入游戏仍手动输入地址，搜索房间未实现。详细范围见 [UI 与 i18n](ui.md)。


## 0.1.7 客户端 UI 热更新

- 生产入口改为稳定宿主 `app/bootstrap.tscn`；完整 UI 包通过认证 TCP 更新，Session、Mod 游戏视图及 Debug 连接保留。
- `tests/client_ui_hot.py`：完整包上传、版本与翻译拒绝、准备失败、五子棋/暗牌局中换壳并继续实际操作、回滚、重启恢复、启动保护标记回退通过。
- `tests/client_ui_state.gd`：15 项页面状态检查通过，覆盖封面选择、启动/加入页、地址端口、设置弹层、语言、减少动态效果和焦点。
- iPhone 16 / iOS 18.5 模拟器：真实导出应用更新平台脚本、纹理和字体，保持原 TCP 连接；局中回滚后与桌面设备继续落子，重启恢复及回滚通过。证据 `build/validation/client-ui-ios.json`、`iphone-ui-hot.png`。
- 规则 50 项、UI 38 项、完整联机与 ZIP 安装恢复、Debug、原 Mod 热更新回归通过。四种 Debug/Release 模板与导出组合验证通过，Release 不开放开发更新服务。
- Android 0.1.7 已生成双 ARM 签名 Debug 包。电视仍需安装一次新基础包，之后才能执行 `ui.push`；尚未声称本版 UI 包已在电视运行。


## 0.1.8 / 五子棋 0.2.0

五子棋改为电视左右布局和手机上下布局，明确展示身份、执棋、在线状态、当前回合及累计用时。确定性规则增加双人同意再开一局，发起端 SDK 增加独立时钟采样与断线暂停。结算弹窗、原生返回、设置返回焦点及跨 CanvasLayer 的中文字体均有回归覆盖。

`tests/gomoku_network.py` 已通过真实 TCP 的计时、暂停、重连、获胜、双人同意和新局时钟归零。TCL 电视基础包 0.1.7 已通过网络更新客户端 UI 与 Mod，并与基础包 0.1.8 的 iPhone 模拟器完成对局、结算和再开一局；实际遥控器输入落子/同意操作通过。模拟器原生触屏控制通道不可用，设备测试用 Debug 提交操作；触屏路径由 Godot Viewport 输入分发测试覆盖。证据见 `build/validation/gomoku-devices.json` 和对应原生截图。

安卓手机已成功覆盖安装基础包 0.1.8；电视普通 adb 安装仍返回 `INSTALL_FAILED_VERIFICATION_FAILURE`，未关闭系统校验。0.1.8 APK 已复制到电视下载目录，电视当前仍是基础包 0.1.7 + 最新 UI/Mod 热更新。

用户解锁手机后，`tests/gomoku_android.py` 已通过安卓真机与电视联机验证：手机实际 adb 触屏落子、电视遥控器落子、九手黑棋获胜弹窗、电视发起再开一局、手机触屏同意。同一会话进入第二局，棋盘和双方时钟重置，电视光标回到中心。手机原昵称保留；两端已返回大厅。报告为 `build/validation/gomoku-android.json`，原生截图为 `gomoku-android-playing.png`、`gomoku-android-result-waiting.png` 和 `gomoku-android-rematch.png`。

五子棋专门回归最终为 57 项、0 失败；客户端 UI 状态回归 15 项、0 失败。已修复并截图复核 iOS 结算弹窗的中文字体继承。计时与新局、原 Mod 热更新、Debug、客户端 UI 热更新、常驻玩家 225 手及四种 Debug/Release 导出隔离均通过。


## 0.1.9 / 星星跳绳 0.1.0

新增可选 Drop-in 会话与跳绳 Mod。专项 40 项、0 失败，三个真实 Godot 客户端的并发计数、离开/重入/空位复用、角色切换、空屏等待和活动 Mod 热更新通过。既有棋牌规则 50 项、UI 38 项、TCP/恢复/外部包回归及五子棋计时/重连/结算/再开一局通过。

Mi 11 已覆盖安装基础包 0.1.9。实际 adb 触屏选择控制器、真实加速度计检测和静止校准通过（基线约 9.76 m/s²），iPhone 模拟器作为展示端正确显示控制器加入和离开。未进行真人跳跃准确率测试。设备报告 `build/validation/jump-rope-devices.json`，原生截图 `jump-rope-android-role.png`、`jump-rope-android-calibrated.png`、`jump-rope-ios-display.png`。桌面渲染截图的跳跃次数为测试数据。

电视 0.1.9 普通 adb 安装被系统校验拒绝，未改变安全设置；最新 APK 已复制到 `Download/novaparty-0.1.9-debug.apk`，等待手动更新后才可加载本 Mod。动态人数 SDK 和安卓传感器开关需要新基础包，之后动作算法/参数/表现可以用 Mod 热更新。见 [星星跳绳](jump-rope.md)。

最终客户端 UI 状态 15 项、0 失败；整套客户端 UI 上传/激活/局中切换/回退/重启恢复与中断保护通过，四种 Debug/Release 导出隔离通过。三款 Mod 的中英文键、占位符、独立目录及英文回退验证通过。


## 0.1.11 / 局域网 Mod 共享与二维码

普通 SDK 增加活动游戏共享与独立 A→B 传递、mDNS 发现、下载确认/进度/取消、ZIP 与完整指纹验证、不可变版本安装及自动加入。Session 提供连接信息和二维码纹理，默认等待面板与跳绳 0.1.1 自控面板均已接入；扫码使用同一下载确认流程。

- 两台 Android 16 / API 36 ARM64 模拟器使用 Apple M4 Pro 硬件加速，实际 NSD 搜索、adb 点击游戏与下载确认、确认前零包字节、普通 SDK 下载、安装后自动加入及真实 TCP 落子同步通过。兼容版本直接复用。
- 使用模拟器合成虚拟场景相机展示 SDK 生成的二维码，Android 相机预览实际识别成功并加入另一台模拟设备。相机权限与取消入口已测试；没有使用真实手机/电脑摄像头。截图 `build/validation/lan-arm-camera-joined.png`。
- iOS 模拟器生成二维码、安卓离线 ZXing 解码、按解码信息加入 iOS 发起的游戏通过；此前 Android 真机与 iOS 模拟器 Bonjour 双向发现通过。本版未声称物理 iPhone 相机或新版电视安装验证。
- SDK 专项 30 项、五子棋 57 项、跳绳 40 项通过；独立 ModSender、双进程缺包下载/取消/重启恢复、损坏包/超大包/非 ZIP 拒绝、客户端 UI 局中热更新及 i18n 回归通过。

实际 Debug/Release 模板与导出资源四种组合通过；仅双 Debug 组合开放开发服务，Release 包含普通共享 SDK 且排除 Debug/测试/工具目录。

报告 `build/validation/lan-arm-devices.json`，真实模拟器截图 `lan-arm-rooms.png`、`lan-arm-confirmation.png`、`lan-arm-joined.png`。桌面 UI 截图为渲染检查，其中列表/下载详情使用测试数据。新原生 NSD/Bonjour/相机能力需要安装 0.1.11 基础包，之后 UI 与 Mod 可继续热更新。

0.1.11 最终 APK 已安装两台 ARM64 模拟器，并复制到真实电视 `Download/novaparty-0.1.11-debug.apk`，未尝试修改安装校验策略。电视仍需手动安装；模拟器最终启动无新增脚本错误。iOS 模拟器相机权限弹窗已出现，物理相机识码未验证。


## 0.1.12 / Debug APK HTTP 更新

新增仅 Android Debug 的认证 HTTP 接口，默认 27842，复用 Debug token；接收原始 APK、校验 SHA/包名/签名/Debug 标志/版本，再通过 PackageInstaller 发起系统安装。原生类只打入 Debug DEX；Release 导出无该类和 REQUEST_INSTALL_PACKAGES 权限。

Android 16 ARM64 模拟器已完成：首次安装来源授权页面、HTTP 上传完整 APK、实际 adb 点击系统“Update”、同版本覆盖安装、启动后持久记录恢复为 installed，系统 lastUpdateTime 推进。过程中修复安装会话输出流重复关闭导致会话被撤销的问题。

未认证、过大请求、缺 SHA、SHA 不符、非 APK、Release APK、版本降级、不同签名与不同包名均拒绝，临时包和最终可安装包清理通过。Debug 原有认证/两款游戏/结果重试/事件/CLI 回归、实际 Debug/Release 模板与资源四种组合通过。验证入口 tests/apk_update.py，记录 build/validation/apk-update.json，截图 apk-update-source-permission.png、apk-update-confirmation.png、apk-update-completed.png。未声称本版已在真实电视安装通过。使用与限制见 [APK 网络更新](apk-updates.md)。


## 电视游戏选择页焦点修复（0.1.12 UI 热更新）

游戏库显式维护随列数/游戏数量变化的方向焦点：每列底部通向启动按钮，启动向上返回最近浏览的卡片；电视底部返回/设置/启动可左右切换，手机按竖向布局处理。修复新增第四张“添加游戏”卡片后，自动方向搜索无法到达右下启动按钮的问题。UI 状态与真实方向输入回归 56 项通过，完整 UI 上传/局中切换/回退/重启恢复与中断保护回归通过。

已热更新至 TCL 电视，实际 adb 遥控器按键验证：暗牌与跳绳卡片向下直达启动、向上回原卡片；五子棋经过添加游戏向下到启动；底部左右切换后确认实际启动五子棋。测试结束已退出临时对局并停在选择页的启动按钮。证据 build/validation/tv-launch-focus.json 与 tv-launch-focus.png；无需重装 APK。


## 选择游戏流程与滚动条调整

首页入口及选择页标题改为“选择游戏 / Choose a game”。确认卡片后自动聚焦启动，原生返回键或 Escape 先回到已选卡片，在卡片上再次返回才回首页；选择页移除设置，保留首页和对局内设置。即便先浏览了其他卡片，返回仍定位实际已选游戏。选择页增加滚动内容内边距，右侧使用浅蓝圆角轨道和滑块。

界面专项 42 项、UI 状态与方向输入 64 项、中英文目录、完整 UI 热更新/局中切换/回退/重启恢复/中断保护通过。已热更新 TCL 电视，并用实际遥控器输入验证确认跳转、原生返回两级行为、底栏左右切换；截图和记录 build/validation/selection-tv-*.png、selection-tv.json。


## UI 音效与电视焦点强化

从 itch.io 下载 heyheythere 的免费 Soft UI SFX Free（CC BY 4.0），接入五个原始 OGG 音效。资源许可、来源与映射位于 assets/audio/ui，设置中保留作者和许可链接。“界面音效”可关闭并持久保存；导航限频，确认后抑制重复导航声，UI 替换/隐藏时停止播放。音频按原始字节加载并随 UI 包分发，无需重装 APK。

聚焦按钮放大 4.5%、卡片 3.5%；由浅青色改为橙金边缘、深色外轮廓、奶白内边和缓慢呼吸光晕。页面短渐显；减少动态效果保留静态亮边与放大。实际渲染复查修复了阴影盖暗按钮及卡片裁掉外侧光晕的问题。横竖屏真实 Godot 渲染截图 feedback-home-tv.png、feedback-grid-tv.png、feedback-home-phone.png、feedback-settings-phone.png。

音效专项 14 项通过，AudioEffectCapture 检测到非零 PCM，峰值约 0.1855；UI 状态/输入 64 项、UI 42 项、i18n 和完整 UI 热更新/局中切换/回退/重启恢复通过。TV 已通过真实遥控器验证焦点放大、确认/返回音效事件、关闭后静音及再次开启，加载 5 个音频流，记录 feedback-tv.json；未验证实体扬声器听感。电视曾进入 TCL 音箱页，当前 adb 截图全黑，最终电视观感未由截图确认，已询问用户实际画面。

电视历史 UI 包达到容量上限后，先备份 5 个较旧测试包到 build/device-backups/tv-ui-before-audio-final，保留当前/上一版及最近无音效版本，停止应用后再清理并重启，随后热更新最终版本。没有修改系统安装校验或电视安全设置。

补测 Release 音频资源：导出后 OGG 会变为 Godot 导入资源，已增加原始 OGG / 导入资源双路径加载；tests/export_audio.py 在没有源码及导入缓存的隔离项目中加载实际 Release 包，5 个音效均可读，署名与许可存在，Debug 目录不存在。


## Android 手机形态补测

用户确认电视已关机，停止电视操作，改用 Android 16 / ARM64 手机模拟器。实体安卓手机当前未连接 adb，原无线地址不可达，因此本轮不声称真机验证。已热更新与电视相同的最终 UI 包，用 adb 实际触屏验证：打开游戏网格、选择卡片自动聚焦启动、原生返回两级行为、4.5% 按钮 / 3.5% 卡片放大和橙金亮边；音效关闭后触屏导航/确认保持静音，减少动态效果冻结首页轨道。

强制停止再启动后，两项偏好和热更新 UI 均恢复，随后实际触屏恢复音效开启/正常动态。额外触屏启动五子棋并验证 launch 音效事件，之后关闭临时游戏，返回首页。截图 feedback-android-home.png、feedback-android-grid.png、feedback-android-launch.png、feedback-android-settings.png、feedback-android-started.png；记录 feedback-android.json。没有验证实体手机扬声器听感。


游戏命名调整：`jump_rope` 当前中文显示名统一为“跳绳”，英文为“Jump Rope”，清单、游戏内文案、参考说明与本地化测试同步更新。历史记录中的“星星跳绳”指同一 Mod。


## 0.1.13 / 仅内置五子棋

客户端默认根目录仅保留 gomoku。新增编辑器导出白名单插件，所有 Android Debug/Release、iOS 导出只打入 mods/gomoku；导出插件本身不进入客户端。跳绳与暗牌源码保留，可独立打包导入；不删除用户已经安装的外部游戏。ModLoader 对缺失内置清单安静返回验证失败，使旧 UI 热更新包仍探测 removed builtins 时能够正常启动。

tests/bundled_mods.py 检查三个实际导出包，只存在五子棋；临时新增 Mod 的脚本和导入贴图均被过滤。在无源码的隔离导出环境中验证默认仅五子棋 + 添加游戏、旧 UI 探测兼容，以及外部跳绳 ZIP 安装。Android Debug/Release 原生模板四种组合与 UI 热更新/回退/恢复通过；三个客户端通过外部包加载跳绳并完成并发、加入离开和表现热更回归。

0.1.13 Debug 和 Release APK 均已构建，实际 APK 资源列表仅含 assets/mods/gomoku。手机 ARM64 模拟器通过现有认证 HTTP 更新到 0.1.13，触屏确认系统安装，旧 UI 热更新包恢复后游戏列表仅显示五子棋。截图 gomoku-only-android.png，记录 gomoku-only-android.json。电视按用户要求保持不操作；iOS 本轮验证导出内容，没有重新安装模拟器应用。


## TCL 电视 APK 更新实测（0.1.13）

普通 `adb install -r` 仍返回 INSTALL_FAILED_VERIFICATION_FAILURE。随后复用客户端认证 HTTP 上传 0.1.13 Debug APK，摘要/包名/签名等校验通过，状态进入 awaiting_confirmation，出现系统标准更新确认页，未要求新增授权。通过已显示的系统“安装”按钮确认后，电视成功安装 versionCode 14 / versionName 0.1.13，installerPackageName 为 org.novaparty.prototype。

重新启动后 Debug RPC 恢复，HTTP 状态为 installed，旧 UI 热更新包正常恢复，游戏选择页仅显示 gomoku。记录 build/validation/apk-update-tv.json，截图 apk-update-tv-confirmation.png、apk-update-tv-success.png。本次没有修改系统安装校验或其他安全设置。结论是电视可通过当前 HTTP + 系统确认路径更新 APK，普通 adb 安装路径仍受限。
