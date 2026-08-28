# AppStart BLE 架构与市场场景评估

> 只读源码审查 · 17 个 Swift 文件 + BLE_README / ROADMAP
> 初版：2026-08-27 · 阶段 1/2 落地后修订：2026-08-28

## 结论摘要

**方向正确，核心抽象无需推倒重来。** 四层分层（`BleConfiguration` → `BleSession` → `BleCentral` → `BlePeripheralConnection`）职责清楚，符合单一职责与依赖倒置；优化重点应放在**状态与生命周期一致性**，而不是增加 Repository/Manager 等套娃层。

阶段 1（稳定性 P0）已落地：connect 总超时与 Notify ready barrier、同设备并发连接合并、带 token 的扫描会话隔离。修复后，工程估计可覆盖约 **80–90%** 的传统 GATT 控制类 IoT / 穿戴业务。

**当前仍不宜直接宣称「覆盖绝大多数场景」**：Mesh、BLE Audio、厂商 OTA 协议（JL/Bes 等）、Tuya/Telink Mesh 不在本内核边界。

| 指标 | 数量 |
|------|------|
| 已落地稳定性/常见能力项 | 7 |
| 仍需按业务启用的关键缺口 | 2 |

---

## 架构分层

| 层级 | 类型 | 职责 |
|------|------|------|
| 产品协议 | `BleConfiguration` | matching、parser、GATT、ACK、重连策略 |
| 应用入口 | `BleSession` | 产品注册与 `activeConnection` |
| 系统中枢 | `BleCentral` | 唯一 `CBCentralManager`、扫描与连接注册表 |
| 设备句柄 | `BlePeripheralConnection` | 状态机、GATT、写队列与重连 |

配置跟 `BleConfiguration` 走，不跟页面走；App 侧推荐只走 `BleSession.connect(discovery:)`。

---

## 阶段 1 已落地项（P0）

### 1. 让 connect 真正等到可用

**原问题：**

- 物理连接成功（`handleConnected`）时就取消总超时；GATT 卡住会永久 await。
- `setNotifyValue` 后未等待 `didUpdateNotificationStateFor` 确认便进入 `.ready`。

**已做：**

- 总超时覆盖 physical connect + GATT 发现 + Notify 确认；仅在 ready / failed / timedOut 时取消。
- `BleGattSetup` 增加 Notify ready barrier；全部目标 Notify 确认后才产出 ready。
- `BlePeripheralConnection` 转发 `didUpdateNotificationStateFor`。

**涉及文件：** `BleGattSetup.swift`、`BlePeripheralConnection.swift`

### 2. 合并同设备并发连接

**原问题：**

- connecting 会创建第二个 connection；connected 又直接返回未 ready 对象。
- 单个 `connectContinuation` 不能安全容纳多个等待者。

**已做：**

- `connectTasks`：同 peripheral 并发 connect 共享 in-flight Task。
- registry 中 connecting/connected 状态复用连接并 `waitUntilReady()`。
- `connectContinuations[]`：ready / 失败 / 超时时一次性恢复全部等待者。

**涉及文件：** `BleCentral.swift`、`BlePeripheralConnection.swift`

### 3. 明确单扫描会话语义（ScanSession + token）

**原问题：**

- 第二次 scan 覆盖 continuation，但 `isScanning` 时不重启底层扫描。
- 旧 stream 的 `onTermination` 或旧 timeout 可能停止新 scan。

**已做：**

- 引入私有 `ScanSession`（`id` + continuation + configuration/products + timeoutTask）。
- 语义：**新 scan 替换旧 scan**（`replaceScanSession` finish 旧 stream 并 restart 底层 scan）。
- `stopScanSession(token:)` / 超时 / `onTermination` 仅当 token 匹配 `activeScanSession.id` 才停止。

**ScanSession 不单独抽文件的原因：** 与 `BleCentral` 扫描生命周期强耦合，无第二处复用；当前约 7 行数据结构 + 配套方法均留在 Central 内，保持最小 diff。

**典型时序：**

