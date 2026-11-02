# 局域网发现、Mod 传递与二维码加入（0.1.11）

客户端的「加入游戏」首先搜索附近的游戏，支持扫码和手动地址作为其他入口。全程由发起游戏的设备提供服务，不依赖中心服务器或 Debug 接口。

## 加入流程

1. 发起端使用 `_novaparty._tcp` 广播游戏；接收端用系统 mDNS / DNS-SD 搜索。Android 使用 NsdManager，Apple 使用 DNS-SD / Bonjour。
2. 选中游戏后，通过游戏 TCP 端口查询公开目录：游戏 ID、版本、来源昵称、包大小、SHA-256、规则和表现指纹、当前会话 ID。此时不占玩家座位。
3. 本机存在规则兼容的版本时直接加入；缺少游戏或规则不兼容时显示下载确认。显示来源设备、地址、大小与可信代码提示。
4. 确认后按 24 KB 分块拉取，显示进度；未确认前不接收包。取消、断线、超时和校验失败都会清理临时文件并留在加入页面。
5. 验证完整包 SHA、ZIP 路径和展开大小、清单与所有文件的规则/表现指纹，再保存到私有目录并加载。确认前和验证过程中不实例化规则或表现代码。
6. 以下载的版本继续加入，并将会话 ID 带入握手，防止误加入已经换局的端点。

ZIP 最多 16 MB，展开最多 32 MB、129 个文件（含清单）。包放在不可变的 `mod_versions/<game_id>/<build_id>` 命名空间，以内容 SHA 保存；相同命名空间只允许字节相同的内容。旧版本保留，同一游戏在列表中只显示一项，已知兼容版本仍可复用。重启后恢复已安装的包。

完整性校验不能认证发送者身份，游戏包仍属于可信 GDScript Mod；用户确认下载后才会执行。原始身份 ID、恢复凭据、Debug token 不包含在服务广播、游戏包或二维码中。

## SDK：活动游戏共享

`Session.create()` 自动提供发现和共享端点，只有活动 Mod 的清单文件会被打包。它与游戏消息共享 TCP 端口；目录和包传输不分配玩家座位。表现热更新成功后，Session 更新共享的表现与版本信息，游戏会话和规则状态保留。

接收端使用 `sdk/peer_mods.gd`：

```gdscript
var receiver = preload("res://sdk/peer_mods.gd").new()
add_child(receiver)
receiver.catalog_received.connect(func(metadata):
    # 先向用户显示来源、大小及下载确认；这里只接收目录。
    show_download_dialog(metadata)
)
receiver.progress.connect(show_progress)
receiver.completed.connect(func(path, metadata):
    var info = loader.install_peer_zip(path, metadata)
    if not info.is_empty():
        continue_join(info, metadata.session_id)
)
receiver.failed.connect(show_error)
receiver.inspect_remote(address, port, expected_session_id)
# 用户确认后调用 receiver.confirm_download()，取消时调用 receiver.cancel()。
```

`Loader.install_peer_zip` 在 ZIP 内验证清单和指纹之后才保存、挂载，不要求 Debug 包。规则不兼容的更新不会替换活动局的规则。

## SDK：独立 A → B 传递

不启动游戏也可以提供 Mod：

```gdscript
var sender = preload("res://sdk/mod_sender.gd").new()
add_child(sender)
var info = loader.inspect("res://mods/my_game")
var error = sender.listen(info, "我的设备", 27900)
```

B 仍使用 `PeerMods` 查询、确认、下载和 `install_peer_zip`。此端点返回 `kind: "mod"`，只传递包，不创建房间、不实例化规则、不自动加入游戏；调用方可安装后自行启动。游戏端点返回 `kind: "game"`。等待确认时有轻量保活；单次连接及传输停滞超时为 10 秒。

## SDK：连接二维码

```gdscript
var info: Dictionary = session.get_join_info() # uri/address/port/session_id
var image: Texture2D = session.get_join_qr()
# 多网卡设备可以传入 address_override；默认优先 Wi-Fi/以太网的 IPv4。
```

