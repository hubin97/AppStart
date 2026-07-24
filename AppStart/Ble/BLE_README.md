# Ble 模块

基于 Swift Concurrency（async/await + AsyncStream）的 CoreBluetooth 封装，支持多页面共享连接、**多产品协议**并存。

## 功能

- 扫描 / 连接 / 断开 / 多设备
- 多产品：每款独立 `BleConfiguration`（匹配 + GATT + 写队列 + 广播解析）
- GATT 自动发现，就绪后 `connect` 返回
- 可选自动重连、串行写队列（ACK 匹配 + 超时）
- `BleSession` 跨页面共享 `activeConnection`

---

## 架构

```
业务 App
  └─ BleConfiguration + BleAdvDataParser（产品协议）
       ↓ register
BleSession（产品注册表 + activeConnection）
       ↓
BleCentral（唯一 CBCentralManager）
       ↓
BlePeripheralConnection（状态机 + GATT + 写队列 + 重连）
```

| 层级 | 职责 |
|------|------|
| `BleConfiguration` | 单款产品完整协议快照 |
| `BleSession.register` | App 启动注册各产品 |
| `BleCentral.scan(products:)` | 混扫；**系统层不按 Service UUID 过滤** |
| `BleDiscovery.configuration` | 混扫 resolve 命中的配置 |
| `BlePeripheralConnection` | 连接时绑定配置快照，后续 register 变更不影响已连设备 |

**原则：** 配置跟 `BleConfiguration` 走，不跟页面走；无外部 productId，展示名等 UI 信息由 App 层维护。

---

## 快速上手

### 1. 定义产品协议

```swift
struct MyPumpParser: BleAdvDataParser {
    typealias ParsedData = String
    func parse(advertisementData: [String: Any]) -> String? {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.starts(with: [0xAA]) else { return nil }
        return "..." // MAC 等
    }
}

enum BleProducts {
    static let pump = BleConfiguration(
        matching: BleParserValidatedMatchingStrategy(parser: MyPumpParser()),
        serviceUUIDs: [CBUUID(string: "AF00")!],
        writeCharUUID: CBUUID(string: "AF01"),
        notifyCharUUID: CBUUID(string: "AF02"),
        writeQueue: .serialized(
            ackMatcher: BleByteAckMatcher(indices: [0, 1, 3]),
            defaultTimeout: 3,
            order: .descending
        ),
        parser: MyPumpParser(),
        debugLog: true,
        logTag: "[Ble/Pump]"
    )

    static let all: [BleConfiguration] = [pump]
}
```

推荐匹配策略：`BleParserValidatedMatchingStrategy`（parser 解析成功即命中；可选 `names` 做 LocalName 前置过滤）。

### 2. App 入口注册

```swift
BleSession.shared.register(BleProducts.all)
```

### 3. 扫描

```swift
Task {
    for await discovery in BleSession.shared.scanAllProducts(timeout: 20) {
        let config = discovery.configuration
        let parsed = discovery.parsedData
        // 按 configuration.logTag 或 parsed 类型区分产品
    }
}
```

单产品：

```swift
for await discovery in BleSession.shared.scan(configuration: BleProducts.pump, timeout: 20) { ... }
```

### 4. 连接

```swift
let connection = try await BleSession.shared.connect(discovery: discovery, timeout: 10)
// activeConnection 已由 connect 自动赋值，无需再手动设置
```

`discovery.configuration` 为 nil 时抛 `BleError.configurationNotResolved`。App 层请只走 `BleSession.connect(discovery:)`，不要绕过 Session 直接调 `BleCentral.connect`。

### 5. 读写与状态

```swift
for await state in await connection.states() { ... }
for await update in await connection.characteristicUpdates() { ... }
try await connection.write(data)
connection.disconnect()
```

---

## 扫描与连接流程

### 扫描（`handleDiscovery`）

```
CBCentral didDiscover
  → 产品扫描：resolve 失败则丢弃
  → advParser 解析 → BleDiscovery（parsedData 可为 nil）
  → 同 identifier 更新缓存并多次 yield（RSSI 刷新）
```

