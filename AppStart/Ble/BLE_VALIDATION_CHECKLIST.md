# BLE 功能验证与回归用例

> 适用范围：AppStart BLE 内核与 AppTemplate BLE 示例业务
> 同步日期：2026-08-31
> 建议设备：至少 1 台主 GATT 设备；如有 supplementary Profile，再准备对应型号

## 1. 测试前准备

- [ ] App 启动调用 `BleSession.shared.configure(with: BleProducts.all)`。
- [ ] 目标产品打开 `debugLog`，日志组件已 launch。
- [ ] 清理 App 后首次启动一次，确认蓝牙权限弹窗与授权流程正常。
- [ ] 准备蓝牙开启、关闭、未授权（可重装 App）、设备远离/断电四种环境。
- [ ] 记录目标设备名称、identifier、主/附加 Service UUID。

## 2. 自动化检查

| 编号 | 用例 | 操作 | 预期 |
|------|------|------|------|
| UT-01 | UUID 等价 | 运行 `BleModuleSpec` | 16-bit 与标准 128-bit Base UUID 正确匹配 |
| UT-02 | ACK matcher | 运行 `BleModuleSpec` | 指定字节一致时匹配，不相关上报不误判 ACK |
| UT-03 | GATT merge | 运行 `BleModuleSpec` | parser 可覆盖主 Profile，并正确注入 supplementary Profile |
| UT-03A | 重连策略参数保持 | 构造 `BleReconnectPolicy(enabled:maxAttempts:retryDelay:attemptTimeout:)` | 四个参数保持独立且值不丢失，`retryDelay` 不覆盖 `attemptTimeout` |
| UT-03B | Session 产品配置 | 连续两次调用 `configure(with:)` | 每次整体替换 `configurations`，不累加并保持传入顺序 |
| UT-04 | 重连成功 | mock 前一次失败、第二次返回 ready | 尝试 2 次后收到 `.stopped(.success)` |
| UT-05 | 重连耗尽 | mock 每次失败，`maxAttempts = 2` | 恰好尝试 2 次并收到 `.stopped(.exhausted)` |
| UT-06 | 模块类型检查 | 对 Ble 全部 Swift 源码执行 typecheck | 无编译错误 |
| UT-07 | 广播首事件 | stream 返回后立即 yield（non-replay） | 首个事件可读取，不落入订阅注册竞态窗口 |

自动化现状：UT-01～05（含 UT-03A/03B）、UT-07 已在 `BleModuleSpec.swift` 中实现，其中 UT-04/05 使用 handler 闭包 mock 重连结果，UT-07 覆盖广播流订阅注册竞态。UT-06 属构建检查；scan/connect/GATT 状态机与 write queue 的多数 CoreBluetooth delegate 集成路径仍缺 mock，不能由上述单元测试替代。

## 3. 扫描

| 编号 | 场景 | 操作 | 预期 |
|------|------|------|------|
| SCAN-01 | 正常混扫 | 蓝牙开启，进入发现页 | 已配置产品均可按 matching/resolve 出现；RSSI 可刷新 |
| SCAN-02 | 扫描超时 | 启动 15s 扫描且不手动停止 | stream 在超时后结束，状态流出现 `.stopped` |
| SCAN-03 | 手动停止 | 扫描中退出页面 | 当前 stream 结束，系统扫描停止，无后续发现回调进入页面 |
| SCAN-04 | 新扫描替换旧扫描 | 页面 A 扫描后立即由页面 B 发起扫描 | A stream 结束；B 正常收到结果 |
| SCAN-05 | 旧 stream 延迟取消 | B 已替换 A 后再销毁 A | A 的 `onTermination` 不会停止 B |
| SCAN-06 | 旧 timeout 延迟到达 | A 配短 timeout，B 在 A 到期前替换 A | A timeout 不会停止 B |
| SCAN-07 | 初始化状态 unknown | App 冷启动后立即请求扫描 | 请求等待 Central 到 `.poweredOn` 后开始，扫描窗口从实际开始时计时 |
| SCAN-08 | 蓝牙关闭 | poweredOff 时发起扫描 | stream 明确结束，不永久挂起；`centralStates()` 给出 poweredOff |
| SCAN-09 | 扫描中关闭蓝牙 | 正在扫描时关闭系统蓝牙 | stream 结束并清理会话，可在重新开启后发起新扫描 |

