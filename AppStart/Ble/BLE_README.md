# Ble 模块

基于 Swift Concurrency（async/await + AsyncStream）的 CoreBluetooth 封装，支持多页面共享连接、**多产品协议**并存。

> **文档定位**：本文是当前 BLE 实现的事实来源（source of truth），以 canonical 路径 `AppStart/Ble` 下源码为准；路线与设想不覆盖本文记录的当前行为。
>
> **相关文档**：特性拓展路线见 [`BLE_ROADMAP.md`](BLE_ROADMAP.md)，架构评估见 [`BLE_ARCHITECTURE_REVIEW.md`](BLE_ARCHITECTURE_REVIEW.md)，回归基线见 [`BLE_VALIDATION_CHECKLIST.md`](BLE_VALIDATION_CHECKLIST.md)。

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
       ↓ configure(with:)
BleSession（产品协议配置 + activeConnection）
       ↓
BleCentral（唯一 CBCentralManager）
       ↓
BlePeripheralConnection（状态机 + GATT + 写队列 + 重连）
```

| 层级 | 职责 |
|------|------|
| `BleConfiguration` | 单款产品完整协议快照 |
| `BleSession.configure(with:)` | App 启动配置会话支持的全部产品协议 |
| `BleCentral.scan(products:)` | 混扫；**系统层不按 Service UUID 过滤** |
| `BleDiscovery.configuration` | 混扫 resolve 命中的产品配置（尚未合并广播动态 GATT） |
| `BleDiscovery.effectiveConfiguration` | `configuration + parsedData` 动态 GATT merge 后的连接配置 |
| `BlePeripheralConnection` | 连接时绑定有效配置快照，后续 Session 配置变更不影响已连设备 |

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
    // 方式 A：GATT 写在 Configuration（静态产品）
    static let pump = BleConfiguration(
        matching: BleParserValidatedMatchingStrategy(parser: MyPumpParser()),
        gattProfile: BleGattProfile(
            serviceUUIDs: [CBUUID(string: "AF00")],
            writeCharUUID: CBUUID(string: "AF01"),
            notifyCharUUID: CBUUID(string: "AF02")
        ),
        writeQueue: .serialized(
            ackMatcher: BleByteAckMatcher(indices: [0, 1, 3]),
            defaultTimeout: 3,
            order: .descending
        ),
        parser: MyPumpParser(),
        debugLog: true,
        logTag: "[Ble/Pump]"
    )

    // 方式 B：GATT 由 parser 的 BleProvidesGattProfile 在 connect 时 merge（同协议多子型号）
    // static let pump = BleConfiguration(matching: ..., parser: MyPumpParser(), ...)

    static let all: [BleConfiguration] = [pump]
}
```

推荐匹配策略：`BleParserValidatedMatchingStrategy`（parser 解析成功即命中；可选 `names` 做 LocalName 前置过滤）。

### 2. 配置 Session

```swift
// 每次调用整体替换；数组顺序决定混扫 resolve 优先级
BleSession.shared.configure(with: BleProducts.all)
```

### 3. 扫描

```swift
Task {
    for await discovery in BleSession.shared.scanAllProducts(timeout: 20) {
        let productConfig = discovery.configuration
        let effectiveConfig = discovery.effectiveConfiguration
        let parsed: MyPumpParser.ParsedData? = discovery.parsedData(as: MyPumpParser.ParsedData.self)
        // 展示可用产品配置；连接/GATT 判断必须用 effectiveConfiguration
    }
}
```

单产品：

```swift
for await discovery in BleSession.shared.scan(configuration: BleProducts.pump, timeout: 20) { ... }
```

### 4. 连接

```swift
let connection = try await BleSession.shared.connect(
    discovery: discovery,
    timeout: 15,
    setAsActive: true
)
// activeConnection 已由 connect 自动赋值，无需再手动设置
```

