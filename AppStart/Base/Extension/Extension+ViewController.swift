//
//  Extension+ViewController.swift
//  AppStart
//
//  Created by hubin.h on 2022/5/31.
//  Copyright © 2025 hubin.h. All rights reserved.

import UIKit

// MARK: - global var and methods
private typealias Extension_ViewController = UIViewController

@MainActor
private enum VcKeys {
    static var keyboardShow: UInt8 = 0
    static var keyboardHide: UInt8 = 0
}

// MARK: - main class
@MainActor
extension Extension_ViewController {

    var keyboardShowBlock: ((Notification) -> Void)? {
        get {
            return objc_getAssociatedObject(self, &VcKeys.keyboardShow) as? ((Notification) -> Void)
        }
        set {
            objc_setAssociatedObject(self, &VcKeys.keyboardShow, newValue, .OBJC_ASSOCIATION_COPY)
        }
    }
    
    var keyboardHideBlock: ((Notification) -> Void)? {
        get {
            return objc_getAssociatedObject(self, &VcKeys.keyboardHide) as? ((Notification) -> Void)
        }
        set {
            objc_setAssociatedObject(self, &VcKeys.keyboardHide, newValue, .OBJC_ASSOCIATION_COPY)
        }
    }
}

// MARK: - call backs
@MainActor
extension Extension_ViewController {
    
    public func addKeyboardListener(willShow: ((Notification) -> Void)? = nil, willHide: ((Notification) -> Void)? = nil) {
        self.keyboardShowBlock = willShow
        self.keyboardHideBlock = willHide
        NotificationCenter.default.addObserver(self, selector: #selector(keyBoardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyBoardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    public func removeKeyboardListener() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc func keyBoardWillShow(notification: Notification) {
        self.keyboardShowBlock?(notification)
    }
    
    @objc func keyBoardWillHide(notification: Notification) {
        self.keyboardHideBlock?(notification)
    }
}
