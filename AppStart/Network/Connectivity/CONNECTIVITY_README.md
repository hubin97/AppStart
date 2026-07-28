# Connectivity 网络连通性

基于 **NWPathMonitor（L2 路径）+ 可选 HTTP 探测（L3 互联网）** 的网络连通性模块，与 `AuthorizationStatus`（隐私授权）分离。

## 为什么单独模块

| 能力 | 模块 | 说明 |
|------|------|------|
| 相册/相机/定位/蓝牙 **隐私授权** | `AuthStatus` | 用户是否允许 App 访问 |
| 定位/蓝牙 **系统服务开关** | `AuthStatus.snapshot` | 系统功能是否开启 |
| **网络路径 / 互联网 / 蜂窝策略** | `Connectivity` | 基础设施状态，无 App 授权层 |

旧版 `AlamofireReachability`（SCNetworkReachability）已移除：只能判断链路是否起来，无法识别「连上无网 WiFi / 设备热点」等场景。

## 分层模型

```
L3  InternetValidation   HTTP 探测（可选；默认 Apple captive 页，生产请换业务 health）
L2  NetworkPathStatus    NWPathMonitor（satisfied / unsatisfied）
L1  NetworkLinkKind       Wi‑Fi / 蜂窝 / 有线 / 无
```

查询深度由 `ConnectivityLevel` 控制：

```swift
enum ConnectivityLevel {
    case path                          // L1+L2，同步
    case validated(force: Bool = false) // L1+L2+L3，async + debounce
}
```

### 典型场景

| 场景 | L1/L2 | L3 探测 |
|------|-------|---------|
| 正常 WiFi 有网 | satisfied + wifi | available |
| 路由器无拨号 / 假 WiFi | satisfied + wifi | unavailable |
| 设备热点但热点无网 | satisfied + wifi | unavailable |
| Captive Portal | satisfied | captivePortal（3xx） |
| 飞行模式 | unsatisfied | 不探测 |

## Pod 引入

```ruby
pod 'AppStart/Network/Connectivity'
# 仅需 Alamofire 链路层 Rx 时可单独引入 Utils（与 Connectivity 无依赖关系）
pod 'AppStart/Network/Utils'
```

## API

### 状态查询（推荐）

```swift
// L1+L2，同步，不发起 HTTP
let snap = ConnectivityCenter.shared.status()
snap.canAttemptRequest   // 路径可用，可尝试请求
snap.summaryText         // UI 文案

// L1+L2+L3（登录/支付等关键操作前）
let full = await ConnectivityCenter.shared.status(.validated())
full.isInternetReady     // 路径 OK 且探测通过

// 强制跳过 debounce 重新探测
let forced = await ConnectivityCenter.shared.status(.validated(force: true))
forced.validation        // .available / .unavailable / .captivePortal
```

**按需调用，无后台轮询。** L3 只在 `status(.validated)` 时发生；
`monitor()` 与 `status()` 不会自动发 HTTP。`validationDebounce` 是限频缓存窗口，不是定时器间隔。

```swift
// 生产环境务必替换（默认仅为 iOS 通用 captive 探测页，非业务可用性保证）
ConnectivityCenter.shared.validationURL = URL(string: "https://api.example.com/health")!
ConnectivityCenter.shared.validationDebounce = 30

// 路径恢复后如需更新 L3 状态，在 monitor 回调里自行探测：
Task {
    for await snap in ConnectivityCenter.shared.monitor() {
        if snap.canAttemptRequest, snap.validation == .notChecked {
            _ = await ConnectivityCenter.shared.status(.validated())
        }
    }
}
```

默认探测地址为 `http://captive.apple.com/hotspot-detect.html`（与系统 Wi‑Fi 门户检测同源），
不使用 Google `generate_204`（国内易失败），也不使用 `apple.com` 首页（非专用、响应重）。

### 监听