`connect(discovery:)` 内部只使用 `discovery.effectiveConfiguration`：先取 resolve 得到的 `configuration`，再把 `parsedData` 提供的主 / 附加 GATT 动态 merge 成连接快照；无法生成时抛 `BleError.configurationNotResolved`。App 层请只走此入口，不要把 `discovery.configuration` 直接传给 `BleCentral.connect`，否则会丢失子型号动态 GATT。

`setAsActive` 默认为 `true`；多设备并行连接时传 `false`，不会覆盖现有 `activeConnection`。可用 `BleSession.shared.connection(for:)` 查询某个外设已登记的连接。

### 5. 读写与状态

```swift
for await state in await connection.states() { ... }
for await update in await connection.characteristicUpdates() { ... }
try await connection.write(data)
let maximum = connection.maximumWriteValueLength(for: .withoutResponse)
try await connection.writeChunked(largeData) // 仅 OTA/批量数据显式选择分片
BleSession.shared.disconnectActiveConnection()
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
  → discovery.effectiveConfiguration
       = configuration.merged(withParsedData: parsedData)
  → BleCentral.connect（绑定有效配置快照）
  → 物理连接 → discoverServices → discoverCharacteristics
  → 订阅 Notify 并等待 `didUpdateNotificationStateFor` 确认 → 定位 writeChar → .ready
  → waitUntilReady() 返回；activeConnection 已赋值
```

状态机：`connecting → connected → ready`；自动重连为 `reconnecting(attempt:maximumAttempts:)`；失败 `failed` / `timedOut`；断开 `disconnected`。

**Notify barrier：** `connect` 成功不等于物理链路已连。主 Profile 与所有 supplementary Profile 配置的 Notify 都必须找到，且各自收到 `didUpdateNotificationStateFor` 成功确认后才进入 `.ready`；任一失败都不会提前返回可用连接。

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
| App 入口 | `BleSession.swift` | configure / scan / connect |
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
| `parsedData` | `advParser` 解析结果（`Any?`）；公开 `parsedData(as:)` 提供类型安全读取 |
| `configuration` | 混扫 resolve 命中的产品配置；临时扫描未配置产品时为 nil |
| `effectiveConfiguration` | `configuration` 与 `parsedData` 动态 GATT merge 的结果；连接链唯一配置来源 |

**`BlePeripheralState`** — 连接状态机：

```
connecting → connected → ready(BleChannelReadyInfo)
         ↘ failed / timedOut
         ↘ disconnected(userInitiated | unexpected)
                    ↘ reconnecting(attempt, maximumAttempts) → connected → ready
```

- `connecting`：`centralManager.connect` 已调用，物理连接未完成
- `reconnecting`：配置启用自动重连后，公开当前重试次数与最大次数
- `connected`：物理连接 OK，GATT 发现进行中
- `ready`：写特征已定位、全部目标 Notify 已确认订阅，可 `write`
- `connect()` 的 `await` 在 `.ready` 时 resume；总超时覆盖物理连接 + GATT + Notify 确认

**`BleScanState`** — 扫描生命周期：`.started` 表示底层 `startScanning` 已调用，`.stopped` 表示超时、手动停止、stream 取消或被新扫描替换后停止。

**`BleReconnectPhase` / `BleReconnectResult`** — 重连循环内部阶段：`.started`；结束时为 `.stopped(.success)` 或 `.stopped(.exhausted)`。业务进度以公开连接状态 `.reconnecting(attempt:maximumAttempts:)` / `.ready` / `.timedOut` 为准；当前没有独立公开的重连 phase stream。

**`BleCharacteristicUpdate`** — Notify 推送，供 UI 订阅；写队列也会消费同一路径。

**`BleDiscovery.displayName`** — 扫描展示名（LocalName → `peripheral.name`），不参与 matching / yield 门禁。

**`BleError`** — 按场景分类：

