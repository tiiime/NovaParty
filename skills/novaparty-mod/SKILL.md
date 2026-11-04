---
name: novaparty-mod
description: 为 NovaParty 制作或修改可信 Godot 游戏 Mod，包含规则、玩家可见状态、交互界面和 ZIP 游戏包。适用于本仓库 SDK，不用于通用 Godot 游戏开发。
---

# NovaParty Mod 开发

先读取仓库的 [SDK 契约](../../docs/sdk.md)。涉及网络或重连时再读 [协议](../../docs/protocol.md)。参考 `mods/gomoku` 的公开棋盘与方向输入，或 `mods/hidden_cards` 的私有手牌和同时响应；后者不是标准扑克规则。

为新游戏建立 `mods/<id>/`，提供清单、规则和表现入口。所有运行依赖列入 `files`，保持游戏逻辑和资源在自己的命名空间，不要求修改平台核心代码来识别新游戏。默认会话为双人；需要随时加入/离开时，可显式声明 `session_mode: "drop_in"`，见 SDK 契约。不要把宽松版本语义用于普通棋牌。

规则继承 RefCounted，实现 `initial_state(seed_value)`、`apply(state, seat, action)` 和 `view_for(state, seat)`。所有规则数据放进 JSON 可表示的状态，随机行为基于输入种子。校验行动权限、参数类型与范围；网络整数可能以 float 解析。拒绝操作返回稳定错误码，不修改已提交状态。

私有信息在 `view_for` 返回前过滤，不能只在界面隐藏。不要在返回值、错误信息或资源日志中泄露对方手牌和未公开牌堆。房主进程掌握完整状态是当前信任模型。

表现入口继承 Control，提供 `command(action)` 信号与 `render(snapshot)`。只读取本玩家快照，通过信号提交输入；适配触屏和方向键/确认操作，不预加载平台业务类。可通过 `set_session_services` 使用公开表现服务，不读取 Session 的房间、规则或凭据内部字段。自绘控件同时处理触屏和鼠标时，忽略 `InputEvent.DEVICE_ID_EMULATION`，避免一次触摸产生两条命令；按钮操作引发界面重建时，延迟提交，避免在其输入回调中同步移除按钮。

为规则增加有意义的验证：合法对局、拒绝非法操作、终局、确定性，以及私有状态边界。使用当前 Godot 运行验证；未运行的步骤如实记录。打包命令：

```sh
python3 tools/pack_mod.py mods/<id> build/<id>.zip
```

需要验证新增包的动态加载时，可参照 `tests/load_pack.gd`，使用宿主中不存在的唯一 Mod ID。动态加载已在 macOS 和一台 Android 13 手机上验证；TCL Android 9 电视已验证内置 Mod、遥控器与联机，电视已验证网络可信包热更新，原生文件选择器导入尚未验证。iPhone 16 / iOS 18.5 模拟器已验证联机、网络热更新、回滚和重启恢复；真实 iPhone 与 iOS 原生文件选择器尚未验证。

需要让 AI 读取合法操作时，为规则实现可选的 `describe_actions(view, seat)`，返回 JSON Schema 和 `legal_actions`，仅根据传入的本玩家视图计算，不读取完整房间状态。参考两个内置规则的实现。

对 Debug 真机或客户端联调，先读 [网络 Debug 契约](../../docs/debug.md)。用 `tools/nvctl.py` 的连接配置文件认证，读取快照和动作描述后再提交；保留请求文件中的 ID、对局 ID、代次和预期版本，原样重试。等待最终 `action_result` 或查询 `game.result`，不要把 `queued` 当成落子成功。令牌配置与带私有手牌的诊断文件不要提交仓库。0.1.3 已支持网络表现更新，先读 [热更新契约](../../docs/hot-updates.md)。在清单中准确声明 `rules_files`，覆盖全部规则脚本和配置依赖；表现文件可独立更新。用 `pack_mod.py --hot` 生成新的 UUID 构建，再通过 `nvctl.py --activate mods.push` 上传切换。使用构建根相对资源路径，不能硬编码旧命名空间。实现可选的 `capture_view_state` / `restore_view_state` 并为焦点子节点命名。规则变化只能在大厅选为下一局版本，不能单端替换进行中的规则。

需要持续自动玩游戏时读取 [常驻玩家说明](../../docs/player.md)，使用 `tools/nvplayer.py` 的独立进程；一次 CLI 读取或聊天订阅不会自行唤醒模型。策略仅接收当前本地玩家过滤视图，持续遵守回执和上下文规则。0.1.4 提供远程创建、加入、离开和凭据重连，见 Debug 契约；默认保护已绑定的对局，切换新局应显式授权控制器采用新房间。

平台 0.1.5 对协议 2 连接可协商心跳，心跳和重连属于 Session，不放入 Mod 规则或动作列表，不增加规则版本。涉及失联恢复时读 [恢复契约](../../docs/recovery.md)，未确认动作保持 ID 与完整有效载荷，凭据重连不代表新对局。不要声称应用重启后可恢复进行中的房间。


涉及体感控制器时，读取 [跳绳说明](../../docs/jump-rope.md) 并参考 `mods/jump_rope`。运动检测留在本机，网络只提交带角色代次的幂等计数；检查真实传感器可用性并校准，不以模拟器/按钮输入冒充硬件动作验证。

涉及局域网发现、Mod 传递或连接二维码时，读取 [发现、传递与二维码契约](../../docs/lan-sharing.md)。普通 SDK 的 `ModSender` 和 `PeerMods` 可传包，不依赖 Debug。接收方先展示来源与下载确认，确认后才拉取；使用 `Loader.install_peer_zip` 验证并安装，不覆盖原有版本。扫码与发现加入复用同一下载确认流程，不能因二维码而跳过确认。

表现可实现 `set_session_services(services)`，调用 `services.get_join_info()` 或 `services.get_join_qr()` 获取公开连接信息和本地 Texture2D；实现 `controls_join_qr()` 后自行管理显示，否则平台提供初始等待二维码。不要把服务 Node 或 Texture 放进规则/快照，不把身份或恢复令牌编码进二维码。原生能力新增需要基础包支持，不能仅靠 Mod 热更新宣称可用。

制作固定人数的多方回合制游戏时，使用 0.1.14 新增的 `session_mode: "fixed"`，不要用 Drop-in 放宽 revision。读取 [固定多人契约](../../docs/sdk.md) 和 [UNO 示例](../../docs/uno.md)：规则管理等待/开始、参与座位、断线暂停和 `can_join`；公共屏幕必须在 `view_for` 层移除手牌，不只隐藏按钮。该能力需要新基座，不能只靠 Mod/UI 热更新。处理 JSON 座位或牌 ID 数组时，用数值比较适配 float，而不是类型敏感的 Array.has(int)。

涉及玩家名字、头像或身份强调色时，读 [用户配置 SDK](../../docs/user-profile.md)。0.1.15 提供 `snapshot.players[seat].profile` 和公开表现服务 `get_local_profile`、`get_player_profile`、`get_avatar_texture`、`get_profile_color`。使用稳定角色/配色 ID，旧快照走默认外观；不要读取完整本地 profile 或恢复令牌，不把纹理、颜色对象和头像偏好写入规则状态。
