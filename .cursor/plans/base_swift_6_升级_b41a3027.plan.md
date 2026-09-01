---
name: Base Swift 6 升级
overview: 以 Swift 6 严格并发和“远程 Web 内容不可信”为基线，分阶段更新 Base 及必要调用方；先建立可编译基线，再修复确定的行为/安全问题，最后收口旧扩展 API。保留 iOS 14 的 AppStart 部署目标和现有有效注释，不直接编辑 CocoaPods 生成工程。
todos:
  - id: swift6-baseline
    content: 建立 AppStart/宿主 Swift 6 严格并发构建基线并分类诊断
    status: completed
  - id: global-core
    content: 改造 Global/Core 主 actor、Window、安全区、导航和依赖注入
    status: completed
  - id: secure-web
    content: 重建白名单 Web bridge 并修复 WKWebView 生命周期与导航策略
    status: completed
  - id: extensions
    content: 迁移活跃扩展 API并收口零引用危险 API
    status: completed
  - id: verification
    content: 补充回归测试并完成宿主、Example 与 pod lint 验证
    status: in_progress
isProject: false
---

# Base Swift 6 升级与修复计划

## 已确认需要修改
- **构建基线**：[`AppStart.podspec`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart.podspec) 仍只声明 Swift 5，两个 [`Podfile`](/Users/imac/Documents/Code/AppTemplate/AppTemplate/Podfile) / [`Example/Podfile`](/Users/imac/Documents/Code/AppTemplate/AppStart/Example/Podfile) 又把所有 target 强制成 Swift 5。调整为 AppStart/宿主 Swift 6、第三方 Pod 继续各自兼容版本，并开启严格并发检查；生成的 `_Pods.xcodeproj` 不手改。
- **UIKit actor 隔离**：在 [`AppCore.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Global/AppCore.swift)、[`ViewModelProvider.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Global/ViewModelProvider.swift)、[`Navigator.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Core/Navigator.swift) 及相关 UI 协议/扩展中明确 `@MainActor`；补齐 [`Themes.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Global/Themes.swift) 的直接 UIKit import。并同步修正被编译器暴露的 Base 消费方隔离，不使用无依据的 `@unchecked Sendable` 掩盖问题。
- **Window 与安全区**：[`AppCore.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Global/AppCore.swift) 移除已废弃的 `UIApplication.shared.windows/statusBarFrame` 回退，按前台 Scene 查找窗口；[`NaviBar.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Core/NaviBar.swift) 与 [`ViewController.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Core/ViewController.swift) 改为基于 safe-area 的动态约束，避免启动、旋转、分屏时使用一次性全局 frame。
- **导航确定性错误**：[`Navigator.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Core/Navigator.swift) 统一主 actor 同步导航，修正 `.alert` 给 sender 设置 presentation style、`dismiss` 对象错误；将 `navigator!` 改为有默认值的非可选依赖。修正 [`TabBarController.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Core/TabBarController.swift) 数组校验的 `||/&&` 越界漏洞，并收口返回手势职责。
- **Web 生命周期与安全边界**：[`WKWebController.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Core/WKWebController.swift) 不再在每次 `viewWillDisappear` 永久清除 delegate/KVO，去掉依赖 `title == nil` 的重复 reload，并加入 URL scheme/host 策略扩展点。将 [`WebInteractable.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Core/WebInteractable.swift) 的 `NSSelectorFromString/perform` 任意反射替换为显式 handler 白名单，Native→JS 使用参数化调用而非字符串插值；同步迁移 [`JSWebController.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Core/JSWebController.swift) 和 [`JSWebCallBack.swift`](/Users/imac/Documents/Code/AppTemplate/AppTemplate/AppTemplate/Modules/Main/Func/JSWebCallBack.swift)。
- **依赖注入契约**：[`ViewModelProvider.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Global/ViewModelProvider.swift) 去掉类型错误时静默新建空 ViewModel 的行为，改成显式注入失败；同步 9 个 provider，确保带参数 ViewModel 不会悄悄退化为空状态。
- **活跃扩展 API**：[`Extension+TableView.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Extension/Extension+TableView.swift) 增加 `IndexPath` 的类型安全 dequeue，并迁移 11 个调用方；[`Extension+Color.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Extension/Extension+Color.swift) 用非废弃解析实现并提供可失败的严格入口，先保留兼容入口、迁移现有合法常量后再弃用；[`Extension+ViewController.swift`](/Users/imac/Documents/Code/AppTemplate/AppStart/AppStart/Base/Extension/Extension+ViewController.swift) 改稳定 associated-object key 并主 actor 隔离。

## 分阶段实施
1. 更新 Swift 6 / strict-concurrency 配置并获取真实编译诊断；只修 Base 及其必要消费方，保持第三方依赖 Swift 5 互操作。
2. 完成 Global/Core 主 actor、非可选依赖和 Window/safe-area 改造，修复 Navigator、TabBar 与 Web 生命周期问题。
3. 重建 Web bridge 为白名单消息模型，加入不可信远程页面导航策略，并迁移示例回调。
4. 迁移 TableView、Color、Dictionary 等活跃扩展；对零引用的 Date/Image/String/Label 等 API，仅修 Swift 6 编译阻塞和明确崩溃边界，其余标记弃用或留到独立清理，避免无关大 diff。
5. 增加回归测试：Navigator 各 transition、ViewModel 注入失败、TabBar 数组边界、Web 消息白名单/转义/生命周期、hex 解析与 typed dequeue；执行宿主构建、Example tests、pod lint，并检查新增 warnings 与注释净删除。

## 已核实但不作为首批缺陷
- `UITableView.dequeueReusableCell(withIdentifier:) as! T` 在当前“先注册、类名作唯一 identifier”的 11 条路径并非 P0 必现崩溃；仍因 API 契约脆弱而迁移。
- `UIColor(hexStr:)` 的现有调用均为代码常量，无证据表明当前会解析失败；问题是废弃 Scanner API和错误静默，不按生产事故处理。
- `UIGestureRecognizer.addTarget` 不能仅凭 target-action 写法判定强引用泄漏；返回手势会因职责分散而重构，但不把它列为已证实内存泄漏。
- `BlurOverlayView`、`UIEdgeInsets` 扩展、`UITabBarAppearance`、`WeakScriptMessageHandler`、`loadFileURL` 目前实现合理，保留。