```text
页面 A: scan(timeout: 30s)     session A
页面 B: scan(timeout: 15s)     replace → finish A，启动 B

事件                     效果
────────────────────────────────────────
B 开始扫描               active = B，底层 restart scan
A 的 stream 被取消       onTermination(A) → token 不匹配 → 无操作
A 的 30s 超时到          stopScanSession(A) → 无操作
B 的 15s 超时到          stopScanSession(B) → 正常停止
```

**涉及文件：** `BleCentral.swift`

---

## 阶段 2 已落地项（P1）

### 1. 收紧断连与重连状态

- 只以 `userInitiatedDisconnect` 判定主动断开，nil error 不再误标。
- 自动重连每次等待 physical + GATT + Notify ready，受 `attemptTimeout` 限制。
- 状态机公开 `reconnecting(attempt:maximumAttempts:)`，业务层可区分首次连接与自动重连。
- 手动连接复用已有句柄并停止旧重连循环，避免 delegate/GATT 串线。
- 终态句柄再次连接时刷新 effectiveConfiguration，动态 GATT 不沿用旧快照。
- registry 移除增加 connection 实例身份校验。

### 2. 补齐大数据写入底座

- 普通写校验 `maximumWriteValueLength`，超限抛 `writeDataTooLong`。
- 新增显式 `writeChunked`，避免底层擅自拆分协议指令帧。
- 主通道、附加通道和 serialized queue 统一经过 withoutResponse 背压路径。
- 收到 `peripheralIsReady(toSendWriteWithoutResponse:)` 后恢复发送；断连会取消等待者。

### 3. 明确蓝牙不可用与扫描状态

- connect 在非 poweredOn 时抛 `bluetoothUnavailable`。
- scan 在 unknown/resetting 时等待状态稳定；扫描窗口从真正开始时计时。
- poweredOff/unauthorized/unsupported 时结束兼容 AsyncStream，具体状态由 `centralStates()` 提供。

### 4. 并发归属（部分完成）

- connect in-flight Task 注册由短锁保护，CoreBluetooth 连接流程在 MainActor 执行。
- 扫描创建、替换、停止及状态回调在 MainActor 串行。
- 整体类型 `@MainActor` 隔离会影响现有同步公开 API，保留到下一次主版本迁移，不在本轮破坏兼容性。

---

## 市场业务覆盖矩阵

| 能力 | 结论 | 源码证据 | 判断 |
|------|------|----------|------|
| 单设备连接 | 支持 | `BleCentral.swift`；`BlePeripheralConnection.swift` | 连接、GATT、Notify 确认、ready 主链完整（阶段 1 已修） |
| 多设备连接 | 支持 | `BleCentral.swift` connectionRegistry | 按 `peripheral.identifier` 保存连接句柄 |
| 多产品混扫 | 支持 | `BleCentral.swift`；`BleProductRegistry.swift` | 全量扫描 + 软件 resolve |
| 流式 Notify | 支持 | `BlePeripheralConnection.swift` | 多订阅与 UUID 过滤；ready 需 Notify 确认（阶段 1 已修） |
| 命令请求/响应 | 支持 | `BleWriteCommandQueue.swift` | 单 in-flight、ACK matcher、超时与 withResponse |
| 绑定与会话内重连 | 部分支持 | `BleReconnectHandler.swift` | 会话重连可用；持久化绑定应留在 App Coordinator |
| 前后台生命周期 | 部分支持 | `BleCentral.swift` | 前台流式扫描可用；后台策略和恢复 hook 尚无 |
| 蓝牙开关/授权 | 支持 | `BleCentral.swift` | 状态流、pending scan、不可用 connect 错误已明确 |
| OTA / 大数据协作 | 部分支持 | `BlePeripheralConnection.swift`；`BLE_ROADMAP.md` | 已有 MTU/分片/背压；仍缺 OTA 重连暂停与厂商协议 |
| 断连恢复一致性 | 支持 | `BlePeripheralConnection.swift` | 主动性、完整 ready 重连、手动 connect 竞态已收紧 |
| 诊断与埋点 | 部分支持 | `BleLogger.swift` | 有日志和副通道隔离，缺结构化事件 |
| 可测试性 | 部分支持 | `BleCentral.swift`；`BleModuleSpec.swift` | Central 可注入；状态机/扫描/队列集成覆盖仍不足 |
| 旧固件/动态 GATT | 部分支持 | `BleGattProfile.swift`；`BleUUID.swift` | UUID 等价与 profile merge 较好；Service Changed 未覆盖 |
| withoutResponse 流控 | 支持 | `BlePeripheralConnection.swift`；`BleWriteCommandQueue.swift` | 统一等待 canSend/ready 回调 |
| MTU 感知与分片 | 支持 | `BlePeripheralConnection.swift` | 普通写显式校验；大数据 `writeChunked` |
| Service Changed | **关键缺口** | `BlePeripheralConnection.swift` | 未处理 `didModifyServices`，固件升级后无法原地重发现 |
| State Restoration | **关键缺口** | `BLE_ROADMAP.md` | 被系统终止后的连接恢复尚未实现 |
| 配对/链路加密 | 业务/系统边界 | CoreBluetooth 系统机制 | 系统隐式配对为主；应用层加密属于产品协议 |

