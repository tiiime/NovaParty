# 平台界面与 i18n

平台界面采用 [v0.5「派对街机」设计规范](design/README.md)。实际界面由 Godot Control、矢量资源和绘制层组成；SVG 画板用于规范与评审，不是整张图片热区。

## 大厅与导航

- 首页把「选择游戏」「加入游戏」与底部档案、设置分开；手机纵排，电视分栏。
- 游戏库使用响应式封面网格和固定启动栏；展示清单人数与选中摘要，导入成功后直接选中对应包。
- 附近、蓝牙、扫码、手动地址复用目录检查 → 缺包确认 → 握手流程。手动输入不需要先选游戏，可粘贴邀请中的 IP 和端口。
- 系统返回优先关闭最上层弹层、取消正在进行的加入操作，再按页面层级导航。离开游戏说明房主和参与者不同的后果。
- 加入以第一份对局快照为准；失败回到原入口。已入座的断线恢复保留原对局界面，详见 [恢复边界](recovery.md)。

## 视觉与反馈

- 颜色、尺寸、字重、动效及触感参数以 `docs/design/tokens.json` 为唯一来源，由 `tools/design/build_design_tokens.py` 生成运行时常量。
- 组件使用纯色块、2 单位描边与 4 单位厚底边；按下面下沉 4，布局本身不跳动。
- 电视焦点为橙色外环、深色轮廓和奶白内边；焦点表示将要操作的控件，选中表示当前值，两者不能混用。
- 音效与触感均可独立关闭。触感仅在 Android / iOS 触屏设备执行，方向键移动焦点不震动。
- 减少动态效果会停止循环装饰、焦点缩放过渡、庆祝运动及弹层上滑，但保留静态焦点和等价文字反馈。

## 代码入口

| 文件 | 职责 |
| --- | --- |
| `app/ui/screens/party_home.gd` | 响应式首页、星星展台与主次入口 |
| `app/ui/screens/party_flow.gd` | 页面枚举、加入来源及返回目标 |
| `app/ui/screens/join_browser.gd` | 搜索状态、按房间 ID 更新发现列表并保留焦点 |
| `app/ui/screens/game_library.gd` | 游戏封面网格、选中状态、默认封面及添加入口 |
| `app/ui/theme/party_theme.gd` | `button()`、`card()`、`sheet()`、`banner()`、`progress()`、`label()` 及平台 Theme |
| `app/ui/theme/tokens.gd` | 从 `docs/design/tokens.json` 生成的运行时颜色、尺寸、字体、动效和触感常量 |
| `app/ui/widgets/switch_row.gd` | 设置开关行、开关绘制及键盘/遥控器交互 |
| `app/ui/widgets/confirm_dialog.gd` | 双选项确认弹层；默认聚焦取消等安全选项 |
| `app/ui/widgets/sheet.gd` | 通用弹层基类、遮罩、滚动内容、布局及减少动态处理 |
| `app/ui/theme/ui_feedback.gd` | UI 音效、触感反馈、开关偏好、限流及诊断信息 |
| `app/ui/dialogs/user_panel.gd` | 用户头像、配色、主题色及保存/取消 |
| `app/i18n.gd` | 平台翻译加载、语言选择与游戏名称显示 |
| `i18n/zh_CN.json`、`i18n/en.json` | 平台文案与格式化占位符 |
| `mods/<id>/locale-*.json` | Mod 自带文案；作为表现资源随 Mod 分发 |

## i18n 开发规则

1. 平台文案使用稳定 key，并同步维护中文和英文；动态句子先 `tr(key)`，再格式化完整句子。
2. 各语言的 `%s`、`%d` 等占位符必须一致。地址、游戏 ID、请求 ID 和规则数据不得翻译。
3. Mod 自带 locale 文件并列入 manifest 的 `files`，不要加入 `rules_files`。
4. Mod 不依赖平台翻译注册；不支持的语言回退英文。语言切换只重新渲染表现，不改变规则状态。
5. 外部游戏可提供 `localized_names`；它只影响表现，不参与规则指纹。
6. 新语言需要同步更新平台加载列表、设置选项与字体覆盖，并单独验证布局、复数形式和 RTL。

## 验证

已通过桌面短屏/电视画布、键盘焦点、Mod UI、局域网传包、自动重连与客户端热更新回归。五子棋、暗牌、UNO、斗地主和跳绳保留独立玩法美术，更新了等待、提交中、拒绝和恢复反馈；规则脚本未修改。

验证命令：

```sh
Godot --headless --path . --script tests/unit/ui.gd
Godot --headless --path . --script tests/unit/ui_feedback.gd
Godot --path . --script tests/capture/capture_screens.gd
python3 tools/design/build_design_tokens.py --check
```

截图输出到 `build/validation/screens/*.png`。截图检查不能替代手机安全区域、电视焦点、触摸输入及真实设备触感测试。

## 热更新与兼容

平台 UI 脚本、翻译和表现资源可作为客户端 UI 包整体热更新，稳定宿主保留活跃 Session；具体边界见 [UI 更新契约](client-ui-updates.md)。Mod 不得 import `app/` 代码，应通过 SDK 快照、命令、`platform_action` 和可选表现扩展与宿主协作。
