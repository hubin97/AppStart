//
//  JSWebController.swift
//  AppTemplate
//
//  Created by hubin.h on 2025/9/25.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation
import WebKit

// MARK: - Global Variables & Functions (if necessary)
public class JSWebViewModel: ViewModel {
 
    var symbol: String?
    public convenience init(symbol: String?) {
        self.init()
        self.symbol = symbol
    }
}

/// JS 可调用的 Native 方法 handler；通过 `WebBridgeHandler.bridge(...)` 构造。
public struct WebBridgeHandler {
    public let handle: @MainActor (_ params: Any?) -> Void
    
    public init(_ handle: @MainActor @escaping (_ params: Any?) -> Void) {
        self.handle = handle
    }
    
    /// 包装无参业务方法。
    public static func bridge(_ handler: @escaping () -> Void) -> WebBridgeHandler {
        WebBridgeHandler { _ in handler() }
    }
    
    /// 包装带参业务方法；参数类型不匹配时会输出 debug 日志。
    public static func bridge<T>(_ handler: @escaping (T) -> Void) -> WebBridgeHandler {
        WebBridgeHandler { params in
            guard let params else {
                LogM.debug("Web bridge 参数缺失: 期望 \(T.self)")
                return
            }
            guard let value = params as? T else {
                LogM.debug("Web bridge 参数类型不匹配: 期望 \(T.self), 实际 \(type(of: params))")
                return
            }
            handler(value)
        }
    }
}

// MARK: - Main Class
open class JSWebController: WKWebController, ViewModelProvider {
    public typealias ViewModelType = JSWebViewModel

    /// JS 可调用的 Native 方法白名单；业务容器按需重写。
    open var bridgeHandlers: [String: WebBridgeHandler] {
        [:]
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        if let symbol = vm.symbol {
            self.registerJsCallNative(with: symbol)
        }
    }
}

// MARK: - Private Methods
extension JSWebController {
    
    /// 注册监听Js方法调用
    private func registerJsCallNative(with interactSymbol: String) {
        LogM.debug("注册监听Js方法调用")
        self.addMethod(name: interactSymbol) { [weak self] symbol, messageBody in
            guard let self,
                  symbol == interactSymbol,
                  self.shouldAcceptBridgeMessage(from: self.wkWebView.url),
                  let message = self.bridgeMessage(from: messageBody),
                  let method = message["method"] as? String else {
                return
            }
            guard let handler = self.bridgeHandlers[method] else {
                LogM.debug("未注册 Web bridge 方法: \(method)")
                return
            }
            handler.handle(message["params"])
        }
    }
    
    /// native调用js方法 `临时测试`
    public func nativeCallJs(with value: Any?) {
        // LogM.debug("native调用js方法")
        let script: String
        let arguments: [String: Any]
        if let value {
            script = "receiveNativeMessage(message)"
            arguments = ["message": value]
        } else {
            script = "receiveNativeMessage()"
            arguments = [:]
        }
        self.wkWebView.callAsyncJavaScript(
            script,
            arguments: arguments,
            in: nil,
            in: .page
        ) { result in
            if case .failure(let error) = result {
                LogM.debug("native调用js方法失败: \(error.localizedDescription)")
            }
        }
    }

    /// 同时兼容 WKScriptMessage 直接传对象和旧页面传 JSON 字符串。
    private func bridgeMessage(from body: Any) -> [String: Any]? {
        if let message = body as? [String: Any] {
            return message
        }
        guard let json = body as? String,
              let data = json.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return message
    }
}

// MARK: - Callbacks
extension JSWebController {
}

// MARK: - Utilities & Helpers
extension JSWebController {
}

// MARK: - Delegate & Data Source
extension JSWebController {
}
