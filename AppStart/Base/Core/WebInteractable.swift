//
//  WebInteractable.swift
//  Momcozy
//
//  Created by hubin.h on 2024/11/8.
//  Copyright © 2025 Hubin_Huang. All rights reserved.

import Foundation

// MARK: - global var and methods
// LUTE_NATIVE : js调用native方法
// LUTE_JS : native调用js方法

// MARK: - main class
public protocol WebInteractable where Self: WKWebController {  
    /// 注册监听Js方法调用, 交互标识
    func registerJsCallNative(with interactSymbol: String)
    
    /// native调用js方法
    func nativeCallJs(with jsonString: String?)
}

// MARK: - private mothods
extension WebInteractable {
    
    // 不带参
    // self.perform(selector)
    // 带一个参
    // self.perform(selector, with: tmp_content.value(forKey: "content"))
    // 带两个参
    // self.perform(selector, with: tmp_content.value(forKey: "params"), with: tmp_content.value(forKey: "params"))

    /// 注册监听Js方法调用
    public func registerJsCallNative(with interactSymbol: String) {
        print("注册监听Js方法调用")
        self.addMethod(name: interactSymbol) {[weak self] symbol, params in
            // print("symbol:\(symbol), params:\(params)")
            // 筛选目标方法标签
            guard let self = self, symbol == interactSymbol else { return }
            // 解析参数, 保证参数和 method一定要存在
            guard let dict = params as? [String: Any], let method = dict.value(forKey: "method") as? String else { return }
            // 执行方法名, 如果有参数则方法名为 method:
            var selectorName = method
            var param: Any?
            if let value = dict.value(forKey: "params") {
                selectorName = "\(method):"
                param = value
            }
            // OC反射 调用方法
            let selector = NSSelectorFromString(selectorName)
            if self.responds(to:selector) {
                // 有参数则传参
                if let param = param {
                    self.perform(selector, with: param)
                } else {
                    self.perform(selector)
                }
            } else {
                print("未找到方法: \(selectorName)")
            }
        }
    }
    
    /// native调用js方法 `临时测试`
    public func nativeCallJs(with jsonString: String?) {
        print("native调用js方法")
        if let jsonString = jsonString {
            self.evaluateJs(jsCode: "receiveNativeMessage('\(jsonString)')") { result, error in
                print("result:\(result ?? ""), error:\(error?.localizedDescription ?? "")")
            }
        } else {
            self.evaluateJs(jsCode: "receiveNativeMessage()") { result, error in
                print("result:\(result ?? ""), error:\(error?.localizedDescription ?? "")")
            }
        }
    }
}
