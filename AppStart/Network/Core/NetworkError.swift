//
//  NetworkError.swift
//  AppStart
//
//  Created by hubin.h on 2025/11/10.
//  Copyright © 2025 路特创新. All rights reserved.

import Foundation
import Moya
import Alamofire

/// 业务层部分（只覆盖 objectMapperError）
//extension NetworkError {
//    /// 业务层自定义错误提示
//    public var errorDescription: String? {
//        switch self {
//        case .objectMapperError(let target):
//            // 自定义国际化文案
//            return NSLocalizedString(
//                "network_parse_failed",
//                comment: "数据解析失败，请检查接口返回内容"
//            ) + ": \(type(of: target))"
//            
//        default:
//            //  其他错误仍使用私有库默认实现
//            return (self as NetworkErrorDescribing).defaultErrorDescription
//        }
//    }
//    
//    /// 重新指向
//    public var localizedDescription: String {
//        return self.errorDescription ?? ""
//    }
//}

// MARK: - Global Variables & Functions (if necessary)

/// 私有库定义默认本地化描述协议
public protocol NetworkErrorDescribing {
    var defaultErrorDescription: String? { get }
}

/// 自定义网络错误
public enum NetworkError: Error {
    /// 解析映射出错
    case objectMapperError(mapType: Any)
    /// 自定义文案
    case exception(msg: String)
}

/// 默认实现（类似 fallback）
extension NetworkErrorDescribing where Self == NetworkError {
    public var defaultErrorDescription: String? {
        switch self {
        case .objectMapperError(let target):
            return L10n.stringObjMapFail(type(of: target))
        case .exception(let msg):
            return msg
        }
    }
    
    // 默认实现 localizedDescription
    public var localizedDescription: String {
        return self.defaultErrorDescription ?? ""
    }
}

// 默认让 NetworkError 遵循
extension NetworkError: NetworkErrorDescribing {}

// MARK: --
public extension MoyaError {
    /// 返回去掉技术性前缀的本地化错误信息
    var localizedErrorMessage: String {
        switch self {
        case .underlying(let err as AFError, _):
            let desc = (err.underlyingError?.localizedDescription ?? err.localizedDescription)
                .replacingOccurrences(of: "URLSessionTask failed with error: ", with: "")
            return desc
            
        case .underlying(let urlError as URLError, _):
            return urlError.localizedDescription
            
        default:
            return localizedDescription
                .replacingOccurrences(of: "URLSessionTask failed with error: ", with: "")
        }
    }
}
