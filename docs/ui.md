# 平台界面与 i18n

平台界面采用 [v0.4「果冻星星 / juicy flat」设计规范](design/README.md)。实际界面由 Godot Control、矢量资源和绘制层组成；SVG 画板用于规范与评审，不是整张图片热区。

## 大厅与导航

- 首页提供「选择游戏」「加入游戏」「用户信息」三个主要入口，设置位于右下角次要入口。
- 选择游戏使用响应式封面网格；内置游戏有专用封面，外部游戏可在 manifest 提供 `cover`，失败时回退星星封面。
- 加入页可显示局域网与蓝牙发现结果，并保留扫码、蓝牙搜索、重新搜索及手动输入。
- 返回键先关闭当前弹层，再回上一级；离开进行中的对局必须经过确认对话框。
- 设置弹层及确认对话框限制焦点范围，关闭后恢复原入口焦点。

## 视觉与反馈

- 颜色、尺寸、字重、动效及触感参数以 `docs/design/tokens.json` 为唯一来源，由 `tools/design/build_design_tokens.py` 生成运行时常量。
- 组件使用纯色块、2 单位描边与 4 单位厚底边；按下面下沉 4，布局本身不跳动。
- 电视焦点为橙色外环、深色轮廓和奶白内边；焦点表示将要操作的控件，选中表示当前值，两者不能混用。
- 音效与触感均可独立关闭。触感仅在 Android / iOS 触屏设备执行，方向键移动焦点不震动。
- 减少动态效果会停止循环装饰、焦点缩放过渡、庆祝运动及弹层上滑，但保留静态焦点和等价文字反馈。

## 代码入口

| 文件 | 职责 |
| --- | --- |
| `app/ui/screens/party_home.gd` | 响应式首页、天空时间变化、星星角色与装饰层 |
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

## 0.1.16 界面重绘

0.1.16 将平台 UI 统一到 v0.4 juicy-flat 规范：组件改为纯色块、2 单位描边和 4 单位厚底边；卡片选中态统一为 `sky.soft + sky`；设置开关、输入框、进度条、横幅与弹层样式收敛到共享主题。电视焦点改为橙色 6 单位外环，并与卡片选中状态分离。新增用户信息页、独立音效/触感开关和减少动态效果处理；确认弹层默认聚焦安全选项。

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
