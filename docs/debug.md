# 网络 Debug（0.1.4 / D1 + D2 + 房间管理）

`Android Debug`、`iOS Simulator Debug` 和显式开启开发特性的桌面 Debug 构建启用。连接配置写入私有目录，界面不展示开发地址；默认选第一个 192.168.* / 10.* IPv4，找不到时使用 127.0.0.1。服务端口 27841，与游戏端口 27840 独立。网络切换后当前版本需要重启应用重新选址。当前只有 `play` 模式，读取本机玩家可见状态，不提供隐藏牌或任意表达式执行；可信 Mod 包的热更新见 [D2 指南](hot-updates.md)。

## 首次连接

客户端 UI 热更新需要覆盖安装一次 `build/android/novaparty-0.1.7-debug.apk`；0.1.3–0.1.6 的基础包只有 Mod 热更新。0.1.7 起可在安装后直接网络更新 UI。安装和启动会中断旧进程中的对局，请在旧对局结束后更新。

先按[本地开发配置](development.md)填写 `.env`。Python 工具会自动读取；下面的 shell 命令需先加载自己维护的 `.env`：

```sh
set -a; . ./.env; set +a
mkdir -p /tmp/novaparty-debug
(umask 077; "${ADB:-adb}" -P "$TV_ADB_PORT" -s "$TV_ADB_SERIAL" exec-out run-as org.novaparty.prototype cat files/debug/connection.json > /tmp/novaparty-debug/tv.json)
python3 tools/nvctl.py --connection /tmp/novaparty-debug/tv.json device.info
python3 tools/nvctl.py --connection /tmp/novaparty-debug/tv.json game.snapshot
```

配置包含 `host`、`port`、`token`、`app_instance_id`，不要提交到仓库。令牌每次启动生成新的 32 字节随机值。之后 CLI 直接访问该地址，无需持续 adb。传输为局域网明文 TCP，目前没有 TLS。Android 私有目录中的连接文件路径由 Godot 的 `user://debug/connection.json` 映射而来；已在 Android 13 手机通过此方式获取凭据并连接；TCL Android 9 电视也已通过相同流程与 LAN 热更新验证。

macOS 开发运行：

```sh
GODOT_EDITOR_CUSTOM_FEATURES=novaparty_debug Godot --path . -- --debug-bind=127.0.0.1 --debug-port=27841 --debug-connection=/tmp/nv-local.json
python3 tools/nvctl.py --connection /tmp/nv-local.json game.snapshot
```

`--debug-bind`、`--debug-port`、`--debug-connection` 只在 Debug 服务已启用时生效。普通编辑器启动不启用服务。文件在 Unix 开发机上设为 0600。

## 人和 AI 的操作流程

1. `game.snapshot` 获取 `game_session_id`、`state_epoch`、`revision`、`seat` 和 `view`；无已就绪局面时返回 `in_room: false`。
2. `game.describe_actions` 返回 JSON Schema、本机玩家当前合法行动列表及提交上下文。
3. 为一次操作生成唯一 `request_id`，将完整请求保存到文件；`expected_revision` 使用刚读取的版本。
4. 用 `game.submit --wait` 等待最终结果。`queued: true` 只表示送入 Session，不能当作接受落子。
5. 网络超时先查询 `game.result`；需要重试时发送原文件，保持所有字段原样。版本过期后读取新局面，创建新的请求 ID。

`/tmp/move.json` 示例（实际上下文从快照获得）：

```json
{"game_session_id":"从快照复制","state_epoch":0,"expected_revision":5,"request_id":"tv-move-006","action":{"type":"place","x":7,"y":6}}
```

```sh
python3 tools/nvctl.py --connection /tmp/novaparty-debug/tv.json --wait game.submit @/tmp/move.json
python3 tools/nvctl.py --connection /tmp/novaparty-debug/tv.json game.result '{"game_session_id":"从快照复制","request_id":"tv-move-006"}'
python3 tools/nvctl.py --connection /tmp/novaparty-debug/tv.json --watch events.subscribe
```

