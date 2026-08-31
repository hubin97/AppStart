# Ble 模块补充约定

本文件补充根目录 `AGENTS.md`，仅在改 Ble 时加强约束。模块 canonical 路径为 `AppStart/Ble`；路径大小写必须保持一致，避免在 Linux / 大小写敏感文件系统出现重复目录或引用失败。

## 原则

- 配置跟 `BleConfiguration`，不跟页面
- App 启动通过 `BleSession.configure(with:)` 一次性配置全部产品协议；数组顺序决定 resolve 优先级
- 连接使用配置快照，后续重新配置 Session 不影响已连设备
- 混扫：系统层不按 Service UUID 过滤；用 matching / parser resolve
- App 侧推荐只使用 `BleSession.connect(discovery:)`
- 串行写队列、ACK、超时、重连：改前先读 `BLE_README.md` 与现有实现

## 分层职责

| 层级 | 职责 |
|------|------|
| `BleConfiguration` | 单款产品完整协议快照 |
| `BleSession` | 产品协议配置 + `activeConnection` |
| `BleCentral` | 唯一 `CBCentralManager` |
| `BlePeripheralConnection` | 状态机 + GATT + 写队列 + 重连 |

## 不要做

- 不要在内核里写死某个产品的展示名
- 不要把 AppTemplate 的 Demo VC 逻辑下沉进 Ble
- 不要在未确认时重写整套状态机
- 不要为单页需求把配置绑到页面生命周期
- 不要把规划项写成已实现；Service Changed、State Restoration、OTA reconnect suspend 当前仅属路线图设计

## 文档同步

- 改 Ble 源码后，同步核对 `BLE_README.md`、`BLE_ARCHITECTURE_REVIEW.md`、`BLE_ROADMAP.md` 与 `BLE_VALIDATION_CHECKLIST.md`
- 实现细节与公开 API 以源码和 `BLE_README.md` 为权威；架构职责/状态所有权见架构评审，阶段状态见路线图，自动化与真机边界见验证清单

## 权威文档

- `BLE_README.md` — 实现细节与代码走读
- `BLE_ARCHITECTURE_REVIEW.md` — 四层职责、状态所有权、并发边界与已知缺口
- `BLE_ROADMAP.md` — 特性拓展迭代规划（Release / 优先级 / 边界）
- `BLE_VALIDATION_CHECKLIST.md` — 自动化、mock 与真机回归验收
