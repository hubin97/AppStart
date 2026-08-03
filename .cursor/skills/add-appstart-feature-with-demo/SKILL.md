---
name: add-appstart-feature-with-demo
description: 在 AppStart 新增大特性后，询问并可选在 AppTemplate 生成 Demo。用于库侧大功能与示例同步。
disable-model-invocation: true
---

# AppStart 大特性 + Demo

## 输入

- 特性目标
- 涉及模块
- 是否已有 API 草稿
- 用户对 Demo 的初步意向（可空）

## 步骤

1. 阅读 `AppStart/AGENTS.md` 与相关模块 README
2. 先只读分析，给出计划与影响面，确认后再改
3. 在 AppStart 实现并通过库侧验收
4. 按 AGENTS「大特性收尾检查」询问是否需要 AppTemplate Demo
5. 若需要：在 `AppTemplate/Modules/Main/Func/`（或对应目录）增加示例与入口
6. 输出改动文件列表、Demo 决策结果与未决事项

## 验收

- [ ] 库侧行为正确
- [ ] 已询问 Demo，并记录用户决定
- [ ] 若做了 Demo：可点通并展示用法
- [ ] 可复用逻辑未错误下沉到 Demo（或已说明例外）