格式为 `novaparty://join?v=1&address=<IP>&port=<PORT>&session=<SESSION_ID>`。只支持此格式与合法 IP/端口/会话 ID，拒绝普通网页、重复/未知字段及其他版本。二维码保存的是连接位置与当前会话，不含玩家凭据；过期会话会被拒绝。扫码不会跳过缺失 Mod 的下载确认。

默认表现下，发起设备等待第一位玩家加入时显示二维码，加入后隐藏。Mod 可以接管布局：

```gdscript
var services
func set_session_services(value) -> void:
    services = value
func controls_join_qr() -> bool:
    return services != null and services.has_method("get_join_qr")
# 根据自身状态显示/隐藏 TextureRect：
# qr.texture = services.get_join_qr()
```

这些方法是可选扩展，`services` 为稳定 Session Node；不要把 Texture、Node 放进规则状态或网络消息。跳绳 0.1.1 在展示角色无人加入时显示二维码，控制器到场后自行隐藏。

扫描使用 `sdk/qr_scanner.gd` 的 `start(title, close_text)`、`scanned`、`failed`、`canceled` 与 `stop()`。Android 使用相机预览和离线 ZXing，iOS 使用 AVFoundation。相机仅在点击扫码后请求权限/打开；取消、识别完成和退出扫描时释放。帧留在设备，不录制、不上传。`JoinCode.decode_png()` 提供离线图片解码，`JoinCode.decode()` 独立验证连接格式。

## 构建与环境

需要 0.1.11 基础包：原生 Bonjour/NSD、相机入口、iOS 隐私声明及 SDK 协议无法通过原有 UI/Mod 热更新补齐。之后可继续热更新客户端界面与 Mod。

- Apple 适配层由 `python3 tools/build_bonjour.py` 使用已安装 Godot 的 C ABI 和 Xcode 构建；生成的 framework 不入 Git。iOS 声明 `_novaparty._tcp` 与局域网、相机用途，使用系统 Bonjour，不手工接收组播，因此不要求额外 multicast entitlement。
- `python3 tools/build_android.py` 把普通 SDK 的 Java 适配层及固定版本 ZXing Core 3.5.3 打入官方非 Gradle 模板的附加 DEX，并重新对齐、签名、验证；不是 Debug RPC 实现。依赖下载校验 SHA-256，许可证随 APK 提供。`--release` 可构建关闭 Debug 服务的原型包，仍使用本机原型签名；生产签名与发布流程另行配置。
- iOS 模拟器构建 `tools/build_ios_simulator.py` 会替换为匹配的模拟器 framework；物理 iPhone 的签名和相机实测不在模拟器验证范围内。
- 当前自动发现优先 IPv4；路由器隔离/组播过滤或局域网权限拒绝时，可改用二维码/手动地址，但设备之间仍需可直连。

## 验证入口

- `tests/lan.gd`：包指纹、ZIP 边界、确认前不持久化、连接格式、真实二维码像素编解码。
- `tests/mod_sender.gd`：无游戏 Session 的 SDK 独立传递、确认和安装。
- `tests/lan_integration.py`：真实双客户端的取消、确认、安装、自动加入、落子、已安装复用和重启恢复。
- `tests/lan_failures.py`：超大目录、损坏 SHA、非 ZIP 均不安装/不加入。
- `tests/lan_devices.py`：ARM64 模拟设备间真实 NSD、adb 点击房间/下载确认、普通 SDK 传输与连接码加入。
- `tests/capture_lan.gd`：桌面渲染的中英文页面及 Mod 自控二维码；列表和下载详情使用明确的测试数据。

设备记录在 `build/validation/lan-arm-devices.json`；界面和真实模拟器截图位于同目录。真实手机与 iOS 模拟器的 mDNS 双向发现已验证；后续操作按用户要求改用 ARM64 安卓模拟器。

Android ARM64 验证使用自有 AVD `NovaParty_ARM64` 与 `NovaParty_TV_ARM64`（Android 16、API 36、硬件加速）。`tools/emulator_camera.py` 仅连接本机自有 NovaParty AVD 的认证 gRPC 端点，用于移动合成相机；没有关闭认证或使用真实摄像头。已通过虚拟场景图片→相机预览→识码→实际加入的完整测试。
