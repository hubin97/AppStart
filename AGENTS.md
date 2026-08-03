# AppStart Agent 指南

## 项目定位

AppStart 是 iOS 基础组件私有库（CocoaPods subspec），iOS 14+ / Swift 5+。  
可复用能力放本库；业务展示名、具体产品 UI、Demo 交互放 AppTemplate。

## 与 Demo App 的关系

- 本地常与 `AppTemplate`（Demo App）并列放在同一工作区父目录，但二者是**独立 git 仓库**
- 改可复用能力 / 内核 / subspec → 本仓库
- 改演示页 / 业务接入示例 → `AppTemplate` 仓库（见该仓 `AGENTS.md`）
- 大特性收尾需询问是否同步 Demo（见下文）

## 目录与模块

| 模块 | 路径 | 说明 | 详细文档 |
|------|------|------|----------|
| Base | `AppStart/Base` | VC/导航/Extension/主题基座 | `README.md` |
| UIComponents | `AppStart/UIComponents` | Alert、列表等可复用 UI | `README.md` |
| Utils | `AppStart/Utils` | Logger、AuthStatus、Toolkit | 文件头注释 / README |
| Network | `AppStart/Network` | HTTP（Moya 等） | `AppStart/Network/Core/HTTP_README.md` |
| Connectivity | `AppStart/Network/Connectivity` | 网络连通性（≠ 权限） | `AppStart/Network/Connectivity/CONNECTIVITY_README.md` |
| Ble | `AppStart/Ble` | CoreBluetooth 封装 | `AppStart/Ble/BLE_README.md` |
| ProgressHUD | `AppStart/ProgressHUD` | HUD | `README.md` |

## 编码约定

- 优先 Swift 现代写法；新并发代码优先 `async/await`, 避免无必要回调嵌套
- 架构模块设计时优先考虑 软件六大设计原则, 数据结构选型要高效
- 编码格式尽量保证规范, 保证分块清晰, 命名优雅; 设计合理且具通用性, 高可复用性, 可读性, 可移植性
- 对外公开 API 保持清晰命名；破坏性变更要在回复里明确说明
- 不要无关大重构；改动范围与任务目标一致
- 不要把业务文案、产品展示名、页面跳转硬编码进库内核
- 新增能力优先扩展现有类型/配置，而不是平行再造一套
- 日志使用项目既有 Logger（如 `LogM`），不要随手 `print` 作为正式方案
- 权限（AuthStatus）与网络连通性（Connectivity）边界不要混淆
- Force unwrap、随意 `try!` 仅在确信安全且局部时使用，否则显式处理错误

## 架构红线（摘要）

### Ble

- 配置跟 `BleConfiguration`，不跟页面
- 产品协议解析 / 匹配在配置侧；UI 信息由 App 维护
- App 侧推荐只使用 `BleSession.connect(discovery:)`
- 改连接状态机、写队列、重连前先读 `AppStart/Ble/BLE_README.md`
- 更多细则见 `AppStart/Ble/AGENTS.md`

### Network / Connectivity

- Connectivity 管路径/互联网探测；AuthStatus 管隐私授权与系统开关
- 不要恢复已移除的旧 Reachability 方案作为主路径
- HTTP 插件与接口约定见 `HTTP_README.md`

## 大特性收尾检查（必须执行）

当任务属于「新增大的公开能力 / 改变对外用法 / 新模块行为」时，在结束前必须询问用户：

> 是否需要在 AppTemplate 中新增或更新 Demo 示例？

判断参考：

- 需要 Demo：新公开 API、非显而易见的用法、新模块能力
- 通常不需要：纯内部重构、无行为变化的 bugfix

若用户同意：

- 在 `AppTemplate` 的 Demo 区域补充示例（常见：`AppTemplate/Modules/Main/Func/`）
- 库内保持可复用逻辑；App 侧放演示与产品相关代码

若用户拒绝：在回复中简要记录原因，不要静默跳过询问。

## 修改边界

- 默认只改 `AppStart/` 源码与对应 README
- 不要改 `Example/Pods/**`
- 不要改无关的 AppTemplate（除非本任务明确包含 Demo）
- 不确定时：先只读分析并给出计划，确认后再改代码

## Definition of Done

- [ ] 改动落在正确模块 / subspec
- [ ] 行为符合任务验收
- [ ] 无无关重构
- [ ] 必要时更新对应 README
- [ ] 大特性已询问是否需要 AppTemplate Demo，并按用户决定处理
