# 网络热更新（0.1.3 / D2）

手机和电视先安装一次 `novaparty-0.1.3-debug.apk`。这版包含网络更新模块，此后在模块支持范围内修改 Mod，无需重装 APK。0.1.2 不包含此模块，不能通过旧调试接口自行升级到本版。

已支持：网络分块上传、SHA-256 校验、独立构建命名空间、在对局中替换本机界面脚本和原始资源、焦点与选格恢复、手动回退、重启后恢复所选构建。进行中的 Session、规则对象、座位、对局 ID 和版本保持不变。

规则脚本或规则数据发生变化时，可以在大厅选择新构建，供下一局使用；双方规则指纹必须相同。当前不支持进行中的规则状态迁移和全端升级事务。平台 SDK、Debug 服务、Godot 引擎、原生插件及权限的更新仍需新 APK。

## 一次更新

使用 [Debug 连接指南](debug.md) 获取连接文件。应用重启后令牌会变化，需要重新获取连接配置，不需要重新安装 APK。为目标 Mod 的副本修改表现脚本或资源，清单中明确声明规则依赖：

```json
{"id":"gomoku","name":"五子棋","version":"0.1.0","sdk":1,"rules":"rules.gd","view":"view.gd","files":["rules.gd","view.gd","theme.json"],"rules_files":["rules.gd"],"players":{"min":2,"max":2}}
```

`rules_files` 必须包含规则入口，以及规则使用的全部脚本、配置、共享依赖。其余 `files` 作为表现文件。未声明 `rules_files` 的普通旧包仍可运行，所有文件保守计入规则指纹；网络热更新包必须显式声明。

五子棋的 `theme.json` 中可以修改 `board_color`，例如 `4b85b4`。打包及推送：

```sh
python3 tools/pack_mod.py /path/to/gomoku-copy build/gomoku-blue.zip --hot
python3 tools/nvctl.py --connection /tmp/tv.connection.json --activate mods.push build/gomoku-blue.zip
python3 tools/nvctl.py --connection /tmp/tv.connection.json mods.status
python3 tools/nvctl.py --connection /tmp/tv.connection.json mods.rollback '{"game_id":"gomoku"}'
```

`mods.push` 是 CLI 组合命令，依次调用上传 RPC；`--activate` 在上传完成后切换。省略该参数只存储候选构建。已有完全相同的 ZIP 会返回现有构建。调用 `mods.activate` 时使用上传结果中的 `build`（ZIP SHA-256），不是清单中的 `build_id`。

每次 `--hot` 打包生成新的 `b_<UUID>`，ZIP 位于 `mod_versions/<id>/<build_id>/...`，运行根为 `res://mod_versions/<id>/<build_id>`。不覆盖旧路径，不依靠清除 ResourceLoader 缓存。再次修改后重新打包，得到新的命名空间；禁止复用 build_id 放置不同内容。

资源在脚本中从自身构建根相对读取，例如 `get_script().resource_path.get_base_dir().path_join("theme.json")`。不要硬编码旧的 `res://mods/<id>` 或其他构建路径。当前已经实际验证 GDScript 与原始 JSON 资源。PNG 等原始数据可使用相应运行时解码接口；需要 Godot 导入产物的纹理、音频、场景、字体依赖尚未完整验证，不能假设源文件放入 ZIP 后所有 `load()` 都会自动完成导入。

## 对局兼容

协议 2 的客户端通过 `rules_fingerprint` 协商规则兼容，允许表现不同。规则指纹包含清单的规则元数据以及 `rules_files` 的字节哈希；显示名称、版本、表现入口、完整文件列表、构建 ID 和输入方式不进入规则元数据。其他清单字段保守计入。表现指纹包含表现入口与非规则文件的字节哈希。

房主仍接受协议 1，但该分支继续要求整个包的原始 `fingerprint` 完全相同，不放宽旧客户端校验。0.1.3 客户端发送协议 2；过旧房主会拒绝，需先更新双方基础客户端。

对局中 `mods.activate` 检查游戏 ID 与规则指纹。规则不同或切换到另一个游戏会被拒绝。选择新界面不会替换 `Session.info` 或房主规则对象；应用单独记录本机表现构建，重连时使用同规则的新构建进行协商。

## 表现契约与回退

表现仍继承 Control，提供 `command(action)` 信号和 `render(snapshot)`。可实现：

```gdscript
func capture_view_state() -> Dictionary:
    return {"cursor": [board.cursor.x, board.cursor.y], "focused": board.has_focus()}

func restore_view_state(state: Dictionary) -> void:
    # 恢复选格，并在需要时恢复焦点。
    pass
```