要点：

- `scan(products:)` 传 `serviceUUIDs: nil`，全量扫描，避免厂商数据/LocalName 设备被系统层滤掉
- **门禁在 resolve / matching**，不在展示名；框架发现日志优先 `parsedData`（如 MAC），`displayName` 供 UI

### 连接

```
BleSession.connect(discovery:)  // App 推荐入口
  → private connect(peripheral, discovery.configuration)
  → BleCentral.connect（绑定配置快照）
  → 物理连接 → discoverServices → discoverCharacteristics
  → 订阅 Notify、定位 writeChar → .ready
  → waitUntilReady() 返回；activeConnection 已赋值
```

状态机：`connecting → connected → ready`；失败 `failed` / `timedOut`；断开 `disconnected`。

---

## 代码走读指南

建议按 **「类型定义 → 协议配置 → 扫描 → 连接 → 写入 → 基础设施」** 顺序阅读，先建立数据模型，再跟调用链。

### 推荐阅读顺序

| 阶段 | 文件 | 一句话 |
|------|------|--------|
| 公共类型 | `BleEnums.swift` | 状态、发现结果、错误码 |
| 协议模型 | `BleConfiguration.swift` | 单产品完整配置快照 |
| 扫描过滤 | `BlePeripheralMatching.swift` | 第一道过滤：要不要这条广播 |
| 广播解析 | `BleAdvDataParser.swift` | 第二道：解析 MAC 等业务字段 |
| 多产品 | `BleProductRegistry.swift` | OR 匹配 + resolve 顺序 |
| App 入口 | `BleSession.swift` | register / scan / connect |
| Central | `BleCentral.swift` | CBCentralManager + 扫描会话 |
| 广播流 | `BleAsyncBroadcastStream.swift` | 多页面订阅同一事件源 |
| 连接句柄 | `BlePeripheralConnection.swift` | 状态机 + 写 + Notify |
| GATT | `BleGattSetup.swift` | Service → Char → Notify |
| 重连 | `BleReconnectHandler.swift` | 意外断开轮询 connect |
| 写队列 | `BleWriteCommand` / `BleWriteCommandQueue` / `BlePriorityQueue` | 串行写 + ACK |
| 日志 | `BleLogger.swift` | debugLog → LogM |

---

### 1. `BleEnums.swift` — 公共 vocabulary

先读这里，后面所有文件都引用这些类型。

**`BleDiscovery`** — 扫描产出物，连接入口：

| 字段 | 含义 |
|------|------|
| `peripheral` | CoreBluetooth 外设对象 |
| `advertisement` | 原始广播 + RSSI |
| `parsedData` | `advParser` 解析结果（`Any?`，App 层 as 成具体类型） |
| `configuration` | 混扫 resolve 命中的 `BleConfiguration`；临时扫描无注册时为 nil |

**`BlePeripheralState`** — 连接状态机：

```
connecting → connected → ready(BleChannelReadyInfo)
         ↘ failed / timedOut
         ↘ disconnected(userInitiated | unexpected)
```

- `connecting`：`centralManager.connect` 已调用，物理连接未完成
- `connected`：物理连接 OK，GATT 发现进行中
- `ready`：写特征已定位、Notify 已订阅，可 `write`
- `connect()` 的 `await` 在 `.ready` 时 resume

**`BleCharacteristicUpdate`** — Notify 推送，供 UI 订阅；写队列也会消费同一路径。

**`BleDiscovery.displayName`** — 扫描展示名（LocalName → `peripheral.name`），不参与 matching / yield 门禁。

**`BleError`** — 按场景分类：

| 错误 | 触发点 |
|------|--------|
| `configurationNotResolved` | `connect(discovery:)` 时 discovery 无 configuration |
| `connectionTimeout` | 连接阶段超时 |
| `channelSetupFailed` | GATT 发现失败 |
| `writeCharacteristicNotFound` | 未找到 writeChar 就 write |
| `writeTimeout` | 串行队列 ACK 超时 |
| `cancelled` | 断开时队列被清空 |

---

### 2. `BleConfiguration.swift` — 单产品协议快照

