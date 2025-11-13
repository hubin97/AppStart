//
//  NetworkRequest.swift
//  HBSwiftKit_Example
//
//  Created by Hubin_Huang on 2022/3/28.
//  Copyright © 2020 云图数字. All rights reserved.

// Moya文档 https://github.com/Moya/Moya/tree/master/docs/Examples
// Moya解析 https://dirtmelon.github.io/posts/Moya/
// ProgressHUD https://github.com/relatedcode/ProgressHUD

import Moya
import ObjectMapper
import PromiseKit

// MARK: - Helper Functions

/// 创建 stub closure
private func makeStubClosure<T: TargetType>(for target: T) -> MoyaProvider<T>.StubClosure {
    // 补充数据源判断, 有传入sampleData, 设置直接用假数据; 否则用真实数据
    return target.sampleData.isEmpty ? MoyaProvider<T>.neverStub: MoyaProvider<T>.delayedStub(0.3)
}

/// 创建 MoyaProvider
private func makeProvider<T: TargetType>(for target: T, plugins: [PluginType]) -> MoyaProvider<T> {
    let stubClosure = makeStubClosure(for: target)
    return MoyaProvider<T>(stubClosure: stubClosure, plugins: plugins)
}

// MARK: - Public Functions

/// 如果返回的数据并不能直接映射, 使用插件预处理
/// func process(_ result: Result<Moya.Response, MoyaError>, target: TargetType) -> Result<Moya.Response, MoyaError>

/// 获取JSONString
/// - Parameters:
///   - target: moya target
///   - plugins: moya plugins
/// - Returns: Promise<String>
public func fetchJSONString<T: TargetType>(target: T, plugins: [PluginType] = []) -> Promise<String> {
    return Promise<String>.init { resolver in
        let provider = makeProvider(for: target, plugins: plugins)
        provider.request(target, completion: { result in
            switch result {
            case let .success(response):
                guard let string = String(data: response.data, encoding: .utf8) else {
                    resolver.reject(NetworkError.decodingError(type: String.self))
                    return
                }
                resolver.fulfill(string)
            case let .failure(error):
                resolver.reject(NetworkError.from(error))
            }
        })
    }
}

/// 获取JSONString（旧版本，已废弃）
/// - Parameters:
///   - targetType: target type（冗余参数，已废弃）
///   - target: moya target
///   - plugins: moya plugins
/// - Returns: Promise<String>
/// - Warning: 此方法已废弃，请使用 `fetchJSONString(target:plugins:)` 代替
@available(*, deprecated, message: "targetType 参数已废弃，请使用 fetchJSONString(target:plugins:) 代替; 或者 NetworkFetch.xx")
public func fetchJSONString<T: TargetType>(targetType: T.Type, target: T, plugins: [PluginType]) -> Promise<String> {
    return fetchJSONString(target: target, plugins: plugins)
}

/// 获取指定模型
/// - Parameters:
///   - target: moya target
///   - metaType: model type
///   - plugins: moya plugins
/// - Returns: Promise<M>
public func fetchTargetMeta<T: TargetType, M: Mappable>(target: T, metaType: M.Type, plugins: [PluginType] = []) -> Promise<M> {
    return Promise<M>.init { resolver in
        fetchJSONString(target: target, plugins: plugins).done { result in
            guard let meta = Mapper<M>().map(JSONString: result) else {
                resolver.reject(NetworkError.decodingError(type: metaType.self))
                return
            }
            resolver.fulfill(meta)
        }.catch { error in
            resolver.reject(error)
        }
    }
}

/// 获取指定模型（旧版本，已废弃）
/// - Parameters:
///   - targetType: target type（冗余参数，已废弃）
///   - target: moya target
///   - metaType: model type
///   - plugins: moya plugins
/// - Returns: Promise<M>
/// - Warning: 此方法已废弃，请使用 `fetchTargetMeta(target:metaType:plugins:)` 代替
@available(*, deprecated, message: "targetType 参数已废弃，请使用 fetchTargetMeta(target:metaType:plugins:) 代替; 或者 NetworkFetch.xx")
public func fetchTargetMeta<T: TargetType, M: Mappable>(targetType: T.Type, target: T, metaType: M.Type, plugins: [PluginType]) -> Promise<M> {
    return fetchTargetMeta(target: target, metaType: metaType, plugins: plugins)
}

/// 获取指定模型数组
/// - Parameters:
///   - target: moya target
///   - metaType: model type
///   - plugins: moya plugins
/// - Returns: Promise<[M]>
public func fetchTargetList<T: TargetType, M: Mappable>(target: T, metaType: M.Type, plugins: [PluginType] = []) -> Promise<[M]> {
    return Promise<[M]>.init { resolver in
        fetchJSONString(target: target, plugins: plugins).done { result in
            guard let list = Mapper<M>().mapArray(JSONString: result) else {
                resolver.reject(NetworkError.decodingError(type: metaType.self))
                return
            }
            resolver.fulfill(list)
        }.catch { error in
            resolver.reject(error)
        }
    }
}

/// 获取指定模型数组（旧版本，已废弃）
/// - Parameters:
///   - targetType: target type（冗余参数，已废弃）
///   - target: moya target
///   - metaType: model type
///   - plugins: moya plugins
/// - Returns: Promise<[M]>
/// - Warning: 此方法已废弃，请使用 `fetchTargetList(target:metaType:plugins:)` 代替
@available(*, deprecated, message: "targetType 参数已废弃，请使用 fetchTargetList(target:metaType:plugins:) 代替; 或者 NetworkFetch.xx")
public func fetchTargetList<T: TargetType, M: Mappable>(targetType: T.Type, target: T, metaType: M.Type, plugins: [PluginType]) -> Promise<[M]> {
    return fetchTargetList(target: target, metaType: metaType, plugins: plugins)
}