| 错误 | 触发点 |
|------|--------|
| `bluetoothUnavailable(CBManagerState)` | 非 `.poweredOn` 时连接；扫描因 API 为非 throwing stream，会结束并由 `centralStates()` 报告具体状态 |
| `notConnected` | 未 ready、断开或重连中调用写入 |
| `writeCharacteristicNotFound` | GATT 未找到主 writeChar，或 `write(_:to:)` 的 UUID 不存在 / 不可写 |
| `connectionTimeout` | `BleSession.connect` 默认 15s（或自定义 `timeout`）内未到 `.ready` |
| `connectionFailed(Error?)` | `didFailToConnect`，或意外断连导致本轮 ready 等待失败 |
| `channelSetupFailed(Error)` | Service / Characteristic 发现或 Notify barrier 失败；底层非 `BleError` 会映射到此 case |
| `writeTimeout` | serialized 写入在发送完成后、指定 timeout 内未匹配 Notify ACK |
| `writeFailed(Error)` | `.withResponse` 的 `didWriteValueFor` 返回错误，或队列底层发送失败 |
| `writeDataTooLong(actual:maximum:)` | 普通 `write` 超过对应 write type 的单次上限，或分片上限无效 |
| `cancelled` | 断连 / 重配时清空写队列、取消 withoutResponse 容量等待，或内部任务失效 |
| `configurationNotResolved` | `connect(discovery:)` 无法生成 `effectiveConfiguration` |

以上为当前 `BleError` 的 **11 个 case**。注意 GATT 缺主 write 特征会直接保留 `writeCharacteristicNotFound`，其余普通 GATT 错误才包装为 `channelSetupFailed`。

---

### 2. `BleConfiguration.swift` — 单产品协议快照

一款产品的**全部蓝牙约定**集中在一个 struct 里，连接时拷贝一份快照，后续 Session 配置变更不影响已连设备。

#### 产品配置、有效配置与连接快照

1. `BleDiscovery.configuration`：resolve 命中的**产品配置**，适合产品识别 / 展示，不含本条广播决定的动态 GATT。
2. `BleDiscovery.effectiveConfiguration`：把 `parsedData as? BleProvidesGattProfile` overlay 到主 Profile，并用 `BleProvidesSupplementaryGattProfiles` 提供的列表替换附加 Profile。
3. `connection.configurationSnapshot`：实际建链时冻结的**有效配置**。ready 连接不受后续 Session 配置变化影响；终态句柄由新 discovery 再连接时才刷新。

因此连接路径固定为 `BleSession.connect(discovery:) → discovery.effectiveConfiguration → BleCentral.connect`；业务层不得直接用 `discovery.configuration` 建链。

| 字段 | 扫描阶段 | 连接阶段 |
|------|----------|----------|
| `matching` | ✅ 过滤广播 | — |
| `advParser` | ✅ 解析 MAC 等 | — |
| `gattProfile` | ❌ **不用于系统 scan 过滤** | ✅ discoverServices / discoverCharacteristics |
| `supplementaryGattProfiles` | — | ✅ 附加 discover / subscribe（不进主 ACK 队列） |
| `writeQueue` | — | ✅ direct 或 serialized |
| `reconnect` | — | ✅ 自动重连策略 |
| `debugLog` / `logTag` | — | ✅ 日志开关与 tag |

**`BleWriteQueueConfiguration`：**

- `.direct` — 直接 `writeValue`，不等待 ACK，`write()` 立即返回
- `.serialized(ackMatcher, defaultTimeout, order)` — 串行队列，一条 in-flight，Notify 或 writeResponse 确认后发下一条

**`BleAckMatcher` / `BleByteAckMatcher`：**

- 写队列**只**调用 `ackMatcher.matches(command:response:)`，不在传输层做 payload 相等/heuristic 过滤
- **ACK vs 设备主动 Notify 的区分**由 App 层 Matcher 完成（如 Pump 要求 `byte[2]==0x01`）
- `BleByteAckMatcher`：按字节下标比对（默认 `[0, 1, 3]`），**仅示例**；弱匹配无法区分 REQ 形上报
- 产品专属 Matcher 在 **App 层** 实现；完整产品示例见 [AppTemplate BLE 文档](../../../AppTemplate/AppTemplate/Modules/Main/Func/BLE/Support/BLE_README.md)

