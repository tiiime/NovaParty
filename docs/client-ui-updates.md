# 客户端 UI 热更新（基础包 0.1.7 起）

Debug 包通过已有的局域网令牌认证 TCP 服务更新完整平台 UI。电视上的旧基础包不能通过 Mod 热更新获得这项能力：需要先覆盖安装一次 0.1.7。之后首页、游戏网格、设置、加入页、等待/错误/离开确认界面、主题、平台翻译、默认封面、星星与按钮资源、字体均可通过 UI 包更新，不再为这些内容安装 APK。

## 使用

```sh
python3 tools/pack_client_ui.py build/ui/client-ui.zip
python3 tools/nvctl.py --connection /private/path/tv.json ui.updates
python3 tools/nvctl.py --connection /private/path/tv.json --activate ui.push build/ui/client-ui.zip
python3 tools/nvctl.py --connection /private/path/tv.json ui.rollback
```

连接文件获取方式同 [Debug 指南](debug.md)，令牌不写在参数或仓库中。`ui.status` 保留当前页面/语言/动画状态查询，并新增 `ui_api`、`ui_build`；`ui.updates` 返回 UI 构建、当前/上一版本、上传数及运行状态。`ui.upload.begin/chunk/abort/commit` 与现有 Mod 上传格式一致，拥有独立存储目录、命名空间和目录文件。激活成功发布 `client_ui_changed`，原连接和订阅继续有效。

每次打包生成唯一的 `ui_versions/u_<uuid>/`，清单声明 `kind=client_ui`、`ui_api=1`、`sdk=1`、完整 Godot 引擎版本、入口和全部文件。整个包以 SHA-256 标识，分片可重试；校验大小、归档路径、文件清单、版本、翻译目录以及入口契约后才允许激活。禁止包直接覆盖 `app/bootstrap.gd`、SDK、项目配置或原有路径。

打包工具将 SVG/PNG/JPEG/WebP 烘焙为携带原始 Image 的可移植 Godot `.res`，TTF/OTF 字体打包为 FontFile `.res`，附带字体许可说明，脚本引用统一改到新命名空间；不依赖目标设备执行 Godot 编辑器导入，也不携带本机 `.godot/imported` 路径或显卡专用压缩纹理。外部 Mod 自带封面和翻译仍随各自的 Mod 更新。

## 生命周期与回退

- 固定入口 `app/bootstrap.tscn` / `bootstrap.gd` 持有 Debug 服务和活跃 Session。`app/main.gd`、`app/ui/*` 及 UI 子场景是可替换 UI。
- 准备新树时保持旧树可用；新树必须完成 `ui_ready` 并通过 ABI 检查，再接入旧 Session 和原来的 Mod 游戏视图。不创建新对局，不重放操作，不替换 Wire、规则对象、私有快照或回执缓存。
- 接管时迁移本地档案、当前游戏选择、地址/端口、重连凭据、页面、状态提示和动画偏好。保留游戏视图实例及其选中状态，并恢复常用控件焦点；设置/离开确认弹层也会恢复。该契约需要 UI 作者继续遵守。
- 激活目录原子写入。准备失败保留旧 UI 与翻译；目录写入失败回切旧 UI。上一版和 APK 内置版均可回退；重复激活同一构建不重复重建。
- 启动先挂载保存的包并恢复活动 UI。候选准备前记录启动保护标记，准备成功后删除；若进程在准备期间被终止，下次启动跳过该候选，使用上一个可用版本。包损坏或版本不兼容时也回退。

UI 包与 Mod 一样是可信代码，以上检查不构成脚本沙箱，也不能自动捕获任意脚本的延迟逻辑错误、无限循环或引擎崩溃。可使用 `ui.rollback` 恢复；启动保护覆盖准备阶段中断，不是持续崩溃监控。

UI 包压缩上限 64 MiB、展开上限 128 MiB、最多 128 个清单文件；每个 UI 更新目录最多保存 8 个包、单进程最多挂载 16 次。字体完整包含在包中，本版包约 11 MiB。超过构建容量会明确拒绝，暂不自动删除旧版本。

## 不在 UI 更新范围

Godot 引擎、原生插件、Android/iOS 权限、APK 图标/安装名称、ProjectSettings、稳定宿主、Debug 服务与网络 SDK 仍需要更新基础包。游戏内部规则和表现继续使用 `mods.*`。Release 不开放网络开发更新服务，也不恢复 Debug UI 包。

## 验证

`python3 tests/client_ui_hot.py` 启动真实生产宿主，通过认证 TCP 上传整包，验证不兼容版本/坏翻译拒绝、候选准备失败、局中切换、回滚、重启恢复和启动保护回退；五子棋与暗牌都在 UI 替换后实际提交操作，核对对局 ID、状态、玩家视图及会话代数不变。

仍需配合既有 UI、联机、Mod 热更新、Debug 和导出隔离回归。实际设备验证情况以 [验证记录](validation.md) 为准。

`python3 tests/client_ui_ios.py --device <UDID>` 对已安装 0.1.7 的 iOS 模拟器执行真实包更新、局中回滚后继续联机操作、重启恢复与回滚，并保存截图和 JSON 报告。
