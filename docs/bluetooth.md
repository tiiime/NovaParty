# Bluetooth LE 联机

## 目的

Bluetooth LE 用于双方没有共同 Wi-Fi 时联机，并与局域网发现和 TCP 连接并存。主机同时监听 TCP 与蓝牙；上层 Session、Room 和 Mod 协议不区分传输方式。

## GATT 方案

使用 Bluetooth LE GATT：主机是外设（peripheral），加入者是中心（central）。

| 项目 | UUID / 属性 |
| --- | --- |
| Service | `6E6F7661-7061-7274-7900-000000000001` |
| RX | `6E6F7661-7061-7274-7900-000000000002`；中心 → 主机；Write With Response |
| TX | `6E6F7661-7061-7274-7900-000000000003`；主机 → 中心；Notify |

## 广播与发现

广播包含 Service UUID 和房间短码 `NP` + 会话 ID 前 6 位十六进制（共 8 个 ASCII 字节）。两个平台携带短码的位置不同，扫描端两种都识别：

| 主机平台 | 短码位置 | 原因 |
| --- | --- | --- |
| iOS / macOS | 广播的本地名（Local Name） | CoreBluetooth 外设只能广播本地名与 Service UUID，且空间有限 |
| Android | 扫描响应里的 Service Data（键为 Service UUID） | Android 不能为单次广播指定本地名，修改系统蓝牙名称会影响用户设备 |

扫描端只列出短码以 `NP` 开头的设备；设备 8 秒未再次出现即从列表移除。如果同一会话已经通过局域网发现，则不重复显示蓝牙行。蓝牙行在连接前不显示游戏名。

## 建立连接

中心连接外设后依次：

1. 发现服务和特征。
2. 请求 MTU；Android 请求 517。
3. 订阅 TX Notify。
4. 订阅成功后将链路视为打开。

主机侧在收到 TX 订阅时将其视为新对端。

## 数据格式与流控

双向都承载与 TCP 完全相同的**换行分隔 UTF-8 JSON 帧**字节流。原生层按 `MTU - 3` 切片，切片边界没有帧语义；GDScript 的 wire 层继续按换行恢复 JSON 帧。

每个方向同一时刻只有一个在途切片：中心等待 Write With Response 确认，主机等待通知已发送回调。GDScript 侧每条链路最多向原生层交付 4096 个未确认字节；原生桥通过 `ble_sent` 事件归还额度。

## 上层协议

`hello` / `welcome`、心跳、断线重连、Mod 目录获取及分片下载全部复用现有 TCP 上层逻辑。地址格式为：

```text
ble:<设备键>
```

Android 的设备键是 MAC 地址，苹果平台是外设 UUID；端口参数忽略。加入流程会先连接一次读取目录，再连接一次进入对局。

## 原生桥接口

所有平台使用统一接口：

```text
exchange(JSON 字符串) -> JSON 事件数组
```

### 命令

| `op` | 参数 / 作用 |
| --- | --- |
| `ble_state` | 查询蓝牙状态 |
| `ble_permissions` | 请求所需权限 |
| `ble_host` | `{name}`，创建主机 GATT 服务 |
| `ble_advertise` | `{enabled}`，切换广播 |
| `ble_host_stop` | 停止主机服务 |
| `ble_scan` | 开始扫描 |
| `ble_scan_stop` | 停止扫描 |
| `ble_connect` | `{key}`，连接设备 |
| `ble_send` | `{link, data}`；`data` 是 base64 字节 |
| `ble_close` | `{link}`，关闭链路 |
| `ble_shutdown` | 关闭扫描、广播和全部链路 |

### 事件

| `type` | 字段 / 含义 |
| --- | --- |
| `ble_state` | `{state}`；`on` / `off` / `unauthorized` / `unsupported` / `unknown` |
| `ble_found` | `{key, name, rssi}` |
| `ble_open` | `{link}` |
| `ble_data` | `{link, data}`；`data` 是 base64 字节 |
| `ble_sent` | `{link, bytes}`；归还发送窗口 |
| `ble_closed` | `{link, code}` |
| `ble_error` | `{code}` |

中心侧链路名为 `c:<设备键>`，主机侧为 `p:<对端标识>`。

## 平台

### Android

原生实现路径为 `native/android/org/novaparty/sdk/BleLink.java`。Android 12 及以上使用权限：

- `BLUETOOTH_SCAN`
- `BLUETOOTH_ADVERTISE`
- `BLUETOOTH_CONNECT`

Android 11 及以下使用 `BLUETOOTH`、`BLUETOOTH_ADMIN`。由于导出模板无法声明 `neverForLocation`，扫描还需要 `ACCESS_FINE_LOCATION`。

### iOS 与 macOS

CoreBluetooth 实现在 `native/apple`。需要 Info.plist 的 `NSBluetoothAlwaysUsageDescription`；缺少该键时，原生层报告 `unsupported`，不创建蓝牙对象。iOS 模拟器没有蓝牙。

### Windows

暂不支持。

## 限制

- 吞吐量低，适合棋牌和小型 Mod 包；大包下载较慢。
- 加入前先连接一次读取目录，再连接一次进入对局。
- 蓝牙行在连接前不显示游戏名。
- 同一主机最多 16 个对端，与 TCP 对端合计计算。

## 调试

Debug RPC：

- `ble.status`：返回当前桥、状态、扫描、广播、链路和最近错误。
- `ble.request_access`：请求蓝牙权限。
- `lan.inspect`：接受 `ble:<设备键>` 地址，可通过蓝牙读取远端目录。

## 自动测试

```sh
Godot --headless --path . --script tests/unit/bluetooth.gd
```

测试使用进程内假电台 `tests/support/fake_radio.gd`，以 20 字节切片验证发现、目录与下载、握手、对局、发送窗口、断线重连及不可用回退，共 25 项，不需要真实蓝牙硬件。

## 真机验证记录

```sh
python3 tests/devices/bluetooth_devices.py --host <宿主 adb 序列号> --guest <加入者序列号> [--apk build/android/novaparty-0.1.16-debug.apk]
```

脚本只用蓝牙（不提供 IP），流程：两端授权 → 宿主开五子棋 → 加入端扫描 → `lan.inspect ble:<设备键>` 读目录并入座 → 双向各落一子 → 空闲 12 秒确认心跳保活 → 离开后宿主停止广播。结果写入 `build/validation/bluetooth/report.json` 与截图。

| 日期 | 设备 | 结果 |
| --- | --- | --- |
| 2026-11-12 | Android 16 ARM64 电视模拟器（宿主）+ 手机模拟器（加入），同机 netsim 虚拟蓝牙，走真实 Android BLE 协议栈 | 通过：发现 0.2 s，读目录+加入 1.5 s，两步落子 1.1 s，空闲保活 12 s |

联调中发现并修复两处原生问题：

1. 模拟器（以及部分电视芯片）下发硬件扫描过滤器失败（`LE_ADV_FILTER status 0x02`）后会丢弃全部结果。现改为不下发过滤器，在软件里按 Service UUID / Service Data 过滤。
2. MTU 协商到 517 后切片为 514 字节，超过 ATT 属性值上限 512，`notifyCharacteristicChanged` 抛异常且该片已出队。现切片上限为 `min(512, MTU-3)`，发送异常时切片回队重试。

尚未验证：两台实体安卓手机、iPhone / Mac 的 CoreBluetooth 实机互联（同一台 Mac 无法自连；iOS 模拟器无蓝牙），以及安卓 ↔ 苹果跨平台互联。苹果桥已随 `tools/build/build_apple_bridge.py` 为 macOS、iOS、模拟器三目标编译通过。
