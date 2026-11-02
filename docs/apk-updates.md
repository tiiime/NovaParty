# Debug APK 网络更新（0.1.12）

Android Debug 基础包提供 HTTP 接收 APK 并触发系统安装的入口，手机和电视共用。首次升级到 0.1.12 仍需使用 adb / USB / 系统文件管理器；之后可以通过局域网传输整个 APK，不再依赖 adb 传包。UI / Mod 热更新继续使用原有接口。

## 使用

使用现有私有 `debug/connection.json`，新增 `apk_http` 字段提供 HTTP 端口和路径。默认 HTTP 为 **27842**，与 Debug RPC 27841 使用相同的 Bearer token、绑定地址。自定义 RPC 端口时 HTTP 使用其后一端口；HTTP 监听失败或非 Android 时 `apk_http` 为空。凭据不要提交到 Git。

```sh
python3 tools/apkctl.py --connection /private/path/connection.json upload build/android/novaparty-0.1.12-debug.apk
python3 tools/apkctl.py --connection /private/path/connection.json status
```

工具以固定大小缓冲区传输文件，自动计算 SHA-256；token 只从文件读取，不放进命令参数。使用 adb 转发测试时：

```sh
adb -s emulator-5554 forward tcp:29843 tcp:27842
python3 tools/apkctl.py --connection /private/path/connection.json --host 127.0.0.1 --port 29843 status
```

上传完成并校验后自动发起安装。Android 8+ 如果尚未允许此应用安装 APK，会打开该应用的“允许来自此来源”设置；授权并返回后继续。保留系统安装确认，安装校验或厂商策略仍可能拒绝。更新会替换运行中的应用，当前对局可能断线；安装后从系统安装器或启动器重新打开。Debug token 随应用进程重启而变化，需要重新获取连接凭据。

## HTTP 契约

每个请求携带 `Authorization: Bearer <Debug token>`。仅处理 HTTP/1.1，单请求后关闭连接，不支持 multipart、chunked 或压缩请求体。

| 方法 | 路径 | 作用 |
| --- | --- | --- |
| POST | `/debug/apk` | 原始 APK 请求体，必填 `Content-Length` 与小写十六进制 `X-APK-SHA256`；校验通过返回 202，随后触发安装 |
| GET | `/debug/apk/status` | 状态、错误码、目标版本、大小、SHA、安装 session ID |
| POST | `/debug/apk/install` | 重试已接收包的安装，或再次检查来源安装授权 |
| DELETE | `/debug/apk` | 清理尚未进入安装阶段的包，例如放弃来源授权；传输/安装中返回 409 |

状态包括 `idle`、`receiving`、`uploaded`、`settings_required`、`preparing_install`、`installing`、`awaiting_confirmation`、`installed`、`failed`、`interrupted`。202 表示上传已接受或安装请求已提交，不代表安装成功。安装结果保存在私有目录；进程因更新退出后，新进程依据系统 `lastUpdateTime` 检查待安装记录是否完成。

## 范围与校验

- 包上限 192 MiB，流式落到应用私有目录；请求头最多 16 KiB，连接读取超时 15 秒，工作线程与等待队列有界，一次仅一个上传/安装。
- 先认证，再接收文件；拒绝重复头、缺失长度/摘要、超大包。取消、断流和失败清理临时包。
- 校验完整 SHA、有效 APK、相同包名与签名、Debug 标志，拒绝版本号降级；允许同版本调试覆盖。系统安装器仍会执行其完整校验。
- 原生实现位于 `native/android_debug`，由构建工具仅注入 Debug APK。Release 不包含该 DEX 类、安装权限或 Debug 服务；`--release` 使用独立 Release 导出配置。
- 此接口沿用现有局域网 Debug 的明文传输方式，不用于公网服务。

构建：`python3 tools/build_android.py --output build/android/novaparty-0.1.12-debug.apk`。
验证入口：`tests/apk_update.py`、`tests/debug_exports.py`。