## 4. 连接与 GATT ready

| 编号 | 场景 | 操作 | 预期 |
|------|------|------|------|
| CONN-01 | 正常连接 | 从 `BleDiscovery` 调用 `BleSession.connect` | 状态依次为 connecting → connected → ready |
| CONN-02 | 蓝牙不可用 | poweredOff 时调用 connect | 立即抛 `BleError.bluetoothUnavailable` |
| CONN-03 | 物理连接超时 | 设备断电后连接，使用短 timeout | 抛 `connectionTimeout`，系统挂起连接被取消 |
| CONN-04 | GATT 超时 | 模拟 physical connected 但服务发现不完成 | 总 timeout 仍生效，不永久 await |
| CONN-05 | Notify barrier | 延迟 Notify state 回调 | connect 在确认前不返回，确认后才 ready |
| CONN-06 | 多 Notify barrier | 主 + supplementary Notify 分别确认 | 全部确认后才 ready |
| CONN-07 | Notify 确认早到 | 一个 Notify 先确认，其他 Service 特征后发现 | 早到确认被保留；最终全部满足后 ready |
| CONN-08 | Notify 失败 | `didUpdateNotificationStateFor` 带 error 或 `isNotifying == false` | 抛 `channelSetupFailed`，不进入 ready |
| CONN-09 | 缺写特征 | 配置 write UUID 但设备未暴露 | 抛 `writeCharacteristicNotFound` |
| CONN-10 | 缺 Notify 特征 | 配置 notify UUID 但设备未暴露 | 抛 `channelSetupFailed` |
| CONN-11 | 同设备并发连接 | 同时发起两次 connect | 仅一次底层 connect/GATT；两方返回同一 connection |
| CONN-12 | connected 时再次连接 | GATT 发现中再次调用 connect | 第二方继续等待 ready，不提前返回 |
| CONN-13 | 不同设备并发连接 | 同时连接两台外设 | 两条连接独立推进，registry 各保留一个句柄 |
| CONN-14 | 重连期间禁止旧写 | 意外断开后立即调用 `write` | 抛 `notConnected`，不使用上一链路缓存特征 |
| CONN-15 | 动态 GATT 快照刷新 | 终态后用包含新 parsedData/Profile 的 discovery 再连接 | 复用句柄但使用新 Service/Notify/write UUID |

## 5. 断连与自动重连

| 编号 | 场景 | 操作 | 预期 |
|------|------|------|------|
| RECON-01 | 用户主动断开 | 调用 `disconnectActiveConnection()` | 状态为 userInitiated，不触发自动重连，activeConnection 清空 |
| RECON-02 | nil error 意外断开 | 设备主动断开且系统 error 为 nil | 仍判定 unexpected，并按策略重连 |
| RECON-03 | 完整 ready 才算重连成功 | physical connected 后阻塞 GATT/Notify | 不提前报告 success；单次 attemptTimeout 后失败重试 |
| RECON-04 | 重连成功 | 设备断电后在次数耗尽前恢复 | 同一 connection 句柄回到 ready，状态订阅继续有效 |
| RECON-05 | 重连耗尽 | 设备持续离线 | 尝试次数等于 maxAttempts，最终 timedOut 并从 registry 清理 |
| RECON-06 | 重连期间手动 connect | 自动重连退避期间由用户主动连接 | 复用原句柄并停止旧重连循环，不产生双 delegate/GATT |
| RECON-07 | 用户在重连中断开 | 重连中点击主动断开 | 当前 attempt/等待者取消，后续不再重连 |
| RECON-08 | 重连进度状态 | 配置 maxAttempts=3，设备保持离线 | 依次收到 reconnecting(1/3)、(2/3)、(3/3)，单次失败不短暂显示最终失败 |

## 6. 写入、ACK、MTU 与背压

