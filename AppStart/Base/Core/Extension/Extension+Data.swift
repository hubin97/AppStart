//
//  Extension+Data.swift
//  LuteBase
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 Hubin_Huang. All rights reserved.
//

import Foundation

fileprivate typealias Extension_Data = Data

/// Data 功能扩展
extension Extension_Data {

    /// data转string
    public var string: String? {
        return String(data: self, encoding: String.Encoding.utf8)
    }

    /// data转jsonObject
    public var jsonObj: Any? {
        if let json = try? JSONSerialization.jsonObject(with: self, options: .mutableContainers) {
            return json
        }
        return nil
    }

    /// data转dict
    public var dict: [String: Any]? {
        if let dict = self.jsonObj as? [String: Any] {
            return dict
        }
        return nil
    }

    /// data转array
    public var array: [Any]? {
        if let arr = self.jsonObj as? [Any] {
            return arr
        }
        return nil
    }
}

extension Extension_Data {
    
    public enum ImageType {
        case unknown
        case jpeg
        case tiff
        case bmp
        case ico
        case icns
        case gif
        case png
        case webp
    }
    
    /// 获取图片Data时格式
    /// https://www.jianshu.com/p/2b90f8876bf0
    /// - Returns: 格式
    public func imageType() -> Data.ImageType {
        return self.detectImageType()
    }
    
    private func detectImageType() -> Data.ImageType {
        if self.count < 16 { return .unknown }
        
        var value = [UInt8](repeating:0, count:1)
        self.copyBytes(to: &value, count: 1)
        
        switch value[0] {
        case 0x4D, 0x49:
            return .tiff
        case 0x00:
            return .ico
        case 0x69:
            return .icns
        case 0x47:
            return .gif
        case 0x89:
            return .png
        case 0xFF:
            return .jpeg
        case 0x42:
            return .bmp
        case 0x52:
            let subData = self.subdata(in: Range(NSMakeRange(0, 12))!)
            if let infoString = String(data: subData, encoding: .ascii) {
                if infoString.hasPrefix("RIFF") && infoString.hasSuffix("WEBP") {
                    return .webp
                }
            }
            break
        default:
            break
        }
        return .unknown
    }
}
