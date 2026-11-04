# SDK 与 Mod 契约 v0.1

这是验证用接口，尚未承诺稳定。支持 Godot 4.6.1、房主权威、可信 GDScript Mod；默认双人，0.1.9 增加可选 Drop-in 会话。

## 包结构

```text
mods/<id>/
  manifest.json
  rules.gd
  view.gd
```

清单示例：

```json
{
  "id": "my_game",
  "name": "我的游戏",
  "version": "0.1.0",
  "sdk": 1,
  "rules": "rules.gd",
  "view": "view.gd",
  "files": ["rules.gd", "view.gd"],
  "players": {"min": 2, "max": 2},
  "inputs": ["touch", "directional"]
}
```

ID 使用 ASCII 字母、数字及下划线，不能以数字开头。普通目录包使用 `res://mods/<id>/`，网络共享/热更新版本包使用不可变 `res://mod_versions/<id>/<build_id>/`。全部运行依赖必须列入 `files`；不能依赖宿主业务代码、其他 Mod 或未列入清单的资源。外部 ZIP 不允许包含清单之外的文件，不覆盖现有 Mod。暂不使用全局 `class_name` 注册跨包类型。

兼容指纹为 SHA-256：清单原始字节的 SHA-256，加换行，再加按文件名字典序排列的 `相对路径:文件SHA-256`，各项以换行连接，再计算整体 SHA-256。包括清单格式差异在内的内容变化都会改变指纹。协议 1 要求完整指纹相同；协议 2 按规则指纹判断兼容，可允许表现不同，详见后续热更新章节。

ZIP 挂载不是代码沙箱。只安装可信包。目录包校验在规则实例化前执行；契约运行错误仍可能影响宿主，后续需要错误隔离策略。

## 规则接口

`rules.gd` 继承 `RefCounted`，实现：

```gdscript
func initial_state(seed_value: int) -> Dictionary
func apply(state: Dictionary, seat: int, action: Dictionary) -> Dictionary
func view_for(state: Dictionary, seat: int) -> Dictionary
```

- `initial_state` 返回完整权威状态。默认双人座位为 `0` 和 `1`；Drop-in 座位范围为 `0..players.max-1`。随机过程使用输入种子，不能读取系统时间或使用未记录的全局随机源。
- `apply` 验证规则，成功返回 `{"state": 新状态}`，失败返回 `{"error": "稳定错误码"}`。房主以深拷贝传入状态，仅成功结果会被提交。不要通过其他对象保存隐式规则状态。
- `view_for` 返回指定座位可见的数据。不得包含对方手牌、未公开牌堆、恢复凭据或其他内部信息。

数据使用 JSON 可表示的 Dictionary、Array、String、数值、bool 和 null。JSON 解析后的数值可能是浮点数；整数参数先检查数值类型、整数性及范围，再转换。不要把 Node、Resource、Vector 或 Callable 放进状态或消息。

并行响应由 Mod 自己在权威状态记录响应窗口、提交情况和结算条件。SDK 的全局版本序列保证操作依次生效；它不会自动解释吃碰杠优先级或计时。旧版本操作被拒绝，客户端获得新快照后重新提交。完整响应窗口与超时 API 尚待麻将原型验证。

## 表现接口

`view.gd` 继承 `Control` 或其子类，提供：

```gdscript
signal command(action: Dictionary)
func render(snapshot: Dictionary) -> void
```

平台实例化界面并加入场景树后调用 `render`。snapshot 包含：

- `seat`：本机座位。
- `revision`：权威状态版本。
- `players`：昵称和在线标记数组，不包含玩家凭据。
- `view`：规则为本玩家生成的可见状态。

用户输入通过 `command.emit(...)` 提交，界面不能直接修改权威状态。平台仅连接该信号与 Session，不分支判断具体游戏。触屏、遥控器焦点和确认操作由 Mod 实现；五子棋提供方向输入示例，暗牌示例使用可聚焦按钮。

## 平台接口

`Session` 是 Godot Node，加入场景树后调用：

```gdscript
create(mod_info, rules, profile, port) -> Error
join(mod_info, profile, address, port, resume_token = "") -> Error
submit(action) -> void
```

`profile` 为 `{"id": 稳定本地ID, "nickname": 昵称}`。通过 `updated(snapshot)` 获取状态，通过 `notice(message)` 获取操作拒绝或连接错误。创建或连接的同步返回值为 OK，不表示异步握手已经完成。

