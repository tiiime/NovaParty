# 用户配置与 Mod 表现服务 · 0.1.15

0.1.15 新增平台用户配置 UI、公共外观同步与系统设备名读取。新增 SDK 和 Android/Apple 桥接代码需要新基础包；0.1.14 不能仅通过客户端 UI/Mod 热更新获得本能力。后续仅改配置页布局与控件样式可以走客户端 UI 热更新；共享角色资源、SDK、原生桥接仍随基础包升级。

首页「用户信息」编辑名字、六种动物角色、四种角色配色和六种个人主题色，详见 [UI cheat sheet](design/profile/README.md)。昵称留空时使用设备名（Android 系统设备名 / Apple 系统公开名称 / Windows 主机名），读不到时回退型号或系统名。iOS 可能只返回系统允许公开的通用名称，不要求额外权限来读取私人设备名。

## 公共数据

`snapshot.players[seat].profile` 是经过白名单归一化的公共对象：

```json
{
  "schema": 1,
  "display_name": "客厅电视",
  "avatar": {"character": "fox", "palette": "mint"},
  "theme_color": "sky"
}
```

角色与配色 ID 见 cheat sheet；主题色 ID 为 `sky/violet/rose/mint/orange/gold`。未知角色、配色、主题色和缺失配置回退默认值；远端名字清理控制字符并限制为 32 字符。没有网络图片 URL、任意 SVG 或远端资源路径。`players[].nickname` 保留并与 `profile.display_name` 一致，原有 Mod 无需迁移。

只传播这些公共字段。完整本地随机 ID、恢复令牌、地址历史、语言、声音及减少动态设置不会放入 profile。昵称可以含用户主动选择的设备名。身份鉴别继续使用原有本地 ID 和恢复令牌，修改外观不改变身份或座位。

## Mod 使用

Mod 通过已有 `set_session_services(services)` 获得表现服务。不要访问 Session 的 identity/room 或其他内部字段：

```gdscript
var services
func set_session_services(value) -> void:
    services = value

func render(snapshot: Dictionary) -> void:
    var local: Dictionary = services.get_local_profile()
    var player: Dictionary = services.get_player_profile(int(snapshot.seat))
    $Name.text = player.display_name
    $Avatar.texture = services.get_avatar_texture(player)
    $Name.add_theme_color_override("font_color", services.get_profile_color(player))
```

| 接口 | 返回 |
| --- | --- |
| `get_local_profile()` | 本机公开配置副本；无需读取完整本地设置 |
| `get_player_profile(seat)` | 指定座位的公开配置副本；旧快照缺字段时按公开代号生成稳定默认头像 |
| `get_avatar_texture(profile)` | 平台本地头像 Texture2D，缓存复用；Mod 也可按角色 ID 使用自己的美术 |
| `get_profile_color(profile)` | 对应主题色的 Color |

数据可直接从 `snapshot.players` 读取。Texture2D/Color/服务 Node 只用于本机表现，不能放入规则 JSON 或通过网络发送。外观更新不构成规则行动；规则不得把头像或主题色作为获胜条件。

## 通信与兼容

协议 2 的 hello 增加可选 `profile` 以及能力 `user_profile_v1`；支持的新房主在 welcome 中确认能力。旧客户端继续使用 nickname，新房主为其生成默认外观；新客户端连旧房主时不发送实时配置更新，公开服务为旧快照生成回退外观。版本字段目前只写 1，未知内容均忽略并按当前白名单归一化。

新基座的 Session 在平台保存配置后调用 `update_user_profile(local_config)`。房主本地直接更新自己的公开信息；加入方发送 `profile_update`，房主只能根据已认证连接绑定的座位写入，忽略消息中的 seat/ID。未握手连接不能写配置；失败的重连令牌不能修改原资料。更新后发布新快照，不改变游戏 revision、规则状态、座位或对局 ID。断线时本地配置仍保存，凭据重连 hello 会携带最新外观；旧房主下本局不保证实时同步新名称。

## 验证

```sh
Godot --headless --path . --script tests/user_profile.gd
Godot --headless --path . --script tests/profile_network.gd
```

覆盖全部 24 个头像、枚举回退、字段隔离、昵称清理、保存/取消、空名字回退、原身份保留、手机/电视布局；真实 TCP 验证协商、双方外观、实时更新、伪造座位隔离、游戏状态不变与 getter 副本。可视预览使用 `tests/user_profile.gd -- --capture`，截图输出忽略的 `build/validation/`。