| 编号 | 场景 | 操作 | 预期 |
|------|------|------|------|
| WRITE-01 | ready 前写入 | connecting/connected 状态调用 `write` | 抛 `notConnected` |
| WRITE-02 | direct 短写 | ready 后发送小于 MTU 的数据 | 单次 `writeValue`，成功返回 nil |
| WRITE-03 | serialized ACK | 连续发送两条命令 | 同时仅一条 in-flight；首条 ACK 后才发送第二条 |
| WRITE-04 | ACK 超时 | 设备不返回匹配 Notify | 抛 `writeTimeout`，队列继续处理下一条 |
| WRITE-05 | withResponse 失败 | 系统 write 回调返回 error | 抛 `writeFailed` |
| WRITE-06 | 普通写超过 MTU | `write` 发送大于 `maximumWriteValueLength` 的数据 | 抛 `writeDataTooLong`，不静默拆协议帧 |
| WRITE-07 | 显式分片 | 用 `writeChunked` 写入大数据 | 每片不超过当前 maximum；顺序完整，最终字节数一致 |
| WRITE-08 | withoutResponse 背压 | 持续写到 `canSendWriteWithoutResponse == false` | 暂停发送；收到 `peripheralIsReady` 后继续，无丢片 |
| WRITE-09 | 背压等待中断连 | capacity waiter 挂起时断开 | waiter 抛 `cancelled`，无 continuation 泄漏 |
| WRITE-10 | supplementary 写 | 指定附加 write UUID | 使用统一 MTU/背压路径，但不进入主 ACK 队列 |

## 7. 业务层回归

- [ ] 发现页：扫描、停止、刷新、选择设备绑定均正常。
- [ ] 已绑定列表：下拉混扫，只连接列表内设备；退出页面停止扫描。
- [ ] Pump：F0/FD/F7 握手成功，产品 ACK matcher 不受影响。
- [ ] Console：状态、主 Notify、附加 Notify、发送指令、主动断开均正常。
- [ ] `BleAppConfiguration.setup()` 重复调用后配置列表不累加，resolve 顺序稳定。
- [ ] 产品名称直接来自 `connection.configurationSnapshot`，动态 GATT 型号仍展示正确产品。
- [ ] `discovery.parsedData(as:)` 类型不匹配时返回 nil，不崩溃。

## 8. 通过标准

- [ ] P0/P1 用例无阻塞、无重复 continuation resume、无崩溃。
- [ ] 同设备任何时刻只有一个有效 connection attempt。
- [ ] 所有 connect 成功返回时状态必为 `.ready`。
- [ ] 所有非主动断连均不会被误标为 userInitiated。
- [ ] 大数据写入无超过 MTU 的单片，背压场景无丢片。
- [ ] 页面退出后无继续刷新 UI、无遗留扫描 Task。
- [ ] 对外 API 与文档一致；`central.stopScanning` 直接调用仍可用。

## 9. 文档契约与已知限制验收

| 编号 | 核查项 | 验收标准 |
|------|--------|----------|
| DOC-01 | 四层职责与状态所有权 | `BLE_ARCHITECTURE_REVIEW.md` 保持 Configuration → Session → Central → Connection 四层，并说明扫描、连接与流的并发边界 |
| DOC-02 | 配置与业务 API | 文档与源码一致：`configure(with:)` 整体替换 `configurations`，`parsedData(as:)` 为 typed accessor，`setAsActive` 只控制主连接选择 |
| DOC-03 | 错误契约 | 蓝牙不可用连接抛 `bluetoothUnavailable`；非 ready 写入抛 `notConnected` |
| LIMIT-01 | descriptor 结果 | 接受 `discoverDescriptors` 可触发发现但当前不消费、不发布结果；需要结果流前不得宣称完整支持 |
| LIMIT-02 | priority | 接受 serialized write queue 保留 priority/order，当前不简化为纯 FIFO |
| LIMIT-03 | 阶段 3 | Service Changed、State Restoration、OTA `suspendReconnect` / `resumeReconnect` 仅为设计，不作为当前版本能力验收 |
| LIMIT-04 | 自动化边界 | UT-04/05/07 已自动化；scan/connect/GATT/write queue 集成 mock 与本清单未勾选真机项仍须执行后才能签收 |