/// 获取数据带进度
/// - Parameters:
///   - target: moya target
///   - plugins: moya plugins
///   - progressBlock: progress callback
/// - Returns: Promise<String>
public func fetchDataWithProgress<T: TargetType>(target: T, plugins: [PluginType] = [], progressBlock: ProgressBlock? = nil) -> Promise<String> {
    return Promise<String>.init { resolver in
        let provider = makeProvider(for: target, plugins: plugins)
        provider.request(target, progress: progressBlock, completion: { result in
            switch result {
            case let .success(response):
                guard let string = String(data: response.data, encoding: .utf8) else {
                    resolver.reject(NetworkError.decodingError(type: String.self))
                    return
                }
                resolver.fulfill(string)
            case let .failure(error):
                resolver.reject(NetworkError.from(error))
            }
        })
    }
}

/// 获取数据带进度（旧版本，已废弃）
/// - Parameters:
///   - targetType: target type（冗余参数，已废弃）
///   - target: moya target
///   - plugins: moya plugins
///   - progressBlock: progress callback
/// - Returns: Promise<String>
/// - Warning: 此方法已废弃，请使用 `fetchDataWithProgress(target:plugins:progressBlock:)` 代替
@available(*, deprecated, message: "targetType 参数已废弃，请使用 fetchDataWithProgress(target:plugins:progressBlock:) 代替; 或者 NetworkFetch.xx")
public func fetchDataWithProgress<T: TargetType>(targetType: T.Type, target: T, plugins: [PluginType], progressBlock: ProgressBlock? = nil) -> Promise<String> {
    return fetchDataWithProgress(target: target, plugins: plugins, progressBlock: progressBlock)
}

// MARK: - NetworkFetch (Moya + Promise + ObjectMapper)
public enum NetworkFetch {
    
    /// 获取原始 JSON 字符串
    public static func json<T: TargetType>(
        target: T,
        plugins: [PluginType] = []
    ) -> Promise<String> {
        return fetchJSONString(target: target, plugins: plugins)
    }
    
    /// 获取模型对象
    public static func meta<T: TargetType, M: Mappable>(
        target: T,
        metaType: M.Type,
        plugins: [PluginType] = []
    ) -> Promise<M> {
        return fetchTargetMeta(target: target, metaType: metaType, plugins: plugins)
    }
    
    /// 获取模型数组
    public static func list<T: TargetType, M: Mappable>(
        target: T,
        metaType: M.Type,
        plugins: [PluginType] = []
    ) -> Promise<[M]> {
        return fetchTargetList(target: target, metaType: metaType, plugins: plugins)
    }
    
    /// 带进度
    public static func progress<T: TargetType>(
        target: T,
        plugins: [PluginType] = [],
        progress: ProgressBlock? = nil
    ) -> Promise<String> {
        return fetchDataWithProgress(target: target, plugins: plugins, progressBlock: progress)
    }
}

// MARK: - async/await (Moya + async/await + ObjectMapper)
extension NetworkFetch {
    
    // MARK: - 通用执行
    @discardableResult
    private static func perform<T: TargetType>(
        _ target: T,
        plugins: [PluginType] = [],
        progress: ((ProgressResponse) -> Void)? = nil
    ) async throws -> Response {
        let provider = makeProvider(for: target, plugins: plugins)
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(
                target,
                callbackQueue: .main,
                progress: progress,
                completion: { result in
                    switch result {
                    case .success(let response):
                        continuation.resume(returning: response)
                    case .failure(let error):
                        continuation.resume(throwing: NetworkError.from(error))
                    }
                }
            )
        }
    }
    
    /// async/await 获取原始 JSON 字符串
    public static func asyncJson<T: TargetType>(
        target: T,
        plugins: [PluginType] = []
    ) async throws -> String {
        let response = try await perform(target, plugins: plugins)
        guard let json = String(data: response.data, encoding: .utf8) else {
            throw NetworkError.decodingError(type: String.self)
        }
        return json
    }

    /// async/await 获取模型
    public static func asyncMeta<T: TargetType, M: Mappable>(
        target: T,
        metaType: M.Type,
        plugins: [PluginType] = []
    ) async throws -> M {
        let response = try await perform(target, plugins: plugins)
        guard let json = try? response.mapJSON() as? [String: Any],
              let meta = M(JSON: json) else {
            throw NetworkError.decodingError(type: metaType)
        }
        return meta
    }

    /// async/await 获取模型数组
    public static func asyncList<T: TargetType, M: Mappable>(
        target: T,
        metaType: M.Type,
        plugins: [PluginType] = []
    ) async throws -> [M] {
        let response = try await perform(target, plugins: plugins)
        guard let jsonArray = try? response.mapJSON() as? [[String: Any]] else {
            throw NetworkError.decodingError(type: metaType.self)
        }
        return Mapper<M>().mapArray(JSONArray: jsonArray)
    }

    /// async/await 带进度
    public static func asyncProgress<T: TargetType>(
        target: T,
        plugins: [PluginType] = [],
        progress: ProgressBlock? = nil
    ) async throws -> String {
        let response = try await perform(target, plugins: plugins, progress: progress)
        guard let result = String(data: response.data, encoding: .utf8) else {
            throw NetworkError.decodingError(type: String.self)
        }
        return result
    }
}
