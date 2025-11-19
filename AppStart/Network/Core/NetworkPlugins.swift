//
//  NetworkPlugins.swift
//  AppStart
//
//  Created by hubin.h on 2022/3/28.
//  Copyright © 2025 hubin.h. All rights reserved.

import Moya
import ObjectMapper

// MARK: - Helper

/// 在主线程执行闭包，如果已在主线程则同步执行，否则异步切换到主线程
public func dispatchOnMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.async(execute: block)
    }
}

public func dispatchOnMain(after delay: TimeInterval = 0, _ block: @escaping () -> Void) {
    if Thread.isMainThread && delay == 0 {
        block()
    } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}

// MARK: - 加载配置
/**
 其他加载情况可以使用Moya自带的插件处理, NetworkActivityPlugin
 let networkActivityClosure = { (_ change: NetworkActivityChangeType, _ target: TargetType) in
     switch change {
     case .began:
         print("\(target) =>began")
     case .ended:
         print("\(target) =>ended")
     }
 }
 NetworkActivityPlugin(networkActivityClosure: networkActivityClosure)
 */
/// 加载动画, 结合ProgressHUD一起使用
public class NetworkLoadingPlugin: PluginType {

    let content: String?
    let hudSize: CGSize
    let bgColor: UIColor?
    let fgColor: UIColor?
    let isEnable: Bool

    /// 初始化加载
    /// - Parameters:
    ///   - content: 文本, 默认 nil
    ///   - hudSize: 尺寸, 默认 100 * 100
    ///   - bgColor: 背景色, 默认.white
    ///   - fgColor: 字体色, 默认.black
    ///   - isEnable: 是否允许Hud底下交互, 默认禁用 false
    init(content: String? = nil, hudSize: CGSize = CGSize(width: 100, height: 100), bgColor: UIColor? = nil, fgColor: UIColor? = nil, isEnable: Bool = false) {
        self.content = content
        self.hudSize = hudSize
        self.bgColor = bgColor
        self.fgColor = fgColor
        self.isEnable = isEnable
    }

    public func willSend(_ request: RequestType, target: TargetType) {
        DispatchQueue.main.async {
            // hud loading
            ProgressHUD.animate(self.content, interaction: self.isEnable)
            guard #available(iOS 13.0, *) else {
                DispatchQueue.main.async {
                    UIApplication.shared.isNetworkActivityIndicatorVisible = true
                }
                return
            }
        }
    }

    public func didReceive(_ result: Result<Response, MoyaError>, target: TargetType) {
        // 立即 dismiss loading，确保在 Promise 的 done/catch 回调之前执行
        dispatchOnMain {
            ProgressHUD.dismiss()
        }
        
        guard #available(iOS 13.0, *) else {
            dispatchOnMain {
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
            }
            return
        }
    }
}

// MARK: - 超时配置
/// 默认 20s超时
public class NetworkTimeoutPlugin: PluginType {

    let timeout: TimeInterval
    public init(_ timeout: TimeInterval = 20) {
        self.timeout = timeout
    }
    public func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        var req = request
        req.timeoutInterval = timeout
        return req
    }
}

// MARK: - 全局配置处理
public class NetworkHandlePlugin: PluginType {

    private let provider: NetworkHandleProvider
    
    /// 直接持有 provider，简化调用链
    public init(provider: NetworkHandleProvider) {
        self.provider = provider
    }

    public func didReceive(_ result: Result<Response, MoyaError>, target: TargetType) {        
        // 顺序：loading dismiss -> successHandle -> Promise done/catch
        dispatchOnMain { [weak provider] in
            guard let provider = provider else { return }
            switch result {
            case let .success(response):
                provider.successHandle(response: response)
            case let .failure(error):
                provider.failureHandle(error: error)
            }
        }
    }
}

// MARK: - 缓存策略处理

/// 控制http接口缓存策略
/// `注意: 个人信息、订单等重要性, 及时性接口, 最好忽略缓存`
///
/// `useCache: true` 默认缓存策略`.useProtocolCachePolicy`
/// `useCache: false` 设置 `.reloadIgnoringLocalCacheData`，即`强制忽略本地缓存，重新从网络加载`
public final class NetworkCachePlugin: PluginType {
    
