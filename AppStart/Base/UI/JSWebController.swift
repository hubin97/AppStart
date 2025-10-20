//
//  JSWebController.swift
//  AppTemplate
//
//  Created by hubin.h on 2025/9/25.
//  Copyright © 2025 路特创新. All rights reserved.

import Foundation

// MARK: - Global Variables & Functions (if necessary)
public class JSWebViewModel: ViewModel {
 
    var symbol: String?
    convenience init(symbol: String?) {
        self.init()
        self.symbol = symbol
    }
}

// MARK: - Main Class
public class JSWebController: WKWebController, WebInteractable, ViewModelProvider {
    public typealias ViewModelType = JSWebViewModel
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        if let symbol = vm.symbol {
            self.registerJsCallNative(with: symbol)
        }
    }
}

// MARK: - Private Methods
extension JSWebController {
    
    // 示例
    @objc func activityNavigator(_ params: [String: Any]) {
        iToast.makeToast("activityNavigator: \(params.string ?? "")")
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