**串行写 + `await connection.write()`** — 等 ACK 再发下一条（指令链在 App 层编排）：

```swift
// .serialized 模式：每条 write 排队，Matcher 匹配 Notify 后 resume
if let ack = try await connection.write(stepAData) {
    if shouldContinue(with: ack.response) {   // App 层解析，框架不管语义
        _ = try await connection.write(stepBData)
    }
}
```

- `write()` 返回 `BleWriteAck?`（`request` / `response`）；`.direct` 模式为 `nil`
- `timeout` 可 per-call 传入；省略则用 configuration 的 `defaultTimeout`
- 顺序、条件分支、组包/解包均在 App 层用 `async` 串联；框架只保证串行与 ACK 匹配

**附加 GATT（R2）与动态 GattProfile（connect merge）**

Parser 解析结果按需实现：

| 协议 | 用途 |
|------|------|
| `BleProvidesGattProfile` | 主通道 overlay merge（如 V3 → extended） |
| `BleProvidesSupplementaryGattProfiles` | 子型号附加通道（如 M5 0x07 → secondary） |

```swift
BleSession.shared.configure(with: [
    BleConfiguration(
        gattProfile: primaryProfile,  // 产品级默认；子型号由 parser overlay
        // matching / writeQueue / parser ...
    )
])

let connection = try await BleSession.shared.connect(discovery: discovery)
// 内部：discovery.effectiveConfiguration merge 主 + 附加 GATT

_ = try await connection.write(c0Data)

// 附加 Notify（App 层按 UUID 过滤；不进主 ACK 队列）
for await update in await connection.characteristicUpdates(matching: secondaryNotifyUUID) {
    // 解析 update.data
}
```

- **静态产品**：产品配置中写死 `gattProfile`
- **动态子型号**：产品配置提供默认值 + parser 实现上述协议（需 connect 时有 parsedData）
- `supplementaryGattProfiles`：仅 discover / subscribe；附加 Notify 不参与主 `write(_:)` ACK

**控制面 / 数据面（写策略）**

| 面 | API | ACK 队列 |
|----|-----|----------|
| 控制面（主通道） | `write(_:)` | ✅ serialized 时匹配主 Notify |
| 数据面 / 附加写 | `write(_:to:)` | 不进主 ACK（直接 writeValue） |
| 裸 GATT | `peripheral.writeValue(...)` | 框架不介入 |

`write(_:to:)` 按已发现 GATT 特征 UUID 查找；目标即主 write 时与 `write(_:)` 相同，否则不占用控制面队列。

工具类型：`BleGattProfile`、`BleUUID.matches`（16-bit ↔ 128-bit Base UUID 等价）

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

