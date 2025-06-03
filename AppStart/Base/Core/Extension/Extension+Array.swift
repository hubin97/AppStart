//
//  Extension+Array.swift
//  LuteBase
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 Hubin_Huang. All rights reserved.
//

import Foundation

// MARK: - global var and methods
fileprivate typealias Extension_Array = Array

// MARK: - private mothods
extension Extension_Array {

    /// dict转data
    public var data: Data? {
        if (JSONSerialization.isValidJSONObject(self)) {
            return try? JSONSerialization.data(withJSONObject: self, options: [])
        }
        return nil
    }

    /// arr转string
    public var string: String? {
        if let data = self.data {
            return String(data: data, encoding: String.Encoding.utf8)
        }
        return nil
    }

    /// 随机一个元素, 同 randomElement()方法
    public var random: Element? {
        return self.count != 0 ? self[Int(arc4random_uniform(UInt32(self.count)))]: nil
    }
}

// MARK: - call backs
extension Extension_Array where Element: Equatable {

    /// 数组去重
    public func deduplication() -> Array<Element> {
        return self.enumerated().filter({ self.firstIndex(of: $0.element) == $0.offset }).map({ $0.element })
    }
}

// MARK: - delegate or data source
extension Extension_Array { 
}

// MARK: - other classes