---

## 最小演进路线

### 阶段 1 · 稳定性 ✅ 已落地

- connect 总超时覆盖完整 ready 流程
- Notify ready barrier（`didUpdateNotificationStateFor`）
- 同设备并发连接合并（`connectTasks` + 多 waiters）
- 扫描会话隔离（`ScanSession` + token）
- 文档更新（`BLE_README.md`）
- 测试：`BleModuleSpec.swift` 已接入 `AppStart_Tests` target；连接/扫描状态机 mock 测试仍待补

### 阶段 2 · 常见市场能力 ✅ 已落地

- 蓝牙不可用与 pending scan 语义
- 断连重连一致性（完整 ready attempt）
- MTU 查询、显式分片与 `withoutResponse` 背压
- 幂等产品配置、Session 级 stop/disconnect、typed parsedData 等业务 API

### 阶段 3 · 按业务启用

- OTA `suspendReconnect`
- Service Changed → 原地重发现
- 结构化诊断事件
- State Restoration

---

## 保持克制：不要下沉到内核

以下能力应留在 App / 产品层，不应进入 Ble 内核：

- 具体 C0 / F0 / B0 指令语义与组包解包
- 配网流程、产品状态机与页面生命周期
- MAC / deviceId / 云端账号绑定
- JL / Bes 等厂商 OTA 协议
- Tuya / Telink Mesh、BLE Audio 等不同技术栈

---

## 可进一步简化的地方

| 方向 | 说明 |
|------|------|
| 保留四层 | 职责已清楚，无需再加 Repository/Manager |
| 删除半实现能力 | `discoverDescriptors` 若无消费方先移出公开配置，否则补完整 delegate 结果流 |
| 统一错误语义 | `bluetoothUnavailable` / `notConnected` 要么真正抛出，要么不要留死枚举 |
| 简化 parsedData 使用 | 保留类型擦除，给 `BleDiscovery` 增加 typed accessor |
| 优先 FIFO | public `write` 无 priority 参数时可移除排序复杂度 |
| 配置注册幂等 | `register` 目前只 append；可增加 replaceAll 避免重复注册改变 resolve |

---

## 验证边界

- 本结论来自静态代码与现有测试交叉检查。
- 现有测试主要覆盖 UUID、ACK matcher 与 GATT merge（`BleModuleSpec.swift`）。
- 连接/扫描/重连结论应由 mock 状态机测试和真机蓝牙测试补证。

### 阶段 1 真机回归建议

1. 正常扫描 → 连接 → 收 Notify → write
2. 连续点击两次连接，底层 connect/GATT 只应一次
3. 快速进入退出扫描页，新 scan 不被旧 Task 停止
4. Notify 确认较慢时，`connect` 等待而非提前返回
5. 主 Profile + supplementary Notify 均确认后才 `.ready`

---

## 相关文档

- [BLE_README.md](./BLE_README.md) — 实现细节与代码走读
- [BLE_ROADMAP.md](./BLE_ROADMAP.md) — 特性拓展迭代规划
- [AGENTS.md](./AGENTS.md) — Agent 改 Ble 时的补充约定
- [BLE_VALIDATION_CHECKLIST.md](./BLE_VALIDATION_CHECKLIST.md) — 功能验证与回归用例