一款产品的**全部蓝牙约定**集中在一个 struct 里，连接时拷贝一份快照，后续 `register` 变更不影响已连设备。

| 字段 | 扫描阶段 | 连接阶段 |
|------|----------|----------|
| `matching` | ✅ 过滤广播 | — |
| `advParser` | ✅ 解析 MAC 等 | — |
| `serviceUUIDs` | ❌ **不用于系统 scan 过滤** | ✅ discoverServices |
| `readCharUUID` / `writeCharUUID` / `notifyCharUUID` | — | ✅ discoverCharacteristics |
| `writeQueue` | — | ✅ direct 或 serialized |
| `reconnect` | — | ✅ 自动重连策略 |
| `debugLog` / `logTag` | — | ✅ 日志开关与 tag |

**`BleWriteQueueConfiguration`：**

- `.direct` — 直接 `writeValue`，不等待 ACK，`write()` 立即返回
- `.serialized(ackMatcher, defaultTimeout, order)` — 串行队列，一条 in-flight，Notify 或 writeResponse 确认后发下一条

**`BleAckMatcher` / `BleByteAckMatcher`：**

- 协议方法 `matches(command:response:)` 判断 Notify 是否为当前队首指令的应答
- 默认 `[0, 1, 3]` 比对帧头 + CID（如 Momcozy `AA 55 … C0`）
- 复杂协议在 App 层实现自定义 `BleAckMatcher`

---

### 3. `BlePeripheralMatching.swift` — 扫描第一道过滤

**职责：** 在 `didDiscover` 里决定「这条广播要不要进入结果列表」，**不做**业务字段解析。

| 策略 | 行为 |
|------|------|
| `BleDefaultMatchingStrategy` | 全收 |
| `BlePrefixMatchingStrategy` | 名称前缀 或 厂商数据前缀（`manufacturerDataPrefix`） |
| `BleParserValidatedMatchingStrategy`（在 AdvDataParser 文件） | parser 解析成功即命中，可选 names 过滤 LocalName |

**注意：** `matching` 与 `advParser` 职责分离 — matching 只回答「是不是我的设备」，parser 回答「广播里有什么」。

---

### 4. `BleAdvDataParser.swift` — 广播解析 + 推荐匹配

**`BleAdvDataParser`** — 关联类型 `ParsedData`，解析失败返回 nil。

**`AnyBleAdvDataParser`** — 类型擦除，让 `BleConfiguration` 能存不同 ParsedData 的 parser。

**`BleParserValidatedMatchingStrategy`** — 推荐默认策略：

1. 若配置了 `names`，先比对 LocalName（优先 `CBAdvertisementDataLocalNameKey`，fallback `peripheral.name`）
2. 调用 parser，`!= nil` 即 matching 命中

内置示例：`BleMACParser`、`BleManufacturerDataParser`、`BlePeripheralNameParser`。

App 层应实现产品专属 parser（如吸奶器 MAC 格式），放在业务模块而非框架内。

---

### 5. `BleProductRegistry.swift` — 多产品混扫

```swift
// 混扫 matching = 所有产品 OR（第一道：可能是自家设备）
products.compositeMatching

// resolve = 按 register 顺序取第一个命中的 configuration（定案：用哪款 advParser / GATT）
products.resolve(peripheral:advertisementData:)
```

| 机制 | 时机 | 规则 | 用途 |
|------|------|------|------|
| `compositeMatching` | 混扫 `scan(products:)` 合并 matching | 任一产品 matching 命中 | 软件层 OR 过滤（系统 scan 仍全量） |
| `resolve` | `handleDiscovery` 每条广播 | **先 register 者优先** | 写入 `BleDiscovery.configuration`，决定 parser 与连接协议 |

**关键规则：**

- 两款产品 matching 同时命中 → **先 register 的赢**
- resolve 结果写入 `BleDiscovery.configuration`，连接时直接用，无需 App 再猜产品类型
- 无 productId 字符串；区分产品靠 `configuration` 引用或 `logTag` / `parsedData` 类型

---

