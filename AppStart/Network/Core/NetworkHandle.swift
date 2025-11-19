//
//  NetworkHandle.swift
//  AppStart
//
//  Created by hubin.h on 2024/7/26.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation
import Moya

/**
 外部实现
 1. 
 /// 全局网络处理, 业务层处理逻辑，如错误码判断等
 class NetworkResponseHandler: NetworkHandleProvider {
    func successHandle(response: Response) {}
    func failureHandle(error: MoyaError) {}
 }
 
 2.
 /// 扩展插件方法
 extension PTEnum {
     /// 所有插件
     public static func all(content: String? = nil, isEnable: Bool = false, timeout: TimeInterval = 20) -> [PluginType] {
         return [PTEnum.loading(content: content, isEnable: isEnable), PTEnum.timeout(timeout), PTEnum.handle(provider: NetworkResponseHandler()), PTEnum.println()]
     }
     
     /// 排除loading 剩余的所有插件
     public static func noloadings(timeout: TimeInterval = 20) -> [PluginType] {
         return [PTEnum.timeout(timeout), PTEnum.handle(provider: NetworkResponseHandler()), PTEnum.println()]
     }
 }
 */

public protocol NetworkHandleProvider: AnyObject {
    /// 响应成功处理
    func successHandle(response: Response)
    
    /// 响应失败处理（可选，提供默认空实现）
    func failureHandle(error: MoyaError)
}

public extension NetworkHandleProvider {
    /// 默认失败处理为空实现，业务层可按需重写
    func failureHandle(error: MoyaError) {
        //ProgressHUD.showError(error.localizedErrorMessage)
        //ProgressHUD.showError(NetworkError.from(error).localizedDescription)
        ProgressHUD.showError(error.userErrorMessage)
    }
}

public enum PTEnum {
    case loading(content: String?, isEnable: Bool)
    case timeout(time: TimeInterval)
    case handle(provider: any NetworkHandleProvider)
    case println

    var plugin: PluginType {
        switch self {
        case .loading(let content, let isEnable):
            return PTEnum.loading(content: content, isEnable: isEnable)
        case .timeout(let time):
            return PTEnum.timeout(time)
        case .handle(let provider):
            return PTEnum.handle(provider: provider)
        case .println:
            return PTEnum.println()
        }
    }
    
    public static func loading(content: String? = nil, isEnable: Bool = false) -> PluginType {
        return NetworkLoadingPlugin(content: content, isEnable: isEnable)
    }
    
    public static func println() -> PluginType {
        return NetworkPrintlnPlugin()
    }
    
    public static func timeout(_ time: TimeInterval = 20.0) -> PluginType {
        return NetworkTimeoutPlugin(time)
    }
    
    public static func handle(provider: any NetworkHandleProvider) -> PluginType {
        return NetworkHandlePlugin(provider: provider)
    }
}
