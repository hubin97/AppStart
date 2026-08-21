# AppStart Ble 特性拓展迭代文档

> 版本：v1.0 · 2026-08-21  
> 状态：规划（Planning）  
> 关联：`BLE_README.md`（实现细节）、`AGENTS.md`（约束）

---

## 1. 目标与策略

### 1.1 北极星

AppStart Ble 定位为 **IoT / 穿戴类设备的 Lute 协议传输内核**：

- 管：Central 生命周期、扫描匹配、连接状态机、GATT、串行写队列、Notify 路由
- 不管：具体指令语义（C0/F0/B0）、配网状态机、OTA 协议、设备云端同步、Live Activity UI

### 1.2 演进策略

```
先 AppStart 做稳、做通用 → AppTemplate Demo 验收 → 业务 App（如 Momcozy）再接入
```

业务多样性（多机型、配网握手、OTA 协作、埋点副通道）作为 **需求规格输入**，沉淀为框架抽象，**不把业务逻辑下沉进内核**。

### 1.3 不变原则

| 原则 | 说明 |
|------|------|
| 配置跟产品走 | 协议差异收进 `BleConfiguration`，不跟页面走 |
| 连接时快照 | `connect` 时 merge 解析结果；已连设备不受后续 `register` 影响 |
| 单 Central | App 内唯一 `CBCentralManager`，禁止第二套 Central |
| App 回连默认 | 使用 `BleReconnectHandler`；不默认开启 iOS 17 系统 AutoReconnect |
| 业务索引在 App | MAC / deviceId 映射由业务 Coordinator 维护，不进框架 |

---

## 2. 能力分层

```
┌─────────────────────────────────────────────────────────────┐
│ L3 业务状态机    配网流程、机型脚本、云端绑定、OTA SDK 编排   │  App 层
├─────────────────────────────────────────────────────────────┤
│ L2 指令协议      组包/解包、加解密、F0 解析、机型 Profile    │  App 层
├─────────────────────────────────────────────────────────────┤
│ L1 传输队列      串行写 + ACK 等待、超时、Notify 双消费       │  AppStart ✅
├─────────────────────────────────────────────────────────────┤
│ L0 GATT 连接     扫描/连接/发现/订阅/ready 状态机           │  AppStart ✅
└─────────────────────────────────────────────────────────────┘
```

### 2.1 已具备（当前版本）

| 能力 | 说明 |
|------|------|
| 多产品混扫 + resolve | `BleProductRegistry`，register 顺序定案 |
| 全量扫描 + matching 过滤 | 系统层 `serviceUUIDs: nil` |
| 连接状态机 | `connecting → connected → ready` |
| 串行写队列 | `.serialized` + `BleAckMatcher` + 超时 |
| 顺序指令链 | `try await connection.write()` 链式调用，等 ACK 再发下一条 |
| 多设备连接句柄 | `activeConnections` |
| App 层自动重连 | `BleReconnectPolicy` + `BleReconnectHandler` |
| AsyncStream API | 状态 / 扫描 / Notify 订阅 |

### 2.2 配网握手（F0 → FD / B0 / F7）说明

**结论：L1 已支持，L2/L3 在 App 层实现。**

- 框架：`writeQueue: .serialized` + 顺序 `await connection.write(...)` 即可实现「等 ACK 再发下一条」
- App：机型顺序（M9 / M5Pro / V3 等）、F0 解析后发 FD、B0 后再 F7 等 **条件分支**，用 async 脚本编排
- 待补：**加强版 ACK Matcher 示例** + AppTemplate **配网握手 Demo**（见 Release 1）

---

## 3. 明确不做

| 项 | 理由 |
|----|------|
| iOS 17 `CBConnectPeripheralOptionEnableAutoReconnect` 默认开启 | 与 App 回连可能冲突；若业务需要，在 App 层 opt-in 并互斥 |
| 框架内 MAC / deviceId 索引 | iOS 主键是 `CBPeripheral.identifier`；MAC 来自自定义 parser |
| 框架内 F0-F7 配网流程 | 机型差异大，属 L3 业务状态机 |
| JL / Bes OTA 协议实现 | 第三方 SDK；框架只提供协作面 |
| Tuya / Telink Mesh / Meari BLE | 非 Lute 栈，独立 SDK |
| `write(data, channel: .ota)` 类 API | OTA 多为断连 + 换 Configuration 重连；见 §5.3 |
| 完整「N 通道 × N 种写队列」矩阵 | 过度设计；见 §5.2 |

---

## 4. 能力矩阵与优先级

