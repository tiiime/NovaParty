# GitHub 构建与打包

## Windows、macOS 与 iOS 模拟器测试包

工作流 `.github/workflows/platforms.yml`，名称 **Desktop and iOS Simulator**。推送 main、推送 v* 标签、向 main 提交 PR 或手动运行时，并行生成以下测试包；不读取任何签名 Secrets，也不发布到商店：

| 平台 | Runner / 架构 | 产物 |
| --- | --- | --- |
| Windows | windows-2025 / x64 | EXE + PCK 的 ZIP，未签名 |
| macOS | macos-15 / Apple Silicon 构建 | Universal ZIP，主程序与 Bonjour 扩展均含 arm64 / x86_64，临时签名，未公证 |
| iOS 模拟器 | macos-15-intel / x86_64 | NovaParty.app 的 ZIP，临时签名，只用于模拟器 |

产物位于对应运行的 Artifacts，保留 14 天。Apple 的 `.app` 用 ditto 打成 ZIP，保留执行权限和包结构。iOS 模拟器包不是 IPA，不能安装到真实 iPhone；Godot 4.6.1 官方模拟器模板当前只有 x86_64，未提供原生 arm64 模拟器产物。

```sh
gh workflow run platforms.yml
gh run list --workflow platforms.yml
gh run download <run-id> --dir build/github
```

CI 安装与校验固定版本 Godot 4.6.1 下载，重建 Apple 原生扩展，检查导出内容仅含五子棋且不含本地配置；然后实际启动打包后的应用，通过 Debug RPC 检查首页和游戏列表。桌面包另检查房间创建/退出，macOS 另检查 Apple Bonjour、二维码、双架构和临时签名。iOS 模拟器仅在回环地址验证启动及原生桥接可用，不替代用户首次授予局域网权限后的真实联机测试。构建和启动分别显示为独立步骤，失败时上传编译日志和模拟器截图。

Windows 目前没有原生 mDNS / 二维码适配器，需手动地址加入；该限制不会因成功打包而消失。macOS 未进行 Developer ID 签名和公证，外部分发后仍可能被 Gatekeeper 拦截。模拟器启动检查不代表真实 iPhone 已验证。

本地 macOS 构建：

```sh
python3 tools/build_bonjour.py --platform macos
python3 tools/build_platform.py --platform macos
```

## Android APK

工作流：`.github/workflows/android.yml`，GitHub Actions 页面选择 **Android APK**。

- 推送 `main` 或向 `main` 提交 PR：检查后生成 Debug APK。
- 手动 **Run workflow**：默认只生成 Debug；勾选 `release` 同时生成正式签名 Release APK。
- 推送 `v*` 标签：同时生成 Debug 和正式签名 Release APK。
- APK 位于运行记录底部的 Artifacts，Debug 保留 14 天，Release 保留 30 天；不自动发布 GitHub Release 或上传商店。

```sh
gh workflow run android.yml                          # Debug
gh workflow run android.yml -f release=true          # Debug + 正式签名 Release
gh run list --workflow android.yml
gh run download <run-id> --dir build/github
```

## 仓库 Secrets

路径：Settings → Secrets and variables → Actions → New repository secret，使用 **Secrets**，不要把密码放在 Variables。

| Secret | 内容 |
| --- | --- |
| `ANDROID_DEBUG_KEYSTORE_BASE64` | 本地 Debug keystore 的 Base64，确保 main 上连续构建签名一致 |
| `ANDROID_KEYSTORE_BASE64` | 正式 JKS / PKCS12 密钥库的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | 正式密钥库密码 |
| `ANDROID_KEY_PASSWORD` | 可选；密钥密码与密钥库密码不同时填写 |

正式签名别名固定为 `novaparty`；如果生成密钥时使用其他别名，需要同步修改工作流的 `ANDROID_KEY_ALIAS`。

密码可以在本机交互输入，避免放入命令参数或聊天：

```sh
gh secret set ANDROID_KEYSTORE_PASSWORD --repo tiiime/NovaParty
# 仅密码不同时设置：
gh secret set ANDROID_KEY_PASSWORD --repo tiiime/NovaParty
```

上传密钥文件的命令（将路径替换为自己保存的文件，Base64 直接通过管道提交，不打印内容）：

```sh
base64 < "$HOME/.android/keys/novaparty-release.jks" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64 --repo tiiime/NovaParty
```

Base64 本身不提供加密；`gh secret set` 会在提交前加密，GitHub Secrets 存储密文。请继续独立备份原始密钥和密码。

## 构建实现

使用 Ubuntu 24.04、Java 17、Godot 4.6.1、Android API 35 / Build Tools 35.0.1。Godot 和模板下载校验仓库内固定的 SHA-512；Actions 引用固定 commit SHA。

Linux Android 构建不使用 Apple Bonjour 扩展，CI 在临时 checkout 中移除其描述文件；Android 包使用 Java NSD / ZXing 桥接。检查包括规则、UI、中英翻译、配置读取，以及最终 APK 的签名、包 ID、双 ARM 架构、Debug 开关、原生类和仅五子棋内置限制。

正式签名只发生于标签和手动触发；PR 不接触签名 Secrets，使用临时 Debug key。推送 main / 标签的 Debug 包使用固定 Debug key；首次切换到正式签名时，旧 Debug 包通常需卸载后安装，之后正式包保持同一签名即可更新。

`tools/android_config.py` 优先从环境变量 / 本地 `.env` 读取 SDK、Java 和签名配置，未配置时读取对应平台 Godot 编辑器设置。Release 缺少正式密钥配置会直接失败，不再回退 Debug 签名。签名密码通过子进程环境传给 apksigner，不出现在命令参数；临时密钥在作业结束时清理，产物只包含 APK。
