# 常驻玩家（0.1.5，房间管理最低 0.1.4）

`tools/nvplayer.py` 是独立 Python 进程，通过认证 Debug SDK 控制一个客户端的本地座位。开始后持续接收网络事件，运行本地策略、提交并等待房主最终回执；聊天回复结束不影响它。它不是持续调用大模型的服务。目前策略为五子棋启发式和 SDK 合法操作适配器，不能承诺棋力。

## 使用

先按 [Debug 指南](debug.md) 获取私有连接文件。已有房间可直接附着：

```sh
python3 tools/nvplayer.py start --connection /tmp/novaparty-debug/tv.json --state /tmp/nv-tv-player.json --strategy gomoku --daemon
python3 tools/nvplayer.py status --state /tmp/nv-tv-player.json
python3 tools/nvplayer.py pause --state /tmp/nv-tv-player.json
python3 tools/nvplayer.py resume --state /tmp/nv-tv-player.json
python3 tools/nvplayer.py stop --state /tmp/nv-tv-player.json
```

省略 `--daemon` 在前台运行。`--once` 在本局结束且已确认最后回执后退出；默认结束后保持监听。`stop` 只停止控制器，不离开游戏房间。暂停前已发送的操作仍可能被房主接受。

0.1.4 客户端支持联网开房/加入：

```sh
python3 tools/nvplayer.py start --connection /tmp/iphone.json --state /tmp/iphone-player.json --create --game gomoku --port 27840 --nickname iPhone --daemon
python3 tools/nvplayer.py start --connection /tmp/desktop.json --state /tmp/desktop-player.json --join 192.0.2.10 --game gomoku --port 27840 --daemon
```

旧 0.1.3 客户端可以附着现有房间，但没有远程房间管理。平台 SDK 的变化需要一次基础包安装，不能通过仅替换 Mod 升级。

默认绑定第一次观察到的应用实例与对局；用户换房或应用重启后暂停行动。明确需要接管新房间时执行 `resume --adopt-room`；该操作丢弃旧局待确认请求并绑定新局。也可启动时显式选择 `--follow-rooms`。连接配置路径应保持不变，应用重启后将新的凭据写到原路径，控制器会重读。

`--strategy first_legal` 从 `game.describe_actions` 的合法列表选择第一项，可适配暗牌等提供该钩子的 Mod。它只使用本地玩家视图，不读取房主完整状态。新增策略在 `player_strategies.py` 中接收过滤快照、返回动作，由控制器负责上下文与回执。

## 恢复与边界

- 每个状态文件有独占文件锁，避免重复启动同一控制器。不同状态文件仍可能指向同一座位；房主版本检查会拒绝竞争操作。
- 每次提交前将原始 ID、动作、版本和上下文写入 0600 检查点。网络断开或进程重新启动后先查询原回执，结果未知时原样退避重试，每个本地 Session 至多发送三次后暂停，需显式 resume；凭据重连创建新 Session 时重置发送预算，始终保留原动作 ID。不能把一次不确定提交重新生成为另一个动作。
- 持续推送事件，闲时每 3 秒同步当前快照。Debug 连接自动退避重连；已加入且具有内存恢复凭据的参与者，在游戏 TCP 断开时可调用 `room.reconnect`。0.1.5 对协商了心跳的对端也能识别静默丢包并恢复，见 [联机恢复](recovery.md)。没有房主迁移或应用进程重启后的对局恢复。
- 状态/日志在指定路径及 `.log`、控制命令在 `.control`，全部为本机文件。状态不存认证令牌或完整快照，动作本身仍可能包含自己选择的牌，不提交仓库。
- `latency_ms` 衡量策略计算开始到最终回执，不包括设定的 think delay；是最近一次操作值。默认 think delay 30 毫秒。操作回执缓存、去重边界见 Debug 契约。

```sh
python3 tests/player_integration.py
```

实际双 Godot 客户端验证：完整 225 手五子棋、暗牌 6 次提交、暂停恢复、单实例锁、SIGKILL 后恢复、房间变化保护，以及代理转发落子后丢掉回执并断开连接，恢复后只确认一次落子。五子棋策略检查直接获胜、强制防守及双三预防。