`ModLoader.inspect(root)` 验证清单并计算指纹；`rules(info)` 创建规则实例；`mount_zip(path)` 挂载独立游戏包，返回资源根目录。`install_zip(source)` 从文件路径或 Android 内容 URI 复制最多 16 MB 的包到私有目录，挂载后返回游戏信息；`installed_packages()` 列出供下次启动挂载的包。包格式尚未固定为最终移动端方案。

## 当前限制

默认双人游戏在双方在线时才接受操作，离线保留座位和恢复凭据；重连与五子棋重赛见后续章节。Drop-in 模式可独立继续并复用离线槽位。当前尚无通用准备阶段、观战、存档和主机迁移。

## Debug 操作描述与结果（0.1.2）

规则可实现 `describe_actions(view: Dictionary, seat: int) -> Dictionary`，返回 `schema`（JSON Schema）与 `legal_actions`。输入只包含本玩家经过过滤的 `view`；不要读取全局状态补充隐藏信息。未实现此钩子仍可正常游戏，Debug 返回 `supported: false`。内置五子棋与暗牌示例已经实现。

Session 的 `action_result(result)` 对房主与加入方均发出最终回执。普通界面仍使用 `submit(action)` 自动生成请求 ID；工具使用 `submit_request(request)` 原样保留请求 ID、预期版本与可选对局上下文。工具必须检查 `accepted`，不能将排队成功视为规则接受。

快照增加共享 `game_session_id` 与固定为 0 的 `state_epoch`，保持协议 1 的旧字段兼容。改变内置规则脚本会改变 Mod 指纹，两端需使用相同包。完整网络工具契约见 [Debug 指南](debug.md)。

## D2 构建与表现更新（0.1.3）

清单可增加 `rules_files`，包含规则入口及所有规则依赖；未声明时将全部 `files` 保守作为规则依赖。网络构建必须声明它，使用 `pack_mod.py --hot` 生成新的 `mod_versions/<id>/<build_id>` 命名空间。规则指纹与表现指纹分开，协议 2 按规则指纹协商；协议 1 仍要求完整原始指纹相同。

表现可提供 `capture_view_state() -> Dictionary` 和 `restore_view_state(state)` 保存局部 UI 状态，使用稳定子节点名称恢复焦点。更新只替换表现，不替换活跃 Session 或规则对象。规则变更在大厅选用、下一局生效；资源用自身构建根相对寻址。具体上传、激活、回退与限制见 [热更新契约](hot-updates.md)。

## UI 设计依据

客户端与 Mod 的界面开发参照 [星星大作战 Design Cheat Sheet](design/README.md)。UNO 游戏内使用独立的 [UNO UI 规范](design/uno/README.md)，大厅不受影响。平台统一大厅与房间控件，游戏内部美术可自由；共同遵守可读性、电视焦点、输入反馈、真实连接状态及安全区域要求。当前已实现自动发现、扫码与缺包下载；接口与验证边界见 [局域网共享](lan-sharing.md)，状态应展示真实搜索和下载结果。

0.1.6 的 i18n：Mod 显示文案随表现包携带，参考两个内置游戏的 `locale-*.json` 与 `_t()`。目录列入 `files`，不列入 `rules_files`。使用当前构建根的相对路径，避免热更新命名空间失效；未知语言回退英文，不依赖平台替 Mod 注册翻译。外部游戏名称支持清单中的 `localized_names`，仅用于显示且不参与规则指纹。详见 [UI 与 i18n](ui.md)。


## 五子棋计时与平台 UI（0.1.8）

可选规则方法 `clock_context(state)` 返回确定性的 `{seat: -1|0|1, round: int}`，由 SDK 发起端统一累计时间。时钟通过快照顶层 `clock` 字段同步，不参与 revision；规则不能读取墙上时间。两人到齐才运行，断线暂停、终局停止、round 改变归零。没有该钩子的游戏不增加周期快照。公开玩家增加不含凭据的短 `code`。

可选表现扩展包括 `wants_fullscreen()`、`platform_action` 信号、`set_platform_state()`、`focus_default()`、`restore_platform_focus()`、`handle_platform_back()` 和 `on_command_notice()`。扩展用于把设置、重连、退出交给宿主，避免 Mod 依赖业务场景路径。具体语义与兼容边界见 [五子棋 0.2.0](gomoku.md)。