// resolve = 按 configurations 顺序取第一个命中的 configuration（定案：用哪款 advParser / GATT）
products.resolve(peripheral:advertisementData:)
```

| 机制 | 时机 | 规则 | 用途 |
|------|------|------|------|
| `compositeMatching` | 混扫 `scan(products:)` 合并 matching | 任一产品 matching 命中 | 软件层 OR 过滤（系统 scan 仍全量） |
| `resolve` | `handleDiscovery` 每条广播 | **configurations 中位置靠前者优先** | 写入 `BleDiscovery.configuration`，决定 parser 与连接协议 |

**关键规则：**

- 两款产品 matching 同时命中 → **`configurations` 中位置靠前者优先**
- resolve 结果写入 `BleDiscovery.configuration`，连接时再经 `effectiveConfiguration` 动态 merge；无需 App 猜产品类型或自行 merge
- 无 productId 字符串；区分产品靠 `configuration` 引用或 `logTag` / `parsedData` 类型

---

### 6. `BleSession.swift` — App 层唯一推荐入口

薄封装，不做 CoreBluetooth 细节：

| API | 作用 |
|-----|------|
| `configurations` | 当前会话支持的全部产品协议配置；只读，数组顺序决定 resolve 优先级 |
| `configure(with:)` | 整体替换会话配置；不追加、不自动去重，单产品与多产品使用同一入口 |
| `scan(configuration:)` | 扫单款产品 |
| `scan(at:)` | 按 `configurations` 下标扫描 |
| `scanAllProducts()` | 混扫 `configurations` 中的全部产品 |
| `stopScanning()` | 停止当前扫描，业务层无需下探 Central |
| `connect(discovery:timeout:setAsActive:)` | 从扫描结果连接（**App 唯一推荐入口**）；绑定 `effectiveConfiguration`，默认 15s、默认设为主连接 |
| `connection(for:)` | 按 `CBPeripheral.identifier` 查询 Central registry 中的连接 |
| `disconnectActiveConnection()` | 主动断开并清空当前主连接 |

跨页面共享：`activeConnection` + `central.activeConnections`。

阶段 2 同时公开：

- `connection.configurationSnapshot`：读取建链时冻结的有效配置。
- `discovery.parsedData(as:)`：类型不匹配返回 nil，不做强转崩溃。
- `central.centralStates()`：`CBManagerState` replayLatest 状态流。
- `central.scanStates()`：`BleScanState.started / stopped` replayLatest 状态流。

`setAsActive: false` 仅控制 Session 的主连接引用，不改变 Central registry；适用于多设备连接。

---

### 7. `BleCentral.swift` — CoreBluetooth 中枢

**单例 `BleCentral.shared`**，持有一个 `CBCentralManager`，所有扫描/连接经此出入。

#### 扫描会话（一次 `scan()` 生命周期，带 token）

| 字段 | 作用 |
|------|------|
| `ScanSession.id` | 会话 token；`onTermination` / 超时仅停止匹配 token 的会话 |
| `ScanSession.continuation` | 向 AsyncStream 消费方 yield |
| `ScanSession.products` | 多产品列表，供 resolve |
| `ScanSession.configuration` | 本轮 matching 用的配置（单产品或 composite） |
| `isScanning` | 是否正在 CBCentralManager 扫描 |
| `discoveredDevices` | 本轮缓存；同 identifier 原地更新，并多次 yield 以刷新 RSSI |

新 `scan()` 会 finish 旧 stream 并替换会话；旧 stream 取消或超时不得影响新会话。

#### `handleDiscovery` 完整链路

```
didDiscover
  → 产品扫描：activeScanSession.products.resolve()，失败则丢弃
  → 临时扫描：matching.shouldConnect()，失败则丢弃
  → resolvedConfiguration.advParser 解析广播（失败 parsedData = nil）
  → 构造 BleDiscovery → 更新 discoveredDevices → yield
  → 仅首次发现打日志（优先 parsedData.mac，否则 parsedData 字符串）
```

#### 为何 `scan(products:)` 传 `serviceUUIDs: nil`

系统层按 Service UUID 过滤时，很多设备广播里不带目标 Service，会被漏扫。框架选择**全量 scan + matching 软件过滤**。

#### 连接 `connect(to:configuration:timeout:)`

1. 同 peripheral 并发 connect 共享同一 in-flight Task
2. 若 registry 里已有 connecting/connected 的连接 → 复用并 `waitUntilReady()`
3. 若已有 ready → 直接返回
4. 否则 `makeConnection` 创建 `BlePeripheralConnection`（绑定配置快照；首次调用的 configuration / timeout 生效）
5. `startConnectionTimeout`（覆盖物理连接 + GATT + Notify 确认；App 默认 15s）
6. `performConnect` → Delegate `didConnect` → GATT → Notify 确认 → `waitUntilReady()`
7. 超时抛 `BleError.connectionTimeout` 并 disconnect

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

#### 并发与线程模型

- `BleAsyncBroadcastStream` 本身是 actor；订阅注册、latest 缓存与 continuation 字典都在 actor 内串行，非 replay Notify 也在 stream 返回前完成注册。
- `BleCentral.connectTasks` 只用 `NSLock` 保护很短的同设备 in-flight Task 注册 / 移除；同一 peripheral 的并发调用共享一个 Task，真正 connect 流程切到 `@MainActor`。
- CoreBluetooth Central delegate 回调统一用 `Task { @MainActor in ... }` 转发；扫描会话创建、替换、停止和状态迁移也在 MainActor 路径推进。
- `BleWriteCommandQueue` 用独立锁保护优先队列、单条 in-flight、timeout Task 与 continuation；`sendingRequestID` 同时充当等待传输许可期间的背压门闩，避免重复发送。
- `.withoutResponse` 容量等待者由 `writeCapacityLock` 保护；`peripheralIsReady(toSendWriteWithoutResponse:)` 恢复等待者，取消 / 断连则以 `cancelled` 结束。
- **整体 `BleCentral` / `BleSession` / `BlePeripheralConnection` 当前未标注 `@MainActor`**，以保持现有同步公开 API 兼容；不能把「delegate 在 MainActor 转发」误写成「整个模块 MainActor 隔离」。

#### 公开状态流总览

```
蓝牙：centralStates()
  unknown / resetting / unsupported / unauthorized / poweredOff / poweredOn

