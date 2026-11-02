# Android 构建与真机测试

## 本地构建

使用 Godot 4.6.1、对应 Android 导出模板、OpenJDK 17 和 Android SDK。在 Godot 编辑器设置中配置 Java SDK 与 Android SDK 路径。

```sh
python3 tools/build_android.py
```

输出：`build/android/novaparty-debug.apk`；详细日志：`build/android/export.log`。当前为 ARM32 / ARM64 通用调试包，包名 `org.novaparty.prototype`，不用于商店发布。

Android 预设包含网络权限，并保留 Mod 的 GDScript 原文和 JSON 清单，以保证与桌面端指纹一致；排除测试和工具脚本。竖屏采用 540×960 基准，横屏采用 1280×720 基准，并使用扩展布局。参考 [Godot 4.6 Android 导出文档](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html)。

## 部署

```sh
adb devices -l
adb -s <serial> install --no-incremental -r build/android/novaparty-debug.apk
adb -s <serial> shell am start -n org.novaparty.prototype/com.godot.game.GodotAppLauncher
```

`GodotAppLauncher` 是此模板实际导出的启动入口。设备需要手动解锁。

## 游戏包导入

将独立 Mod 放入手机下载目录，点击“导入可信游戏包”，通过系统文件选择器选择 ZIP。Android 13 使用系统文件访问框架，返回的 URI 由 FileAccess 读取，再复制到 `user://mods` 下。

包大小暂限 16 MB。复制后的包以内容 SHA-256 命名，重启时自动挂载。已有同名游戏不覆盖；更新与卸载流程尚未实现。参考 [Godot 原生文件选择器和 Android URI 说明](https://docs.godotengine.org/en/4.6/classes/class_displayserver.html#class-displayserver-method-file-dialog-show)。

手机导入测试应使用宿主不包含的独立 Mod ID，不能仅选择已内置的游戏。

## 真机检查步骤

1. 检查竖屏布局、中文、点击区域和键盘输入。
2. 手机创建五子棋房间，电脑通过手机 Wi-Fi 地址加入；双方交替落子，检查状态一致和终局。
3. 电脑创建房间，手机输入电脑 Wi-Fi 地址加入；检查反向连接。
4. 暗牌示例完成三轮，检查只显示本方手牌，并在双方提交后揭晓。
5. 导入外部 ZIP，创建游戏，再重启应用确认恢复。
6. 参与者切到后台并返回；中断连接后手动重连，确认身份与状态。

局域网测试使用真实 Wi-Fi 地址，不能把 adb forward/reverse 结果当作 Wi-Fi 联机通过。读取日志时限定 NovaParty 进程，避免采集其他应用日志。


## 已验证范围与故障处理

2026-11-01 已在 Android 13 / Mi 11 上完成上述导入、双向 Wi-Fi 对局、短时后台返回和手动重连。详细结果见 [验证记录](validation.md)。

Android 当前直接调用 `DisplayServer.file_dialog_show`，避免该设备上 FileDialog 的能力检测退回自带文件框。系统 URI 只在选中文件后读取，再复制到私有目录；不申请整个共享存储访问权限。

通过 adb 输入地址时，应等待软键盘就绪，清空旧内容再输入，核对完整 IPv4 地址后连接。触屏事件会带有模拟鼠标副本，Mod 自绘控件应忽略 `InputEvent.DEVICE_ID_EMULATION`，避免一次触摸提交两次操作。


电视实测及 USB 安装限制见 [电视验证记录](tv.md)。0.1.1 已修复系统返回事件处理，真实电视返回键仍待 USB 更新后回归。