### 6. `BleSession.swift` — App 层唯一推荐入口

薄封装，不做 CoreBluetooth 细节：

| API | 作用 |
|-----|------|
| `register(_:)` / `register([:])` | 追加产品配置，同步 Central 日志 |
| `configure(_:)` | 单产品场景更新 Central 默认配置 |
| `scan(configuration:)` | 扫单款产品 |
| `scan(at:)` | 按注册下标扫 |
| `scanAllProducts()` | 混扫全部已注册产品 |
| `connect(discovery:)` | 从扫描结果连接（**App 唯一推荐入口**；内部 private connect 绑定 resolve 后的 configuration） |

跨页面共享：`activeConnection` + `central.activeConnections`。

---

### 7. `BleCentral.swift` — CoreBluetooth 中枢

**单例 `BleCentral.shared`**，持有一个 `CBCentralManager`，所有扫描/连接经此出入。

#### 扫描会话上下文（一次 `scan()` 生命周期）

| 变量 | 作用 |
|------|------|
| `isScanning` | 是否正在 CBCentralManager 扫描 |
| `scanTimeoutTask` | 超时 Task；到期自动 `stopScanning()` |
| `activeScanContinuation` | 向 AsyncStream 消费方 yield |
| `activeScanProducts` | 多产品列表，供 resolve |
| `activeScanConfiguration` | 本轮 matching 用的配置（单产品或 composite） |
| `discoveredDevices` | 本轮缓存；同 identifier 原地更新，并多次 yield 以刷新 RSSI |

#### `handleDiscovery` 完整链路

```
didDiscover
  → 产品扫描：activeScanProducts.resolve()，失败则丢弃
  → 临时扫描：matching.shouldConnect()，失败则丢弃
  → resolvedConfiguration.advParser 解析广播（失败 parsedData = nil）
  → 构造 BleDiscovery → 更新 discoveredDevices → yield
  → 仅首次发现打日志（优先 parsedData.mac，否则 parsedData 字符串）
```

#### 为何 `scan(products:)` 传 `serviceUUIDs: nil`

系统层按 Service UUID 过滤时，很多设备广播里不带目标 Service，会被漏扫。框架选择**全量 scan + matching 软件过滤**。

#### 连接 `connect(to:configuration:)`

1. 若 registry 里已有 connecting/connected/ready 的连接 → 复用
2. `makeConnection` 创建 `BlePeripheralConnection`（绑定配置快照）
3. `performConnect` → Delegate `didConnect` → GATT → `waitUntilReady()`
4. 超时由 connection 内部 Task 触发 disconnect

#### Delegate 转发

| 回调 | 去向 |
|------|------|
| `didDiscover` | `handleDiscovery` |
| `didConnect` | `connection.handleConnected()` |
| `didDisconnect` | `connection.handleDisconnected()` |
| `didFailToConnect` | `connection.handleConnectFailed()` |

所有 Delegate 回调包在 `@MainActor` 里执行。

---

### 8. `BleAsyncBroadcastStream.swift` — 多订阅广播

Actor 实现，维护 `[UUID: Continuation]` 字典。

| 模式 | 用途 | 使用处 |
|------|------|--------|
| `replayLatest: true` | 新订阅者立即拿到最新值 | 蓝牙状态、连接状态、扫描状态 |
| `replayLatest: false` | 只收订阅后的增量 | Notify 特征更新 |

替代方案：注释里提到可用 `AsyncAlgorithms` 的 `AsyncChannel` 简化实现。

---

### 9. `BlePeripheralConnection.swift` — 单设备生命周期

**初始化时按 configuration 创建：**

- `BleGattSetup` — GATT 发现
- `BleWriteCommandQueue` — 仅 `.serialized` 时
- `BleReconnectHandler` — 仅 `reconnect.enabled` 时

#### 连接流程

```
beginWaitingForReady()           // 状态 → connecting
performConnect (Central)
  → handleConnected()            // 状态 → connected，discoverServices
  → GattSetup 链式发现
  → finishGattSetup              // writeChar 赋值，状态 → ready
  → completeConnectIfNeeded()    // resume connect 的 continuation
```