宿主先加载、检查并准备新界面，然后断开旧界面的输入信号，替换显示并连接新界面。恢复钩子在新界面可见后调用；焦点子节点使用稳定名称，可帮助通用焦点路径恢复。平台外部控件的焦点也会保留。内置五子棋和暗牌示例均实现恢复钩子。

坏哈希、非法命名空间、越界文件、无效清单、无法实例化的脚本或缺少基本表现接口会被拒绝，不更换当前界面。对局中规则指纹变化同样被拒绝。`mods.rollback` 回到上一个已激活构建，首次更新内置游戏可回到内置版本。

可信 GDScript 的任意运行错误、死循环和原生崩溃无法保证都在进程内检测或回滚。不要把新脚本的任意运行错误视为事务异常可捕获；先在独立 Godot 进程验证候选。当前热更新不提供脚本沙箱。

## 上传 RPC

与 Debug 共用鉴权连接和 64 KiB 换行 JSON 帧：

| 方法 | 参数 | 结果 |
|---|---|---|
| `mods.upload.begin` | `size`, `sha256` | `upload_id`, `offset`, `chunk_size`；相同已存包返回 `existing`, `build` |
| `mods.upload.chunk` | `upload_id`, `offset`, `data`（标准 Base64） | 下一个 `offset`；已收到且字节相同的块可原样重试 |
| `mods.upload.commit` | `upload_id` | 校验、挂载并登记候选，返回构建信息；不自动激活 |
| `mods.upload.abort` | `upload_id` | 删除暂存上传 |
| `mods.status` | `{}` | 构建、当前/上一构建、上传数量、本机界面状态 |
| `mods.activate` | `build` | 切换结果，含 `presentation_only` 与 `view_state` |
| `mods.rollback` | `game_id` | 切回上一构建 |

成功切换还推送 `presentation_changed` 事件。`debug.capabilities.hot_update` 返回 `upload` / `presentation` / `live_rules` 及包/块上限。

上限：ZIP 16 MiB，解压总量 32 MiB，最多 129 个条目（包含清单），清单 64 KiB，单块 24 KiB，两个并行上传，上传空闲 120 秒清理；已确认的不同内容 ZIP 至多保留 8 个，每进程最多尝试挂载 16 次。Godot 无法卸载已挂载资源包，所以不自动覆盖或无限堆积；达到容量后提示重启或清理本应用的热更新存储。当前尚无网络删除构建接口，清理前保留需要的构建和连接配置。

服务先检查 ZIP 中央目录大小，再解压并校验文件集合和命名空间。拒绝目录穿越、重复路径、额外文件、多盘 ZIP、加密 ZIP 和 ZIP64。暂存文件不会直接挂载；完成校验后使用不可变的最终 ZIP 路径。构建目录、当前/上一选择通过临时文件及重命名保存，启动时重新验证包哈希；不可用的当前构建会尝试上一可用构建，否则使用原有游戏入口。

存储位于连接配置目录下的 `hot/`；Android 默认 `user://debug/hot/`。这是开发数据，与普通导入的 `user://mods/` 分开。Debug 目录及全部更新服务代码继续排除于 Release 包。

## 验证

```sh
python3 tests/hot_integration.py
python3 tests/hot_integration.py --visual
python3 tests/debug_integration.py
python3 tests/debug_exports.py
```

前两项运行真实应用的双客户端，验证切换资源、局面不变、继续对局、焦点/选格与单一输入连接、坏包拒绝、回退、重启恢复和不同表现的协议 2 加入。可视验证截图输出 `/tmp/novaparty-hot-update.png`。

Android 真机回归需要手机已安装 0.1.3、在前台创建一个全新五子棋房间，并有连接配置：

```sh
python3 tests/android_hot.py --connection /tmp/phone.connection.json --serial <serial> --restart --create-tap <已观察的创建按钮x,y>
```

此脚本连接一个真实 Godot 对手，通过手机的 LAN 接口完成热更新和九手整局，再重启验证恢复，回退到内置界面并返回大厅。它会结束所创建的测试对局。手机测试截图保存在 `build/validation/android-hot-update.png`。

TCL Android 9 / ARM32 电视已通过同一测试流程；使用 `--adb-server-port 5038 --artifact-prefix tv --remote-first-move --create-tap 85,480`，截图为 `build/validation/tv-hot-update.png`。电视与手机都已验证更新后继续整局、回退及重启恢复。