扫描：scanStates()
  .started → .stopped

连接：connection.states()
  .connecting → .connected → .ready
             ↘ .failed / .timedOut / .disconnected

重连（同一 connection 状态流）：
  .disconnected(.unexpected) → .reconnecting(n/max)
  → .connected → [GATT + Notify barrier] → .ready
  → 下一次 .reconnecting，或最终 .timedOut

写入（无独立公开状态 stream）：
  ready → MTU 校验 → direct / serialized 入队
  → withoutResponse 容量门禁 → writeValue
  → Notify ACK / writeResponse / timeout / cancelled
```

蓝牙、扫描、连接三类状态流均 `replayLatest`，新订阅者先收到最近状态；`characteristicUpdates()` 为非 replay 数据流。写入结果由每次 `await write` 返回 / 抛错表达，不存在独立写状态流。重连循环的单次连接失败 / 单次 attempt timeout 会被 `isAutoReconnecting` 抑制，不短暂发布 `.failed` / `.timedOut` 终态；业务只看到尝试进度，成功时 `.ready`，全部耗尽后才 `.timedOut`。

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
  → 等待全部目标 Notify 的 `didUpdateNotificationStateFor` 确认
  → finishGattSetup              // writeChar 赋值，状态 → ready
  → completeWaitingForReady()    // 保存 attempt 终态并 resume 全部等待者
```

#### 写入 `write(_:)` / `write(_:to:)`

- **主通道**：`write(_:)` → 就绪时缓存的主 `writeChar`；serialized 时等主 Notify ACK
- **指定特征**：`write(_:to:)` → 已发现的 `peripheral.services` 中按 UUID 查找（`BleUUID.matches`）
- 目标即主 write → 与 `write(_:)` 相同（可走写队列）
- 其它 UUID → 不进主 ACK 队列，但仍统一执行 ready、MTU 与 withoutResponse 背压检查
- `maximumWriteValueLength(for:)` 按 `.withResponse` / `.withoutResponse` 查询 CoreBluetooth 当前链路上限（通常由协商 MTU 推导，两个 write type 可能不同）
- 普通 `write` 超过对应上限时抛 `writeDataTooLong`，不会静默拆分协议帧
- OTA/批量数据显式调用 `writeChunked`，按当前上限顺序分片；该 API 不进入协议 ACK 队列
- `.withoutResponse` 在 `canSendWriteWithoutResponse == false` 时挂起，收到 `peripheralIsReady` 才继续；断连 / Task 取消会释放等待者

#### Notify 双消费（重要）

```swift
didUpdateValueFor
  → updateBus.yield()              // UI / 业务订阅
  → writeQueue?.handleCharacteristicUpdate()  // ACK 匹配
```

改 Notify 处理逻辑时必须兼顾两路：UI 需要全量推送，队列只认 `ackMatcher` 判定为 ACK 的包。

#### 断开

