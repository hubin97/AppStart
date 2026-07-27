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
Task {
    for await snap in ConnectivityCenter.shared.monitor() {
        // 更新 UI：snap.summaryText
    }
}

// 蜂窝/WLAN 数据策略（设置 → 蜂窝网络 → 本 App）
Task {
    for await allowed in ConnectivityCenter.shared.monitorCellularDataPolicy() {
        // allowed == true 表示未受限
    }
}
```

## 与 `ReachabilityManager` 的关系

`ReachabilityManager`（Alamofire 链路层 + Rx）**保持不变**，适合已有 Rx 代码、只需 WiFi/蜂窝/无连接的场景。

需要路径质量、互联网探测时，直接用 **`ConnectivityCenter` 的 async API**（无需 Rx）：

```swift
Task {
    for await snap in ConnectivityCenter.shared.monitor() { ... }
}
```

Rx 项目可在业务层自行 `Observable.create` 包装，不必在组件库内再封一层。

## 迁移指南

| 旧 API | 新 API |
|--------|--------|
| `snapshot()` | `status()` |
| `snapshotWithValidation()` | `await status(.validated())` |
| `validateInternet(force:)` | `await status(.validated(force:))` → 读 `.validation` |
| `AuthorizationStatus.monitorNetworkReachability()` | `ConnectivityCenter.shared.monitor()` |
| `AuthorizationStatus.monitorCellularDataRestriction()` | `ConnectivityCenter.shared.monitorCellularDataPolicy()` |
| `AuthPermission.networkReachability` | 不再属于权限枚举 |
| `AuthorizationStatus.networkService { }` | 已移除，请用 `ConnectivityCenter.shared.monitor()` |
| `AuthorizationStatus.cellularDataService { }` | 已移除，请用 `ConnectivityCenter.shared.monitorCellularDataPolicy()` |
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
├── ConnectivitySnapshot.swift   # 分层模型 + ConnectivityLevel
├── NetworkPathMonitor.swift     # NWPathMonitor
├── NetworkValidator.swift       # HTTP 探测
├── ConnectivityCenter.swift     # 统一入口
└── CONNECTIVITY_README.md       # 本文档
```

## 参考

- [Apple NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)
- HTTP 模块：[HTTP_README.md](../Core/HTTP_README.md)
