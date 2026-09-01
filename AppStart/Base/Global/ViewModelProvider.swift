//
//  ViewModel.swift
//  AppStart
//
//  Created by hubin.h on 2024/7/4.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation

open class ViewModel: NSObject {

    required public override init() {}
    deinit {
        print("\(type(of: self)): Deinited")
        //logResourcesCount()
    }
}

/// `ViewModel: Input, Output`
///
/// 提供输入输出转换方法
public protocol ViewModelTransformable {
    associatedtype Input
    associatedtype Output

    func transform(input: Input) -> Output
}

/// `ViewModelProvider: T -> VM`
///
/// `规避后续使用泛型冲突, T改为ViewModelType`
/// 提供ViewModel的声明和类型校验
///
/// `vm` 要求宿主已注入正确类型的 ViewModel；缺失或类型错误属于编程错误，
/// 会立即触发 precondition，避免静默创建一个未配置的新实例。
@MainActor
public protocol ViewModelProvider: AnyObject {
    associatedtype ViewModelType: ViewModel
    
    var viewModel: ViewModel? { get set }
    var vm: ViewModelType { get }
}

extension ViewModelProvider {
    public var vm: ViewModelType {
        guard let viewModel = viewModel as? ViewModelType else {
            // 注入缺失或类型错误属于编程错误；preconditionFailure 在开发期立刻暴露，
            // 比静默 `ViewModelType()` 空实例更易排查（页面会表现为「没数据/逻辑不执行」）。
            preconditionFailure(
                "Expected \(ViewModelType.self), got \(self.viewModel.map { String(describing: type(of: $0)) } ?? "nil")"
            )
        }
        return viewModel
    }
}