| ID | 能力 | 优先级 | 阶段 | 说明 |
|----|------|--------|------|------|
| **C3** | UUID 匹配正确性 | **P0** | R1 | `CBUUID` 比较 + 单测；必要时 `BleUUID.equivalent` |
| **A3** | 同协议多子型号（动态 GattProfile） | **P0** | R1 | Parser 输出 Profile，`connect` 时 merge 进快照 |
| **S1** | 串行写 + ACK 稳定化 | **P0** | R1 | 误匹配防护、Pump ACK Matcher 示例、配网链 Demo |
| **R1** | 混扫 / 多连接 / 重连打稳 | **P0** | R1 | bugfix、边界测试、文档 |
| **C2** | 可选副通道（analytics） | **P1** | R2 | 主 transport + 副通道 direct write；非 OTA 并行 |
| **O1** | OTA 协作扩展点 | **P2** | R3 | 双 Configuration、suspendReconnect、暴露 peripheral |
| **E1** | State Restoration hook | **P3** | R4 | Live Activity 等特化场景；Momcozy 接入前可不做了 |
| ~~B3~~ | ~~按 MAC 查连接~~ | — | — | **删除**；业务 Coordinator |
| ~~AR~~ | ~~iOS 17 AutoReconnect~~ | — | — | **非默认**；业务 opt-in |

---

## 5. 关键设计决策

### 5.1 重连：仅 App 层，默认不用系统 AutoReconnect

| 方式 | 建议 |
|------|------|
| `BleReconnectHandler` | **默认** |
| iOS 17 AutoReconnect | 不纳入框架默认；与 App 回连同时开启易重复 connect / 状态打架 |
| State Restoration | 与 AutoReconnect 不同；P3 可选 hook，非主线 |

### 5.2 写策略：单连接单主队列 + 可选副通道

| 场景 | 方案 |
|------|------|
| 日常控制（C0/F0/B0） | 主通道 `.serialized` + ACK（**保持现状**） |
| 配网指令链 | 顺序 `await write()`（**保持现状**） |
| 主控制 + 埋点并行（M5 类） | 主通道 serialized + **副通道 `.direct`**（R2） |
| OTA | **独立 connect 会话** + OTA Configuration（R3） |

**不做**：每种 channel 各一套完整 priority 队列矩阵。

### 5.3 OTA：协作面，不实现协议

典型流程：

```
transport Config 连接 → 断开 → ota Config 连接 → 第三方 SDK 写固件
→ 设备重启 → scan → transport Config 连接
```

框架协作点：

| 协作点 | 框架提供 |
|--------|----------|
| 换 GATT 会话 | 独立 `BleConfiguration`（如 `.pumpTransport` / `.pumpOTA`） |
| 原始能力 | `peripheral`、写特征、`write(data)` direct |
| 生命周期 | `suspendReconnect()` / `resumeReconnect()`（OTA 期间） |
| 协议 / 分包 / 进度 | **不提供**（JL / Bes SDK） |

### 5.4 UUID 匹配：CBUUID 一等公民

**最优解**（不照搬业务 App 字符串 slice 逻辑）：

1. Configuration 一律存 `CBUUID`
2. GattSetup 用 `characteristic.uuid == configuredUUID` 比较
3. 补单测：短 UUID、`0000XXXX-...`、`00000000-XXXX-...` 等布局
4. 单测失败时再补 `BleUUID.equivalent(_:_:)`

### 5.5 动态 GattProfile（A3）

同一广播（如 0xAA）不同子型号（V3 vs M9）对应不同 Service UUID：

```swift
// Parser 输出（App 层类型示例）
struct BleGattProfile {
    var serviceUUIDs: [CBUUID]
    var writeCharUUID: CBUUID?
    var notifyCharUUID: CBUUID?
    // optional secondaryChannel for analytics
}

// connect 时：effectiveConfig = baseConfiguration.merged(with: parserProfile)
```

避免为每个 PType 注册多个冲突 Configuration 抢 resolve。

### 5.6 ACK Matcher 推荐（Pump / 0xAA 0x55 协议）

默认 `BleByteAckMatcher(indices: [0, 1, 3])` 可用，配网/控制建议更严：

```swift
// 概念：REQ = AA 55 00 CID …，ACK = AA 55 01 CID …
struct BlePumpAckMatcher: BleAckMatcher {
    func matches(command: Data, response: Data) -> Bool {
        guard command.count > 3, response.count > 3 else { return false }
        return response[0] == 0xAA && response[1] == 0x55
            && response[2] == 0x01      // CT = ACK
            && response[3] == command[3]  // 同 CID
    }
}
```

---

## 6. 分阶段 Release

### Release 1 — GATT 正确性 + 传输稳定（P0）

**目标**：连接/GATT/写队列/配网链可依赖。

**框架**

- [ ] C3：`BleGattSetup` 全面 `CBUUID` 比较 + UUID 等价单测
- [ ] A3：`BleGattProfile` + `connect` merge 进配置快照
- [ ] S1：`BlePumpAckMatcher` 内置示例；写队列 ACK 误匹配加固
- [ ] R1：混扫 resolve 顺序、多连接并发、重连耗尽行为回归
- [ ] 文档：`BLE_README.md` 增补 ACK / 指令链章节

**AppTemplate 验收**

