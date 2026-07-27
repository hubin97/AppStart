# AppStart

[CI Status](https://travis-ci.org/hubin.h/AppStart)
[Version](https://cocoapods.org/pods/AppStart)
[License](https://cocoapods.org/pods/AppStart)
[Platform](https://cocoapods.org/pods/AppStart)

基础组件库，用于高效构建和定制 iOS 应用。提供 MVC 基座、UI 组件、网络、蓝牙、日志与 HUD 等模块化能力，可按需通过 CocoaPods subspec 引入。

A foundational component library for efficient development and customization of iOS applications.

## Requirements

- iOS 14.0+
- Swift 5.0+



## Installation

AppStart is available through [CocoaPods](https://cocoapods.org). Add to your Podfile:

```ruby
# 按需引入子模块
pod 'AppStart/Base'
pod 'AppStart/Network'
pod 'AppStart/Ble'
pod 'AppStart/ProgressHUD'
pod 'AppStart/UIComponents'
pod 'AppStart/Utils'
```

Then run `pod install`.

## Example

Clone the repo and run `pod install` from the Example directory first.

## 模块概览


| 模块               | CocoaPods Subspec       | 简述                                                                      | 文档                                                     |
| ---------------- | ----------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------ |
| **Base**         | `AppStart/Base`         | 应用基座：`ViewController` / 导航栈、主题与布局常量、`AppCore` 窗口访问、常用 Extension         | —                                                      |
| **UIComponents** | `AppStart/UIComponents` | 可复用 UI：`AlertView`、封装 TableView / CollectionView / TextField、列表曝光协议     | —                                                      |
| **Utils**        | `AppStart/Utils`        | 工具集：Logger（LogM + 文件存储）、权限与网络可达性、Rx 扩展、Toast / 图片浏览等 Toolkit            | —                                                      |
| **Network**      | `AppStart/Network`      | 基于 Moya + PromiseKit + ObjectMapper 的 HTTP 封装；插件化 Loading / 超时 / 统一错误处理 | [HTTP_README.md](AppStart/Network/Core/HTTP_README.md) |
| **Ble**          | `AppStart/Ble`          | 基于 async/await + AsyncStream 的 CoreBluetooth 封装；多产品协议、扫描/连接/串行写队列       | [BLE_README.md](AppStart/Ble/BLE_README.md)            |
| **ProgressHUD**  | `AppStart/ProgressHUD`  | 全局 Loading / Banner / 自定义 HUD，含多种内置动画                                   | —                                                      |
| **Sources**      | `AppStart/Sources`      | SwiftGen 生成的 `Strings` / `Assets` 类型安全访问（通常随 Base / UI 模块间接依赖）          | —                                                      |




### Base

- **Global**：`AppCore`（窗口、安全区、布局常量）、`Themes`、`ViewModelProvider`
- **Extension**：String / Date / Color / View / ViewController 等常用扩展
- **Core**：`ViewController`、`NavigationController`、`Navigator`、`WKWebController`、导航栏封装



### UIComponents

- **AlertView**：可组合弹窗容器
- **Views**：带刷新、空态、图片加载的列表与输入组件
- **Protocols**：TableView / CollectionView 曝光统计协议



### Utils

- **Logger**：`LogM` 日志管理、文件策略、内置日志列表页（Ble / Network 等模块的 debug 日志依赖此项，使用前需 `LogM.shared.setup(...).launch()`）
- **AuthStatus**：相册、定位、蓝牙等隐私授权与系统服务开关（详见文件头注释）
- **Toolkit**：Toast、本地化、二维码、图片浏览等
- **Reactive**：RxSwift / RxGesture 常用扩展



### Network

Moya `TargetType` 定义接口 → `NetworkFetch` / `NetworkAsync` 发起请求 → `NetworkPlugins` 注入 Loading、超时、日志与业务 `NetworkHandle`。详见 [HTTP_README.md](AppStart/Network/Core/HTTP_README.md)。

**Connectivity**（路径监听 + 可选互联网探测）与权限模块分离，详见 [CONNECTIVITY_README.md](AppStart/Network/Connectivity/CONNECTIVITY_README.md)。

### Ble

业务层为每款产品定义 `BleConfiguration` + `BleAdvDataParser`，经 `BleSession.register` 注册后混扫、连接、写入。App 侧推荐只使用 `BleSession.connect(discovery:)`。详见 [BLE_README.md](AppStart/Ble/BLE_README.md)。

### ProgressHUD

独立 HUD 组件，Network 插件默认依赖其 Loading 能力；也可单独用于非网络场景。

## 推荐阅读顺序

1. [BLE_README.md](AppStart/Ble/BLE_README.md) — Ble 架构与代码走读（含端到端调用链）
2. [HTTP_README.md](AppStart/Network/Core/HTTP_README.md) — 网络插件配置与接口示例



## Author

hubin.h, [970216474@qq.com](mailto:970216474@qq.com)

## License

AppStart is available under the MIT license. See the LICENSE file for more info.
