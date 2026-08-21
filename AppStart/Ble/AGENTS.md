# Ble 模块补充约定

本文件补充根目录 `AGENTS.md`，仅在改 Ble 时加强约束。权威细节以 `BLE_README.md` 为准。

## 原则

- 配置跟 `BleConfiguration`，不跟页面
- `BleSession.register` 注册产品；连接后使用配置快照，后续 register 变更不影响已连设备
- 混扫：系统层不按 Service UUID 过滤；用 matching / parser resolve
- App 侧推荐只使用 `BleSession.connect(discovery:)`
- 串行写队列、ACK、超时、重连：改前先读 `BLE_README.md` 与现有实现

## 分层职责

| 层级 | 职责 |
|------|------|
| `BleConfiguration` | 单款产品完整协议快照 |
| `BleSession` | 产品注册表 + `activeConnection` |
| `BleCentral` | 唯一 `CBCentralManager` |
| `BlePeripheralConnection` | 状态机 + GATT + 写队列 + 重连 |

## 不要做

- 不要在内核里写死某个产品的展示名
- 不要把 AppTemplate 的 Demo VC 逻辑下沉进 Ble
- 不要在未确认时重写整套状态机
- 不要为单页需求把配置绑到页面生命周期

## 权威文档

- `BLE_README.md` — 实现细节与代码走读
- `BLE_ROADMAP.md` — 特性拓展迭代规划（Release / 优先级 / 边界）