- `disconnect()` 设 `userInitiatedDisconnect = true`，不触发重连
- 只有该标记判定主动断开；CoreBluetooth `error == nil` 仍可能是外设主动断开
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
- 配置了 `gattProfile.writeCharUUID` 但未找到 → `writeCharacteristicNotFound`

---

### 11. `BleReconnectHandler.swift` — 自动重连

Task 驱动的轮询，**不是** UI Controller：

```
notifyUnexpectedDisconnect / notifyConnectFailed
  → runLoop: 调用一次完整 reconnect（physical + GATT + Notify ready）
  → attempt 失败后等待 interval，再发起下一次
  → 完整 ready → notifyConnected → stop
  → 达 maxAttempts → onPhaseChange(.exhausted) → 连接状态 timedOut
```

- `notifyUserDisconnect()` → 设 flag + stop，不再重连
- 每次 attempt 受 `BleReconnectPolicy.attemptTimeout` 限制
- 重连成功后 `notifyConnected()` 重置 attempts
- `.started / .stopped(.success|.exhausted)` 由 `BleReconnectPhase` / `BleReconnectResult` 表达，当前供连接内部协调；公开 UI 订阅使用 `connection.states()`
- 自动重连期间抑制单次 attempt 的 `.failed` / `.timedOut`，避免 UI 在重试间隙误判最终失败；只有耗尽才发布 `.timedOut`

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
  → withoutResponse 无容量：等待 peripheralIsReady（此时尚不计 ACK timeout）
  → 真正 writeValue 后启动 ACK timeout
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
- `BleCentral.syncLogger(from:)` 在 Session 配置、scan / connect 时合并多产品 logTag

**前置条件：** App 启动时 `LogM.shared.setup(...).launch()`，否则看不到日志。

---

### 端到端调用链

#### 扫描 → 连接

```
App: BleSession.configure(with: products)
App: for await d in scanAllProducts()
  → BleCentral.scan(products:)
  → startScanning(serviceUUIDs: nil)
  → didDiscover → handleDiscovery → yield(d)

App: try await connect(discovery: d)
  → d.effectiveConfiguration
      = d.configuration?.merged(withParsedData: d.parsedData)
  → BleSession.connect → BleCentral.connect
  → BlePeripheralConnection.waitUntilReady()
  → didConnect → GattSetup → 全部 Notify 确认 → .ready
  → BleSession 按 setAsActive 决定是否赋值 activeConnection
```

#### 写入（serialized）

