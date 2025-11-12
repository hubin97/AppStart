//
//  NetworkError.swift
//  AppStart
//
//  Created by hubin.h on 2025/11/10.
//  Copyright © 2025 路特创新. All rights reserved.

import Foundation
import Moya
import Alamofire

/// 业务层扩展示例（可选）
/// 如果需要覆盖某些错误的描述，可以这样实现：
///
/// extension NetworkError {
///     public var errorDescription: String? {
///         switch self {
///         case .decodingError(let type):
///             // 自定义国际化文案
///             return NSLocalizedString(
///                 "network_parse_failed",
///                 comment: "数据解析失败，请检查接口返回内容"
///             ) + ": \(type)"
///         default:
///             // 其他错误使用默认实现
///             return self.defaultErrorDescription
///         }
///     }
/// }
///
///  // 业务模块调用, 遵循`模块内优先`原则
///  func failureHandle(error: MoyaError) {
///    ProgressHUD.dismiss()
///    let networkError = NetworkError.from(error)
///    let errorMessage = networkError.errorDescription ?? networkError.localizedDescription
///    iToast.makeToast(errorMessage)
///   }

// MARK: - Global Variables & Functions (if necessary)

/// 自定义网络错误
public enum NetworkError: LocalizedError {
    // MARK: - 系统层（URLError）
    case networkUnavailable
    case timeout
    case sslUntrusted
    case connectionFailed
    case cancelled
    
    // MARK: - HTTP 层
    case unauthorized
    case forbidden
    case notFound
    case serverError(statusCode: Int)
    case http(statusCode: Int)
    
    // MARK: - 数据解析/编码
    case decodingError(type: Any.Type) // objectMapping / stringMapping / imageMapping
    case encodingError                 // encodableMapping

    // MARK: - 业务层
    case business(code: Int, message: String)

    // MARK: - 其他
    // @available(*, deprecated, message: "Use `requestError(message:)` instead, `exception(msg:)` 语义模糊")
    case exception(msg: String)
    case requestError(message: String)
    case unknown(message: String)
}

/// 提供错误描述
extension NetworkError {
    /// 默认错误描述实现（业务层可覆盖 errorDescription 并调用此方法获取默认值）
    public var defaultErrorDescription: String? {
        switch self {
        // 系统层
        case .networkUnavailable:
            return L10n.stringNetUnavailable
        case .timeout:
            return L10n.stringNetTimeout
        case .sslUntrusted:
            return L10n.stringNetSslUntrusted
        case .connectionFailed:
            return L10n.stringNetConnectFailed
        case .cancelled:
            return L10n.stringNetCancelled
            
        // HTTP 层
        case .unauthorized:
            return L10n.stringNetUnauthorized
        case .forbidden:
            return L10n.stringNetForbidden
        case .notFound:
            return L10n.stringNetNotFound
        case .serverError(let code):
#if DEBUG
            return "\(L10n.stringNetServerError) (\(code))"
#else
            return L10n.stringNetServerError
#endif
        case .http(let code):
#if DEBUG
            return "\(L10n.stringNetHttpError) (\(code))"
#else
            return L10n.stringNetHttpError
#endif
            
        // 编码解析
        case .encodingError:
            return L10n.stringNetEncodingError
        case .decodingError(let type):
#if DEBUG
            return "\(L10n.stringNetDecodingError) (\(type))"
#else
            return L10n.stringNetDecodingError
#endif
            
        // 业务层
        case .business(_, let msg):
            return msg
            
        // 自定义
        case .exception(let msg):
            return msg
        case .requestError(let message):
            return message
        case .unknown(let msg):
            return msg
        }
    }
    
    /// 错误描述（业务层可覆盖此属性，并在需要时调用 defaultErrorDescription 获取默认值）
    public var errorDescription: String? {
        return defaultErrorDescription
    }
}

// MoyaError -> NetworkError
public extension NetworkError {
    
    static func from(_ error: MoyaError) -> NetworkError {
        switch error {
        case .underlying(let err, _):
            if let urlError = err as? URLError {
                return from(urlError)
            }
            if let afError = err as? AFError {
                // 进一步剥离 AFError 下层的 URL 错误
                if let underlying = afError.underlyingError as? URLError {
                    return from(underlying)
                }
                return .unknown(message: afError.localizedDescription)
            }
            // 非 AF/URL 错误，归类为未知
            return .unknown(message: err.localizedDescription)
        case .statusCode(let response):
            return from(statusCode: response.statusCode)
        case .objectMapping(_, _), .stringMapping(_), .imageMapping(_), .jsonMapping(_):
            return .decodingError(type: Any.self)
        case .encodableMapping(_), .parameterEncoding(_):
            return .encodingError
        case .requestMapping(let msg):
            return .requestError(message: msg)
        }
    }
    
    static func from(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet:
            return .networkUnavailable
        case .timedOut:
            return .timeout
        case .cannotConnectToHost:
            return .connectionFailed
        case .serverCertificateUntrusted,
                .serverCertificateHasBadDate,
                .serverCertificateHasUnknownRoot:
            return .sslUntrusted
        case .cancelled:
            return .cancelled
        default:
            return .unknown(message: error.localizedDescription)
        }
    }
    
    static func from(statusCode: Int) -> NetworkError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 500...599:
            return .serverError(statusCode: statusCode)
        default:
            return .http(statusCode: statusCode)
        }
    }
}

// MARK: --
public extension MoyaError {
    /// 简单处理, 仅去掉技术性前缀的本地化错误信息
    var localizedErrorMessage: String {
        let message: String
        
        switch self {
        case .underlying(let error, _):
            if let afError = error as? AFError {
                message = afError.underlyingError?.localizedDescription ?? afError.localizedDescription
            } else if let urlError = error as? URLError {
                message = urlError.localizedDescription
            } else {
                message = error.localizedDescription
            }
        default:
            message = self.localizedDescription
        }
        
        // 清理多余的技术性前缀
        return message
            .replacingOccurrences(of: "URLSessionTask failed with error: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 分层处理, 区分错误提示, 业务页面显示
    var userErrorMessage: String {
        return NetworkError.from(self).errorDescription ?? ""
    }
}