- [ ] 配网握手 Demo：`F0 → (FD) → B0 → (F7)` 一种机型 profile
- [ ] V3 动态 GattProfile Demo（128-bit Service）
- [ ] 连接失败 / 超时 / 重连可视化
- [ ] 双设备并发连接 Demo

**退出标准**

- Demo 全链路无人工干预可跑通
- 核心路径有测试：matching、resolve、ACK 队列、GATT ready、UUID 等价

---

### Release 2 — 可选副通道（P1）

**目标**：主控制 + 埋点并行，不引入 OTA 多通道复杂度。

**框架**

- [ ] C2：`BleConfiguration` 支持 `secondaryChannel`（optional）
  - 仅 `.direct` write
  - 不参与主 ACK 队列
  - Notify 按 UUID / role 路由，避免误匹配主队列 ACK
- [ ] API：`connection.writeSecondary(_:)` 或 `write(_:, role: .secondary)`（二选一，实现时定稿）

**AppTemplate 验收**

- [ ] Mock analytics 副通道：主通道发 C0 同时副通道收 Notify

**退出标准**

- 主队列 ACK 不受副通道 Notify 干扰

---

### Release 3 — OTA 协作（P2）

**目标**：第三方 OTA SDK 以极简方式接入，框架不实现 OTA 协议。

**框架**

- [ ] 文档：OTA 会话切换模式（transport ↔ ota Configuration）
- [ ] `suspendReconnect()` / `resumeReconnect()` on connection 或 session
- [ ] 暴露 `CBPeripheral` + 目标 `CBCharacteristic` 供 SDK 使用（已有，文档化）

**AppTemplate 验收**

- [ ] Mock OTA：断连 → ota Config 连接 → direct write → 断连 → transport 重连（不接 JL/Bes）

**退出标准**

- OTA 模拟页不破坏主链路 reconnect 策略

---

### Release 4 — 特化与 DX（P3，可选）

**目标**：降低业务 App 接入成本；Momcozy 试点前非阻塞。

**框架 / 文档**

- [ ] E1：`BleRestorationHandling` hook（`willRestoreState` 转发，业务注入）
- [ ] 「从零接入新产品」Checklist
- [ ] 可选：`BleConnectionObserver`（states + updates 统一订阅）

**AppTemplate 验收**

- [ ] CozyLink / Phototherapy 完整 Configuration 样例

---

## 7. 框架 vs 业务边界（接入清单）

| AppStart Ble | 业务 App（AppTemplate / Momcozy） |
|--------------|-----------------------------------|
| `BleConfiguration` 结构 | 各产品 Configuration 实例 |
| `BleAdvDataParser` / Profile | Pump/T31/网关 parser |
| `BleAckMatcher` 协议 + 示例 | Pump 等具体 Matcher |
| 扫描 / 连接 / GATT / 写队列 | 配网 Strategy、PumpDevice 指令 |
| `BleSession` | AppDelegate 注册、Coordinator |
| suspendReconnect | OTA / 绑定会话标记 |
| — | MAC ↔ connection 索引 |
| — | F0-F7 机型脚本、加解密 |
| — | JL/Bes OTA SDK |
| — | Live Activity / Recovery Bridge |

---

## 8. 业务 App 接入门槛（Gate）

建议在 **Release 1 + Release 2 完成** 后启动业务试点：

| Gate | 标准 |
|------|------|
| G1 | AppTemplate 配网握手 Demo 稳定 |
| G2 | V3 动态 GattProfile Demo 通过 |
| G3 | 副通道 Demo 不干扰主 ACK（若业务需要埋点） |
| G4 | AppStart 发版 tag，AppTemplate 锁定版本 |
| G5 | 业务 App 单机型 Feature Flag 试点，保留旧栈可回滚 |

试点顺序建议：**控制页 → 配网 → OTA 会话切换 → Live Activity（R4）**。

---

## 9. 与 AppTemplate README 待办映射

| AppTemplate 待办 | 归入 Release |
|------------------|--------------|
| 多产品 Configuration UI | R1 |
| 连接失败 / 超时 / 重连可视化 | R1 |
| 广播解析展示页 | R1 |
| OTA 扩展点 | R3 |
| 连接状态 UI 绑定 | R4 |

---

## 10. 修订记录

| 日期 | 版本 | 说明 |
|------|------|------|
| 2026-08-21 | v1.0 | 初版：基于 Momcozy 业务多样性反推框架演进；明确不做项与优先级 |

---

## 附录 A：Release 时间线（参考）

```text
R1  GATT + 传输稳定     ████████░░░░░░░░  (~6w)
R2  可选副通道           ░░░░████████░░░░  (~4w)
R3  OTA 协作             ░░░░░░░░██████░░  (~3w)
R4  特化 / DX（可选）    ░░░░░░░░░░░░████  (~3w)
    业务 App 试点        ░░░░░░░░░░████████  (R1 后半可并行 Demo)
```

*时间为估算，以 Release 退出标准为准，不以日历承诺。*