`--watch` 持续输出 JSON 行；空闲达到 `--timeout` 会结束，可增加超时并记录游标重连。命令行错误写入 stderr，退出码 1；规则拒绝是成功取得的回执，stdout 中 `accepted: false`，调用方应检查该字段。

## RPC 契约

每行一个 UTF-8 JSON 对象，最大帧 64 KiB。支持 JSON-RPC 2.0 的单请求/响应子集，必须包含字符串或数值 `id`，不支持批量及无 ID 通知请求。认证后服务端可主动推送 `event` 通知。

```json
{"jsonrpc":"2.0","id":1,"method":"auth","params":{"token":"配置文件中的令牌"}}
```

认证失败断开连接；未认证连接 5 秒超时。复用 Wire 的 16 个连接、256 KiB 输出队列和 64 KiB 分帧上限，每连接每秒最多 60 次请求；慢客户端超出队列上限会断开。客户端重连后需重新认证。

| 方法 | 参数 | 结果 |
|---|---|---|
| `device.info` | `{}` | 实例 ID、系统、型号、版本、模式 |
| `debug.capabilities` | `{}` | 协议 1、方法列表、容量、`hot_update` 能力对象（上传/表现更新可用，局中规则升级不可用） |
| `room.status` | `{}` | 快照元信息与玩家连接信息，不包含 `view` |
| `room.create` / `room.join` | 生命周期上下文、`game_id`、可选 `port` / `nickname`；加入另需 IP `address` | 发起创建/连接，不代表加入握手已完成 |
| `room.leave` / `room.reconnect` | 生命周期上下文，另含 `local_session_id` | 离开当前房间 / 使用当前内存凭据重连参与者 |
| `game.snapshot` | `{}` | 本机玩家经过 `view_for` 过滤的快照，含 `host` / `connected` |
| `game.describe_actions` | `{}` | 可选规则钩子的 Schema、`legal_actions`、`context`；未实现钩子返回 `supported: false` |
| `game.submit` | 上面的完整操作请求 | 排队结果；通过事件或查询获取最终回执 |
| `game.result` | `game_session_id`, `request_id` | 最近 256 个本机操作结果；未收到或已淘汰返回 `status: unknown` |
| `events.subscribe` | 可选 `after_seq`, `app_instance_id` | 当前快照、当前序号、是否需要重同步；随后推送历史与新事件 |
| `events.unsubscribe` | `{}` | 停止此连接推送 |

事件是 `{"jsonrpc":"2.0","method":"event","params":{"seq":12,"app_instance_id":"...","kind":"state","data":{...}}}`。类型为 `state`、`action_result`、`notice`、`presentation_changed`，以及携带当前过滤快照的 `connection`。通知文本仅用于展示，不应解析中文文本判断逻辑。

事件序号独立于对局版本；连接变化或重复回执也可以产生事件。保存最近 128 条；游标过旧、超过当前序号或来自另一个进程时返回 `resync_required: true`，以返回的快照与序号重建本地状态。正常恢复时返回当前快照，再按序重放 `after_seq` 之后的事件；按 `seq` 丢弃重复事件，注意历史事件的局面可能早于该快照。

请求 ID 必须非空且不超过 128 字符；版本和代次须为整数。旧对局/旧代次在 Debug 接口被拒绝，房主也会校验携带的上下文。当前代次固定为 0，尚无规则升级。房间保留至多 10000 条操作去重记录，此限制独立于 Debug 的 256 条查询缓存；查询淘汰后仍可原样重试，由房主返回原有回执。旧房主没有共享对局 ID，无法使用新接口提交。

## Release 与验证

`Android Debug` 带 `novaparty_debug` 导出特性；应用与服务均检查 `OS.is_debug_build()` 和该特性。`Android Release` 不带特性，并排除整个 `debug/`。Release 预设默认不签名，正式分发前需要配置正式签名。