#### 写入 `write(_:type:timeout:)`

- 有 writeQueue → 构造 `BleWriteCommand` → `enqueue` 挂起直到 ACK
- 无 writeQueue → 直接 `peripheral.writeValue`

#### Notify 双消费（重要）

```swift
didUpdateValueFor
  → updateBus.yield()              // UI / 业务订阅
  → writeQueue?.handleCharacteristicUpdate()  // ACK 匹配
```

改 Notify 处理逻辑时必须兼顾两路：UI 需要全量推送，队列只认 ACK。

#### 断开

- `disconnect()` 设 `userInitiatedDisconnect = true`，不触发重连
- 意外断开 → `reconnectHandler.notifyUnexpectedDisconnect()`
- 断开时 `writeQueue.cancelAll()`，所有 pending write 抛 `cancelled`

---

### 10. `BleGattSetup.swift` — GATT 发现链

```
beginServiceDiscovery
  → discoverServices(serviceUUIDs 或 nil=全部)
  → 每个 service → discoverCharacteristics(配置的 UUID 或 nil=全部)
  → process: read / setNotify / 记录 writeChar
  → 所有 service 完成 → finalizeIfNeeded → Result
```

- `pendingServiceCount` / `completedServiceCount` 计数，全部完成后一次性 ready
- `didEmitReady` 防止多 service 回调重复触发
- 配置了 `writeCharUUID` 但未找到 → `writeCharacteristicNotFound`

---

### 11. `BleReconnectHandler.swift` — 自动重连

Task 驱动的轮询，**不是** UI Controller：

```
notifyUnexpectedDisconnect / notifyConnectFailed
  → runLoop: 每 interval 调用 connect?()
  → 成功 → notifyConnected → stop
  → 达 maxAttempts → onPhaseChange(.exhausted) → 连接状态 timedOut
```

- `notifyUserDisconnect()` → 设 flag + stop，不再重连
- 重连成功后 `notifyConnected()` 重置 attempts

---

### 12. 写队列三件套

#### `BleWriteCommand`

单条写指令：`data`、`writeType`、`timeout`、`priority`、`requestId`（UUID）。

#### `BlePriorityQueue`

支持 `.ascending` / `.descending` 优先级排序；队首 `peek()` 即当前 in-flight 候选。

#### `BleWriteCommandQueue` — 核心状态机

```
enqueue → 入队 + 挂起 continuation
processNextIfNeeded → 队首无 timeoutTask 时 writeValue（同一时刻仅一条 in-flight）
  ↓
handleCharacteristicUpdate → ackMatcher 匹配队首 → completeHead → 发下一条
handleWriteConfirmation   → withResponse 模式在此 complete
handleTimeout               →  dequeue + throw writeTimeout + 发下一条
cancelAll                   → 断开时清空，throw cancelled
```

**日志（debugLog 开启时）：**

- 发送：`写入指令 <requestId>: <hex>`
- 成功：`指令 ACK(notify|writeResponse) <requestId>: <hex>`
- 失败：`指令失败` / `写入超时`

**ACK 设计边界（见下方「常见陷阱」）：**

- 串行队列保证不会两条指令同时在途，**不存在**「后发 C0 先 ACK」的 in-flight 乱序
- 相同 payload 重复发送 + 超时后迟到 ACK，可能被误判为当前队首的应答

---

### 13. `BleLogger.swift` — 日志

- `BleConfiguration.debugLog = true` 时才输出
- 写入 `LogM.tag(normalizedTag).debug(...)`
- `BleCentral.syncLogger(from:)` 在 register / scan / connect 时合并多产品 logTag

**前置条件：** App 启动时 `LogM.shared.setup(...).launch()`，否则看不到日志。

---

### 端到端调用链

#### 扫描 → 连接

```
App: BleSession.register(products)
App: for await d in scanAllProducts()
  → BleCentral.scan(products:)
  → startScanning(serviceUUIDs: nil)
  → didDiscover → handleDiscovery → yield(d)

App: try await connect(discovery: d)
  → BleSession private connect(peripheral, d.configuration)
  → BleCentral.connect → activeConnection 赋值
  → BlePeripheralConnection.waitUntilReady()
  → didConnect → GattSetup → .ready
```