```swift
// 便捷全局函数（对齐 connectedToInternet()，无 Rx）
Task {
    for await snap in connectivityUpdates() {
        // snap.canAttemptRequest / snap.summaryText
    }
}

Task {
    for await policy in cellularDataPolicyUpdates() {
        let hint = policy.accessHint(with: ConnectivityCenter.shared.status())
        // policy：系统 coarse 态；hint：结合路径的 UI 提示
        // 大陆「关闭」与「仅 WLAN」均为 .restricted，最终以请求是否成功为准
    }
}

// 等价于：
// ConnectivityCenter.shared.monitorCellularDataPolicy()
```

### 无线数据策略（大陆三档 vs 海外）

`CTCellularData` **无法**直接读出大陆设置的三档文案，只能得到：

| `CellularDataPolicy` | 大陆「无线数据」 | 海外典型 |
|----------------------|------------------|----------|
| `.unrestricted` | 无线局域网与蜂窝数据 | 允许蜂窝 |
| `.restricted` | 关闭 **或** 仅无线局域网 | 禁止蜂窝（Wi‑Fi 常仍可用） |
| `.unknown` | 尚未回调 | 同左 |

整合方式：

1. 用 `cellularDataPolicyUpdates()` 拿系统 coarse 态  
2. 用 `policy.accessHint(with: path)` / `wirelessDataAccessHint()` 结合当前路径给 UI 文案  
3. **「关闭」vs「仅 WLAN」** 以业务请求或 `status(.validated())` 是否成功为准（路径有时在「关闭」下仍显示可用）

## 与 `ReachabilityManager` 的关系

| | `connectedToInternet()` | `connectivityUpdates()` |
|--|-------------------------|-------------------------|
| 模块 | `Network/Utils` | `Network/Connectivity` |
| 技术 | Alamofire + **RxSwift** | `NWPathMonitor` + **AsyncStream** |
| 粒度 | WiFi / 蜂窝 / 不可达 | L1 链路 + L2 路径（可扩展 L3） |

`ReachabilityManager` **保持不变**，适合已有 Rx 代码。新代码推荐：

```swift
Task {
    for await snap in connectivityUpdates() { ... }
}
```

Rx 项目若要桥接，可在业务层自行 `Observable.create` 包装 `connectivityUpdates()`，不必在组件库内再封一层。

## 迁移指南

| 旧 API | 新 API |
|--------|--------|
| `snapshot()` | `status()` |
| `snapshotWithValidation()` | `await status(.validated())` |
| `validateInternet(force:)` | `await status(.validated(force:))` → 读 `.validation` |
| `AuthorizationStatus.monitorNetworkReachability()` | `connectivityUpdates()` / `ConnectivityCenter.shared.monitor()` |
| `AuthorizationStatus.monitorCellularDataRestriction()` | `cellularDataPolicyUpdates()` / `monitorCellularDataPolicy()` |
| `AuthPermission.networkReachability` | 不再属于权限枚举 |
| `AuthorizationStatus.networkService { }` | 已移除，请用 `connectivityUpdates()` |
| `AuthorizationStatus.cellularDataService { }` | 已移除，请用 `cellularDataPolicyUpdates()` |
| vendored `AlamofireReachability.swift` | 已删除 |

## 设计原则（对齐大厂实践）

1. **UI 提示**用 L1+L2（快速、省电），如「当前网络不可用」。
2. **不硬拦截**用户操作；请求失败由网络层重试/错误处理兜底。
3. **关键操作前**（登录、支付）再跑 L3 探测。
4. **探测 debounce**，避免频繁 HEAD 请求。
5. **Captive Portal** 通过 HTTP 3xx 识别，UI 可引导用户完成登录。

## 文件结构

```
AppStart/Network/Connectivity/
├── ConnectivitySnapshot.swift   # L1/L2/L3 + ConnectivityLevel + Snapshot
├── CellularDataPolicy.swift     # 无线数据策略 + WirelessDataAccessHint
├── NetworkPathMonitor.swift     # NWPathMonitor
├── NetworkValidator.swift       # HTTP 探测
├── ConnectivityCenter.swift     # 统一入口
└── CONNECTIVITY_README.md       # 本文档
```

## 参考

- [Apple NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)
- HTTP 模块：[HTTP_README.md](../Core/HTTP_README.md)
