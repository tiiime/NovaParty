# 通信协议 v0.2

当前客户端使用协议版本 `2`，房主同时支持协议 `1` 的完整包指纹校验分支。当前实现是可靠有序的 TCP 流，UTF-8 JSON 对象加单个换行分帧，不使用对象反序列化。房主监听默认端口 `27840`，参与者主动连接。未来蓝牙适配应保留相同上层消息语义，不要求复用 TCP 分帧。

## 限制

每个发送帧不超过 65,536 字节（含换行），发送队列上限 262,144 字节；接收端按字节缓存处理半帧和粘包。无效 JSON、非对象消息和超限输入断开连接。每帧最多处理每连接 64 条消息。最大 16 个运输连接，握手超时 10 秒；游戏只有两个座位。

0.1.5 对支持的协议 2 对端协商 `heartbeat_v1`，及时识别静默丢包；未协商的旧对端保持原 TCP 行为。对局通道当前无加密、自动发现或应用层速率限制；独立的 Debug 通道另有限流。后台生命周期和网络切换仍需单独处理。

## 握手

客户端发送：

```json
{"type":"hello","protocol":2,"capabilities":["heartbeat_v1"],"rules_fingerprint":"<规则指纹>","fingerprint":"<完整包指纹>","player_id":"<本地ID>","nickname":"小明","resume_token":""}
```

协议 2 校验规则指纹，允许双方表现构建不同；协议 1 继续校验完整包指纹。成功返回协商后的协议及能力：

```json
{"type":"welcome","protocol":2,"seat":1,"resume_token":"<32随机字节的十六进制字符串>","rules_fingerprint":"<规则指纹>","capabilities":["presentation_versions","heartbeat_v1"]}
```

随后发送本玩家快照。失败返回 `{"type":"error","code":"..."}`；常见错误为 `incompatible`、`invalid_identity`、`invalid_resume_token`、`already_connected`、`room_full`。

房主在连接上绑定座位，不接受操作消息自报座位。玩家 ID 只是身份索引；已有身份必须提供恢复凭据且原连接已经离线，才能重新绑定座位。凭据不会出现在公共玩家列表中。当前凭据固定到该房间生命周期，客户端仅在内存中保存。

## 操作与结果

```json
{"type":"command","request_id":"<本座位唯一请求ID>","expected_revision":0,"action":{"type":"place","x":7,"y":7}}
```

```json
{"type":"receipt","request_id":"<同一ID>","accepted":true,"code":"","revision":1}
```

房主先按座位和请求 ID 去重，再检查预期版本，最后调用 Mod。相同 ID、相同有效载荷重试返回原结果，不重复执行；相同 ID、不同载荷返回 `request_id_reused`。失败结果同样被记录，因此修改操作或重新尝试必须生成新 ID。

工具操作可额外携带 `game_session_id` 和 `state_epoch`，房主会校验它们；当前代次固定为 0。Session 保留调用方的请求 ID 与预期版本，并向房主和加入方一致发出 `action_result`。

常见拒绝原因：`stale_session`、`stale_epoch`、`waiting_for_players`、`stale_revision`、`invalid_action`，以及 Mod 的规则错误码。每房间最多保留 10,000 个请求记录，达到上限拒绝新请求，不淘汰旧的去重记录。该上限适用于当前短对局原型，正式版需结合对局边界设计。

每次处理操作后发送各接收者自己的完整快照；版本仅在规则成功推进后增加。收据的版本是该请求原先处理时的版本，重试后应以随后收到的最新快照为准。原型客户端尚未自动重发未确认请求。

## 快照与私有状态

```json
{"type":"snapshot","game_session_id":"<房间随机ID>","state_epoch":0,"revision":1,"seat":1,"players":[{"nickname":"房主","connected":true},{"nickname":"小明","connected":true}],"view":{"hand":[3,8,21]}}
```

`view` 必须由规则在发送前按接收座位生成。规则完整状态不直接进入网络广播。重连使用相同过滤后的完整快照。房主客户端的界面也使用座位 0 的过滤视图，但房主规则进程仍掌握完整状态。

离线状态通过快照更新，不增加规则版本。首版没有客户端中途退出后让新身份接管座位的机制，也没有房主迁移。

## 参考

- [Godot TCP 客户端 API](https://docs.godotengine.org/en/4.6/classes/class_streampeertcp.html)
- [Godot 游戏包加载说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html)

本文的帧格式、身份模型和去重规则是 NovaParty 自身设计。

规则与表现的指纹算法、版本命名空间和局中表现替换见 [D2 热更新契约](hot-updates.md)。

## 可选健康检查

`heartbeat_v1` 只在协议 2 的 hello 和 welcome 均声明后启用，未声明时不能因缺少 pong 而断开。每 2 秒发起一个随机 nonce 的 ping，匹配的 pong 确认往返路径；8 秒未确认关闭连接。参与者收到 welcome 前的握手期限为 10 秒。完整消息与重试边界见 [联机恢复](recovery.md)。心跳不进入规则、快照或对局版本。