## Drop-in 会话（0.1.9）

清单可显式声明 `session_mode: "drop_in"`，`players.min: 1` 与整数 `players.max`（2–8）。其余 Mod 保持双人门槛和严格 revision。Drop-in 可以在加入/离开期间继续操作，并复用离线槽位；规则可实现纯函数 `presence_changed(state, seat, connected) -> Dictionary`，其结果在 SDK 中提交并递增 revision。

此模式允许 `0 <= expected_revision <= revision` 的命令在当前权威状态重新验证，适用于每个控制器独立的幂等累计动作。规则必须自行验证角色代次与单调序列，不能依赖宽松版本控制保护旧动作；参考 [跳绳](jump-rope.md)。回执缓存限 512 项，更换槽位身份会清理旧回执。请勿为传统回合制游戏开启此模式。

可选表现 `set_platform_state` 现在还提供 `reduce_motion` 和 `input_paused`，后者在设置/离开确认弹窗打开时为 true，体感游戏需暂停计数。旧表现可忽略新增字段。

## 局域网传递与二维码（0.1.11）

Session 自动提供 mDNS 游戏发布及普通 SDK Mod 共享。接收端 `PeerMods` 的目录查询不下载包；用户确认后才 `confirm_download()`，校验后由 `Loader.install_peer_zip` 安装。独立 `ModSender` 可在没有游戏 Session 时提供包。完整接口和边界见 [局域网发现、Mod 传递与二维码](lan-sharing.md)。

可选 Mod 表现方法 `set_session_services(session)` 可访问 `get_join_info(address_override = "")` 与 `get_join_qr(address_override = "")`。`controls_join_qr()` 返回 true 后，由 Mod 自行控制显示；否则平台在初次等待玩家加入时显示默认二维码。返回的 Texture2D 仅用于本地表现，不能放进规则或快照。扫码与手动加入统一走目录检查、缺失 Mod 下载确认及带会话 ID 的握手。

## 固定多人会话（0.1.14）

新增显式 `session_mode: "fixed"`，清单使用 `players.min: 2`，整数 `players.max` 为 2–8。默认双人和 Drop-in 语义不变，SDK 清单版本仍为 1；旧客户端因不支持该人数/模式而拒绝包，需要更新基座。

- 固定会话始终使用严格 revision、原座位凭据重连和不复用座位的身份策略，不放宽为 Drop-in 的旧版本命令。
- 规则实现纯函数 `presence_changed(state, seat, connected)`；首次创建会调用座位 0 的在线通知，此后成员加入/断线/重连时调用并递增 revision。
- 可实现 `can_join(state) -> bool` 控制新身份加入。既有身份的凭据重连在此门槛前验证，不会因本局锁定而被拒绝。返回 false 时暂停 mDNS 发布，恢复 true 时重新发布。
- SDK 不替 Mod 决定准备阶段或暂停策略。固定模式允许单个发起者提交等待页设置；Mod 必须验证开始时的实际参与人数，记录本局参与座位，并自行拒绝断线期间的游戏操作。
- 坐席不一定等于参与发牌的人。UNO 的公共屏幕 + 最多 6 玩家使用 7 个坐席，屏幕不进入参与者列表、手牌和重赛投票；其他游戏可采用不同角色。
- 合法操作描述也必须适配 JSON float 数字，不能用类型敏感的 `Array.has(int)` 检查从网络读取的 float 座位数组。参考 `mods/uno/cards.gd`。

示例见 [UNO](uno.md)。当前计时钩子仍只支持双人累计计时，UNO 没有使用它。`debug.capabilities.session_modes` 可检查基座是否声明 `fixed` 支持；这只是开发诊断接口，普通 SDK 游戏不依赖 Debug。

## 用户配置与角色表现（0.1.15）

平台提供用户信息编辑与六种动物角色、四种配色、个人主题色。Mod 从 `snapshot.players[seat].profile` 或表现服务 `get_local_profile()` / `get_player_profile(seat)` 获取公开配置，通过 `get_avatar_texture(profile)` / `get_profile_color(profile)` 展示。完整数据、兼容性与示例见 [用户配置 SDK](user-profile.md)。这是新增基座能力，0.1.14 需升级；头像不进入规则与私有身份信息。