    let useCache: Bool
    public init(shouldUseCache: Bool = true) {
        self.useCache = shouldUseCache
    }
    public func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        var req = request
        // FIXME: 除了自己设置忽略忽略的; 用户态接口也统一禁用缓存策略
        if !useCache || target.path.hasPrefix("/user/") {
            req.cachePolicy = .reloadIgnoringLocalCacheData
        }
        return req
    }
}

// MARK: - 日志打印
import CocoaLumberjack
/// 日志格式输出 Moya NetworkLoggerPlugin 改
public class NetworkPrintlnPlugin: PluginType {

    public static let shared = NetworkPrintlnPlugin()
    /// 设置打印日志级别, 默认 off为关闭,
    /// UPDATE: 250812 网络日志默认 简易日志, 即使debug模式写文件
    public var loglevel: DDLogLevel = .off
    
    /// 是否打印response.description
    public static var showRspDesc = false

    fileprivate let loggerId = "Moya"
    fileprivate let dateFormatString = "dd/MM/yyyy HH:mm:ss"
    fileprivate let dateFormatter = DateFormatter()
    var date: String {
        dateFormatter.dateFormat = dateFormatString
        dateFormatter.locale = Locale(identifier: "zh_CN")
        return dateFormatter.string(from: Date())
    }
    
    /// 当前打印日志级别
    private var currentLevel: DDLogLevel {
        #if DEBUG
        return NetworkPrintlnPlugin.shared.loglevel
        #else
        return .off
        #endif
    }
    
    public func willSend(_ request: RequestType, target: TargetType) {
        guard currentLevel != .off else { return }
        let req_content = logNetworkRequest(request.request as URLRequest?)
        LogM.log(level: currentLevel, message: "Request 🚀🚀🚀", file: "", line: 0)
        req_content.forEach({ LogM.log(level: currentLevel, message: "\($0)", file: "", line: 0) })
    }

    /// Result库缺少导入, didReceive不执行
    public func didReceive(_ result: Result<Response, MoyaError>, target: TargetType) {
        guard currentLevel != .off else { return }
        
        var rsp_content = [String]()
        if case .success(let response) = result {
            rsp_content = logNetworkResponse(response.response, data: response.data, target: target)
        } else {
            rsp_content = logNetworkResponse(nil, data: nil, target: target)
        }
        
        LogM.log(level: currentLevel, message: "Response ✨✨✨", file: "", line: 0)
        LogM.log(level: currentLevel, message: "PATH: \(target.path)", file: "", line: 0)
        rsp_content.forEach({ LogM.log(level: currentLevel, message:"\($0)", file: "", line: 0) })
    }

    func logNetworkRequest(_ request: URLRequest?) -> [String] {
        var output = [String]()
        output += [format(loggerId, date: date, identifier: "Request", message: request?.description ?? "(invalid request)")]
        if let httpMethod = request?.httpMethod {
            output += [format(loggerId, date: date, identifier: "HTTP Request Method", message: httpMethod)]
        }
        if let headers = request?.allHTTPHeaderFields {
            output += [format(loggerId, date: date, identifier: "Request Headers", message: headers.description)]
        }
        if let bodyStream = request?.httpBodyStream {
            output += [format(loggerId, date: date, identifier: "Request Body Stream", message: bodyStream.description)]
        }
        if let body = request?.httpBody, let stringOutput = String(data: body, encoding: .utf8) {
            output += [format(loggerId, date: date, identifier: "Request Body", message: stringOutput)]
        }
        return output
    }

    func logNetworkResponse(_ response: HTTPURLResponse?, data: Data?, target: TargetType) -> [String] {
        guard let response = response else {
           return [format(loggerId, date: date, identifier: "Response", message: "Received empty network response for \(target).")]
        }
        var output = [String]()
        if NetworkPrintlnPlugin.showRspDesc {
            output += [format(loggerId, date: date, identifier: "Response", message: response.description)]
        }
        if let data = data, let stringData = String(data: data, encoding: String.Encoding.utf8) {
            output += [format(loggerId, date: date, identifier: "Response Data", message: stringData)]
        }
        return output
    }

    func format(_ loggerId: String, date: String, identifier: String, message: String) -> String {
        return "\(loggerId): \(identifier): \(message)"
    }
}
