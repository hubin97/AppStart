//
//  Extension+EdgeInsets.swift
//  AppStart
//
//  Created by hubin.h on 2025/2/26.
//  Copyright © 2024 路特创新. All rights reserved.

import Foundation

// MARK: - global var and methods
typealias Extension_EdgeInsets = UIEdgeInsets

// MARK: - main class
extension Extension_EdgeInsets {
    
    /// 初始化方法：统一设置四个方向的值
    public init(all: CGFloat) {
        self.init(top: all, left: all, bottom: all, right: all)
    }
    
    /// 初始化方法：设置水平和垂直方向的值
    public init(horizontal: CGFloat, vertical: CGFloat) {
        self.init(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
}

// MARK: - private mothods
extension Extension_EdgeInsets { 
}

// MARK: - call backs
extension Extension_EdgeInsets { 
}

// MARK: - delegate or data source
extension Extension_EdgeInsets { 
}

// MARK: - other classes