```
App: try await connection.write(c0Data)
  → writeQueue.enqueue
  → processNextIfNeeded
  → withoutResponse 容量门禁 → writeValue → 启动 ACK timeout
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
| `BleSession.shared` | App 启动配置全部产品协议 |

业务层**不应**在框架外加 GATT merge、productId 映射、connectResolved 等旁路；协议差异全部收进各自的 `BleConfiguration`。

---

### 扩展指南

新增产品或子型号时，沿现有扩展点组合，不修改 Central / Connection 稳定主链：

1. 实现 `BleAdvDataParser`，把广播解析为产品自己的强类型数据；优先用 `BleParserValidatedMatchingStrategy` 复用同一解析规则做 matching。
2. 创建 `BleConfiguration`，集中配置主 GATT、supplementary GATT、写队列、重连和日志；在 App 启动用 `configure(with:)` 一次性配置全部产品协议。
3. 子型号由广播决定 UUID 时，让解析结果实现 `BleProvidesGattProfile`；有附加 Service 时实现 `BleProvidesSupplementaryGattProfiles`。框架会在 `effectiveConfiguration` 中 merge。
4. 产品有协议 ACK 时，在 App 层实现专属 `BleAckMatcher`；不要把 CID、CT、序列号等业务规则写入内核。
5. 页面只消费 `scanAllProducts` / `connect(discovery:)` / 状态流 / Notify 流；多设备连接用 `setAsActive: false` 与 `connection(for:)` 管理句柄。
6. 大数据传输先选目标 write type，再读 `maximumWriteValueLength(for:)`；只有明确允许拆帧的协议才调用 `writeChunked`。

### 当前已知限制

- **Service Changed 未处理**：没有实现 `didModifyServices` 后的原地 GATT 重发现；固件升级导致服务变化时需断开并重新扫描 / 连接。
- **State Restoration 未实现**：未配置 CoreBluetooth restoration identifier，也不处理系统终止后的 Central / Peripheral 恢复。
- **Descriptor 结果未发布**：`discoverDescriptors = true` 只调用 `discoverDescriptors(for:)`；当前没有 descriptor delegate 消费、缓存或公开结果流。
- **无 OTA 协议实现**：已有 MTU、显式分片和 withoutResponse 背压底座，但不包含 JL / Bes 等厂商 OTA 状态机、校验、断点续传或升级期重连协调。
- **无 Mesh / BLE Audio**：不实现 Tuya / Telink 等 BLE Mesh，也不覆盖 BLE Audio；它们不是本 GATT 控制内核的透明扩展。

上述能力若进入需求，应先在 App / 产品层确认协议边界；确属通用传输能力后再扩展内核，避免把单产品流程下沉。

---

### 常见陷阱

1. **resolve 顺序** — 混扫按 `configurations` 数组顺序匹配；调整顺序可改变 resolve 结果
2. **配置快照** — `configuration` 是产品配置，`effectiveConfiguration` 才是连接输入，`configurationSnapshot` 是建链冻结结果；连接后重新配置 Session 不影响已连设备
3. **Notify 双消费** — UI 订阅与 ACK 队列共用 `didUpdateValueFor`
4. **matching 与 parser 重复逻辑** — 推荐 `BleParserValidatedMatchingStrategy` 共用同一 parser，避免两处规则不一致
5. **LocalName** — 优先广播里的 LocalName，`peripheral.name` 可能滞后为空
6. **ACK 误判** — 使用弱默认 `BleByteAckMatcher`；设备主动 REQ 形上报与写应答同 CID；App 层实现专属 `BleAckMatcher`（如 Pump CT=ACK）
7. **扫描 stream 取消** — `onTermination` 按 session token 停止；新 scan 会替换旧 scan；页面销毁时取消 Task 即可
8. **连接复用** — 同一 peripheral 并发 connect 共享 in-flight Task；connecting/connected 时 await 同一 ready 结果，不会重复 discover

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
| `BleByteAckMatcher` | 按字节下标 ACK 匹配 |
| `BleGattProfile` | 连接时 GATT 覆盖（子型号动态 UUID） |
| `BleUUID` | CBUUID 等价比较 |
| `BlePrefixMatchingStrategy` | 名称前缀 / 厂商数据前缀匹配 |
| `AnyBleAdvDataParser` | 解析器类型擦除 |
| `BleCompositeMatchingStrategy` | 多产品 OR 匹配 |
| `BleCharacteristicUpdate` | Notify 特征值变更 |
| `BleWriteAck` | 串行写 ACK 结果（request + response） |
| `BleDiscovery` | 扫描结果（含 `effectiveConfiguration`、typed parsedData、displayName） |
| `BleScanState` | 扫描 started / stopped 状态 |
| `BleReconnectPhase` / `BleReconnectResult` | 重连循环阶段与结果 vocabulary |
| `BleCentral` | 扫描、连接 |
| `BleSession` | 产品协议配置 + Session |
| `BlePeripheralConnection` | 单设备句柄 |

---

## 文件索引

```
Ble/
├── BLE_README.md               # 实现细节、代码走读（本文档）
├── BLE_ROADMAP.md              # 特性拓展迭代规划
├── BLE_ARCHITECTURE_REVIEW.md  # 当前架构与市场场景评估
├── BLE_VALIDATION_CHECKLIST.md # 功能验证与回归基线
├── AGENTS.md                   # 模块约束补充
├── BleEnums.swift              # 公共类型、错误码
├── BleConfiguration.swift      # 协议配置模型
├── BleGattProfile.swift          # 动态 GATT merge
├── BleUUID.swift                 # UUID 等价比较
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
