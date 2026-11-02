# 五子棋 Mod 0.2.0

电视采用左棋盘、右上信息、右下纵向操作；平台进入该 Mod 后收起重复标题、成员栏和底部操作。手机竖屏保留大触控棋盘，把双方身份与用时并排放在棋盘下方，设置/退出靠底部；横屏沿用左右布局。中英文文案随 Mod 携带。

棋盘支持触屏、物理鼠标和遥控器，显示最后一手标记与获胜连线。遥控器在棋盘最右列继续向右可进入操作列表，向左回棋盘。双方信息包括昵称、公开短代号、执棋颜色、自己/对方、在线状态；当前落子方同时通过文字和卡片边框标识。

## 累计计时

采用双方累计思考用时，不限时、不超时判负。两人到齐后开始，只累加当前回合；连接断开后暂停，恢复后继续。结算冻结用时，双方同意再开一局后归零。

基础包 0.1.8 的发起端提供权威时钟。SDK 使用单调时间，规则只通过可选 `clock_context(state)` 返回 `{seat, round}`，规则代码不读取时间、不把墙上时间写入棋盘状态。快照额外携带 `clock: {elapsed_ms, running_seat, round, synchronized}`，每秒同步一次；显示端在样本之间平滑累计。时钟采样不增加 revision、不提交棋子动作。公开玩家信息增加由身份 ID 哈希得到的短 `code`，不暴露重连令牌或原始身份 ID。

旧基础包可加载 Mod；没有权威时钟时显示“计时需新版客户端支持”，不会显示伪同步计时。0.1.7 作为加入方可以显示 0.1.8 发起端发送的时钟；电视自行发起并计时仍应安装 0.1.8。

## 结算与再开一局

结束时弹窗展示胜者昵称、自己胜/负或平局、局数、手数和双方用时，提供再开一局、退出游戏、查看棋盘。弹窗隔离遥控器焦点；返回先关闭弹窗，之后可通过“查看结果”再次打开，不随重复快照反复弹出。

`rematch` 是双方独立同意的规则动作。首个同意保留棋盘和结算状态，双方都同意才开启下一局；保持原连接、身份、game_session_id 和单调递增 revision。新局清空棋盘、重置用时和遥控器光标，仍由黑棋先行。请求包含当前 round，旧局请求不能影响新局。双方同时点击造成 revision 竞争时，仅对显式点击意图延后重试，不在 render 中发送动作，也不会自动替玩家同意。

Mod 的规则指纹已改变，不能替换正在运行的旧版规则；需先结束/退出旧局，再在开始页面使用新版本。后续纯表现修改仍可局中热更。

## 宿主 UI 扩展

- `wants_fullscreen()`：宿主让出游戏区域，隐藏重复栏位。
- `platform_action(action)`：可选信号，仅请求 `settings`、`reconnect`、`exit`；宿主负责会话生命周期，Mod 不依赖 app 业务路径。
- `set_platform_state(dictionary)`：宿主提供连接状态、是否可重连和操作反馈。
- `focus_default()`、`restore_platform_focus(action)`、`handle_platform_back()`：处理进入、关闭设置及返回键的焦点。
- `on_command_notice(code)`：允许表现对明确的并发同意冲突处理重试；普通错误仍由平台显示。

旧宿主没有这些扩展时，Mod 保留宿主原有操作入口，并明确说明；不显示无响应的替代按钮。CanvasLayer 弹窗显式携带宿主字体，避免 iOS 中文缺失，并在换 UI 字体后刷新引用。

## 验证

- `Godot --headless --path . --script tests/gomoku.gd`（57 项）：确定性计时、断线暂停、重连恢复、双人同意与幂等性、旧轮次防护、横竖屏布局、真实 Viewport 指针输入、弹窗/设置字体与焦点、显式并发同意重试。
- `python3 tests/gomoku_network.py`：真实 TCP 双客户端，验证计时、断线/凭据重连、胜利弹窗、双方同意后新局和计时重置。
- `Godot --path . --script tests/capture_gomoku.gd`：桌面横屏、手机长短屏、中英文及结算截图。
- `python3 tests/gomoku_devices.py --device <UDID> --tv-connection <private.json>`：iPhone 模拟器发起、真实 TCL 电视加入。实际 adb 遥控器落子与再开一局，模拟器通过 Debug 提交操作；截图取自真实应用。`--manual-touch` 仅用于有人/可用原生自动化实际触摸时，此次模拟器原生控制通道启动失败，未使用该模式完成验证。Godot 全视口指针分发测试已通过。

设备截图与报告位于 `build/validation/gomoku-iphone-*.png`、`gomoku-tv-device-*.png`、`gomoku-devices.json`。既有联机、Debug、Mod 热更新、整套客户端 UI 热更新和 Release 隔离回归仍保留。

安卓手机基础包已成功覆盖安装到 0.1.8；手动解锁后，`tests/gomoku_android.py` 已通过实际 adb 触屏落子、电视遥控器落子、九手获胜弹窗、双方同意再开一局、同一会话内棋盘和计时重置，保留手机原昵称。报告为 `build/validation/gomoku-android.json`，截图为 `gomoku-android-*.png`。测试结束后两端返回大厅。电视普通 adb 覆盖安装仍被系统校验拒绝，0.1.8 APK 已放 `Download/novaparty-0.1.8-debug.apk`，需手动安装后才能由电视提供权威时钟。