#### 写入（serialized）

```
App: try await connection.write(c0Data)
  → writeQueue.enqueue
  → processNextIfNeeded → writeValue
  → didUpdateValueFor → ackMatcher → completeHead
  → enqueue 的 continuation resume
```

---

### 框架 vs 业务 App 边界

| 框架（AppStart BLE） | 业务 App |
|----------------------|----------|
| `BleConfiguration` 结构 | 各产品的具体 configuration 实例 |
| `BleAdvDataParser` 协议 | 吸奶器/体温贴/光疗 parser 实现 |
| `BleAckMatcher` 协议 | 产品专属 ACK 规则（可选） |
| 扫描/连接/写队列/重连 | UI Controller、命令帧组装、页面跳转 |
| `BleSession.shared` | AppDelegate 注册产品 |

业务层**不应**在框架外加 GATT merge、productId 映射、connectResolved 等旁路；协议差异全部收进各自的 `BleConfiguration`。

---

### 常见陷阱

1. **resolve 顺序** — 混扫时先 register 的产品优先；调整注册顺序可改变 resolve 结果
2. **配置快照** — 连接后改 register 不影响已连设备；需重连才用新配置
3. **Notify 双消费** — UI 订阅与 ACK 队列共用 `didUpdateValueFor`
4. **matching 与 parser 重复逻辑** — 推荐 `BleParserValidatedMatchingStrategy` 共用同一 parser，避免两处规则不一致
5. **LocalName** — 优先广播里的 LocalName，`peripheral.name` 可能滞后为空
6. **ACK 误判** — 相同指令重复发 + 超时；设备主动上报与 ACK 同帧头；需自定义 matcher 或业务防抖
7. **扫描 stream 取消** — `onTermination` 自动 `stopScanning()`；页面销毁时取消 Task 即可
8. **连接复用** — 同一 peripheral 已在 connecting/connected/ready 时 `connect` 复用句柄，不会重复 discover

---

### 调试建议

1. 开启目标产品 `debugLog: true`，确认 LogM 已 launch
2. 扫描阶段看 `发现外设` 日志，确认 matching / resolve 命中
3. 连接阶段看 `订阅通知` / `记录写特征`，确认 GATT ready
4. 写入阶段看 `写入指令` → `指令 ACK(notify)` 成对出现
5. 若无 ACK：查 notify 是否订阅、ackMatcher 字节位是否匹配回包、是否被主动上报误匹配

---

## 主要类型

| 类型 | 说明 |
|------|------|
| `BleConfiguration` | 单款产品完整协议 |
| `BleParserValidatedMatchingStrategy` | 推荐扫描匹配（parser + 可选 names） |
| `BlePrefixMatchingStrategy` | 名称前缀 / 厂商数据前缀匹配 |
| `AnyBleAdvDataParser` | 解析器类型擦除 |
| `BleCompositeMatchingStrategy` | 多产品 OR 匹配 |
| `BleDiscovery` | 扫描结果（含 `configuration`、`parsedData`、`displayName`） |
| `BleCentral` | 扫描、连接 |
| `BleSession` | 注册表 + Session |
| `BlePeripheralConnection` | 单设备句柄 |

---

## 文件索引

```
Ble/
├── BleEnums.swift              # 公共类型、错误码
├── BleConfiguration.swift      # 协议配置模型
├── BlePeripheralMatching.swift
├── BleAdvDataParser.swift      # 广播解析 + 推荐匹配策略
├── BleProductRegistry.swift    # 多产品 resolve
├── BleSession.swift            # App 入口
├── BleCentral.swift            # CBCentralManager 封装
├── BleAsyncBroadcastStream.swift
├── BlePeripheralConnection.swift
├── BleGattSetup.swift
├── BleReconnectHandler.swift
├── BleWriteCommand.swift
├── BleWriteCommandQueue.swift
├── BlePriorityQueue.swift
└── BleLogger.swift
```
