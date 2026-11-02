# 本地开发配置

```sh
cp .env.example .env
```

在 `.env` 中填写自己的信息。该文件已被 Git 忽略，`.env.example` 只保留空值或通用默认值。请勿将真实设备信息、账号或凭据填进 example。

| 变量 | 用途 | 未配置时 |
| --- | --- | --- |
| `GODOT` | Godot 可执行文件路径 | PATH 中的 godot，再回退到 macOS 标准安装路径 |
| `ADB` | adb 可执行文件路径 | Android SDK 环境变量、PATH 或 adb |
| `ANDROID_HOME` | Android SDK 路径，用于查找 adb | 也识别系统已有的 ANDROID_SDK_ROOT |
| `ANDROID_SERIAL` | 真机测试的安卓手机序列号 | 必须通过 `--serial` 明确指定 |
| `TV_ADB_SERIAL` | 电视无线 adb 地址或 USB 序列号 | 必须通过 `--tv-serial` 明确指定 |
| `TV_ADB_PORT` | 电视独立 adb 服务的端口 | 5037 |
| `ANDROID_EMULATOR_SERIAL` | LAN / APK 安装测试的模拟器序列号 | emulator-5554 |
| `IOS_SIMULATOR_DEVICE` | iOS 模拟器 UDID 或选择器 | booted |

优先级为：命令行参数 > 进程环境变量 > 仓库 `.env` > 通用默认值。空值视为未配置。路径支持 `~`，含空格需引号；配置读取器只解析字面量 `KEY=value`，不执行 shell，不展开 `$VAR`。

构建脚本、UI 打包器和通过共享测试入口运行的 Python 测试自动读取 `.env`。直接执行 Godot 不会读取 `.env`；SDK/游戏本身也不依赖该文件。Debug 签名默认沿用本机 Godot 编辑器设置。Release 使用 `.env.example` 中的正式签名环境变量，缺少配置时不会回退 Debug 密钥；详见 [GitHub 打包与签名](github-actions.md)。

```sh
python3 tools/build_android.py
python3 tools/build_ios_simulator.py --install --launch
python3 tests/gomoku_android.py --phone-connection <private-phone.json> --tv-connection <private-tv.json>
python3 tests/gomoku_devices.py --tv-connection <private-tv.json>
```

`android_hot.py` 的通用 `--serial` 可传手机或电视；电视测试应显式传 `--serial` 和 `--adb-server-port`，避免误用默认手机。

需要在 shell 里直接使用这些变量时，只加载自己维护、可信的 `.env`：

```sh
set -a; . ./.env; set +a
"${ADB:-adb}" -P "$TV_ADB_PORT" -s "$TV_ADB_SERIAL" get-state
```

调试连接 JSON 内包含动态 token，继续单独保存在私有目录，不写入示例或文档。`build/`、日志、签名材料和连接凭据保持忽略；所有应用导出预设额外排除 `.env` / `.env.*`。

此调整清理当前版本中的个人环境信息，既有 Git 提交及作者邮箱仍保留；没有重写历史。
