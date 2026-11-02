# 安卓电视验证

日期：2026-11-01。设备：TCL ak30a5，Android 9 / API 28，32 位 ARM（armeabi-v7a），1920×1080，Mali-G31。

## 安装

通用 APK 同时包含 ARM32 和 ARM64。此电视通过 adb 安装返回 `INSTALL_FAILED_VERIFICATION_FAILURE`；用户通过 USB 安装后成功启动。系统安装校验保持原值，没有关闭校验或修改厂商安装策略。

0.1.1 更新包：`build/android/novaparty-0.1.1-debug.apk`，versionCode 为 2。按用户选择通过 USB 覆盖安装。

## 已实测

- 横屏采用 1280×720 基准，棋盘完整显示在 1920×1080 画面内。
- 遥控器可选择游戏、创建房间、移动棋盘选中格并确认落子。
- 电视作为房主，手机通过 Wi-Fi 直接加入并交替落子，完成五子棋；电视终局为版本 9，五连胜判定正确。
- 电视作为参与者，输入电脑 Wi-Fi 地址并加入，通过遥控器完成另一局五子棋；电脑记录版本 0→9，逐手推进且无重复操作。
- 电视与电脑完成暗牌示例三轮，版本 0→6。遥控器可左右选牌、确认提交，并在揭牌及界面刷新后继续操作。
- 电视的 Godot 启动和上述对局日志没有脚本或节点生命周期错误。

电视遥控器输入通过 adb 注入 Android DPAD 方向及确认键验证。地址输入还使用了 adb 的键盘文本注入，未证明该电视的屏幕键盘支持完整的遥控器文字输入。

## 返回键修复与验证边界

已安装的 0.1.0 中，Android 返回键触发默认退出，未能留在大厅。这是测试发现的问题，不能记录为返回通过。

0.1.1 同时关闭 `quit_on_go_back`，并通过根窗口 `go_back_requested` 信号处理返回大厅。桌面行为检查模拟根窗口的返回通知和信号，验证会话清理、显示大厅和恢复焦点；还验证了横竖屏切换与选牌焦点恢复，共 7 项通过。**电视需要 USB 更新到 0.1.1 后，再验证真实返回键。**

参考：[Godot 根窗口返回信号](https://docs.godotengine.org/en/4.6/classes/class_window.html#class-window-signal-go-back-requested)、[Android 默认退出设置](https://docs.godotengine.org/en/4.6/tutorials/inputs/handling_quit_requests.html)。

## 后续

- 更新后回归真实遥控器返回、重新开房和再次加入。
- 验证电视端系统文件选择器及外部 Mod 导入；本轮只验证内置游戏。
- 配置标准 Android TV 的 Leanback 入口与横幅；当前是普通 Android 启动入口，在该 TCL 设备已实际启动。
- 验证手柄、待机唤醒及长时间后台。

## 证据

位于 `build/android/evidence/`：

- `tv-host-gomoku-finished.png`：电视与手机对局终局。
- `phone-tv-first-move.png`：手机收到电视第一手棋。
- `tv-as-client-finished.png`、`tv-client-host.log`：电视作为加入方完成对局。
- `tv-cards-finished.png`、`tv-cards-peer.log`：遥控器完成暗牌三轮。

后续手机截图曾被系统界面遮挡，因此没有将其作为匹配终局的证据。

## 0.1.3 热更新回归（2026-11-01）

用户通过 USB 安装并启动后，使用独立 adb 服务端口 5038 读取私有连接配置，经局域网 27841 完成鉴权与能力检查。遥控器方向键将光标移动至 (0,0)，确认键完成第一手；真实 Godot 对手响应后，在含两颗棋子的版本 2 局面上传并激活蓝色资源构建。

验证通过：Android PID 不变，对局 ID、代次、版本、座位、玩家、棋盘、光标和焦点均保持；随后回退/再次激活并完成九手整局。强制停止并重启后，新令牌及保存构建恢复，重新创建房间确认蓝色资源可用，再回退到内置配色，通过遥控返回键退出房间。测试后电视停在大厅。未重新安装 APK。

复现命令（需先在电视创建全新五子棋房间，并按[本地开发配置](development.md)填写 `.env`）：

```sh
set -a; . ./.env; set +a
python3 tests/android_hot.py --connection /tmp/novaparty-tv.connection.json --serial "$TV_ADB_SERIAL" --adb-server-port "$TV_ADB_PORT" --artifact-prefix tv --remote-first-move --restart --create-tap 85,480
```

截图：`build/validation/tv-hot-update.png`。此次覆盖网络可信包热更新，不代表已经验证电视原生文件选择器导入。