```sh
python3 tests/integration.py
python3 tests/debug_integration.py
# macOS：实际 Debug/Release 模板与导出资源的四种组合
python3 tests/debug_exports.py
```

第二项运行真实 Godot 房主和加入方，验证认证、私有手牌与合法操作过滤、双方回执、重复请求、过期保护、订阅回放/溢出、CLI 读取及 `--wait` 完成两种整局。0.1.3 已在 Android 13 手机上通过 LAN 热更新与整局验证。TCL Android 9 电视也已通过遥控器、热更新、完整对局及重启恢复回归。D2 使用方式见 [热更新指南](hot-updates.md)，D3 局中规则升级仍见 [设计草案](debug-design.md)。

## 0.1.4 房间生命周期

快照和 `room.status` 在大厅也返回 `app_instance_id`、`room_generation`、`local_session_id`；存在 Session 时返回 `session_state` 和 `connection_error`。状态包括 `lobby`、`hosting`、`connecting`、`handshaking`、`connected`、`failed`、`rejected`、`disconnected`。`in_room: false` 也可能表示加入尚未完成，通过结构化状态区分。

生命周期命令需保存唯一 `request_id`、当前 `app_instance_id` 和 `room_generation`，离开/重连另须本地 Session ID。相同请求返回缓存结果，复用 ID 改参数拒绝；保留最近 128 项（包括错误）。缓存淘汰后代次检查仍阻止旧请求改变新房间。已有 Session 时创建/加入返回 `room_busy`，不得静默替换对局。`room.reconnect` 仅支持已有内存凭据的断线参与者，不支持房主恢复。

`nvctl.py` 对上述方法自动补齐缺失上下文，显式传入的旧字段不会被覆盖。对不确定结果的重试应保存完整 JSON，原样调用；不要依赖重新补上下文。开房示例：

```sh
python3 tools/nvctl.py --connection /tmp/nv-local.json room.create '{"game_id":"gomoku","port":27840}'
python3 tools/nvctl.py --connection /tmp/nv-local.json room.leave
```

常驻策略控制器及进程恢复流程见 [常驻玩家](player.md)，模拟器凭据获取见 [iOS 指南](ios.md)。0.1.4 接口需要新的基础客户端，局中 Mod 表现更新不会升级平台 SDK。

0.1.5 Session 可协商心跳，`connection_error` 可返回 `heartbeat_timeout` 或 `handshake_timeout`。普通客户端手动重连、常驻玩家自动重连及未确认操作的精确重试边界见 [联机恢复](recovery.md)。

## 0.1.6 UI 只读状态

`ui.status`（无需参数）读取真实首页 / 设置 / 游戏页面、语言、减少动态效果标记、动画时间、轨道位置和本地化标题。`animation_processing` 是首页节点的帧处理标记；减少动态效果时该节点仍可更新时钟，但不会推进 `motion_time`。仅 Debug 提供，不含任意 UI 执行或设置修改接口，详见 [UI 验证](ui.md)。

## 客户端 UI 更新

0.1.7 的稳定宿主支持 `ui.updates`、`ui.upload.begin/chunk/abort/commit`、`ui.activate`、`ui.rollback`；`ui.status` 新增 UI 构建标识。`debug.capabilities.hot_update.client_ui` 表示是否支持，旧基础包需要覆盖安装一次。操作方式与生命周期见 [UI 热更新](client-ui-updates.md)。


## Android APK 更新（0.1.12）

Android Debug 的连接配置增加 `apk_http`，提供认证 HTTP 上传、状态查询与系统安装入口；`debug.capabilities` 也返回该字段。默认端口 27842，沿用同一 Debug token。用 `tools/apkctl.py` 上传完整基础包，详见 [APK 网络更新](apk-updates.md)。非 Android 或监听失败时该字段为空，Release 不包含原生实现或安装权限。
