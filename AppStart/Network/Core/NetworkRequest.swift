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

/// 如果返回的数据并不能直接映射, 使用插件预处理
/// func process(_ result: Result<Moya.Response, MoyaError>, target: TargetType) -> Result<Moya.Response, MoyaError>

/// 获取JSONString
/// - Returns: Promise<String>
public func fetchJSONString<T: TargetType>(targetType: T.Type, target: T, plugins: [PluginType]) -> Promise<String> {
    return Promise<String>.init { resolver in
        // FIXME: 补充数据源判断, 有传入sampleData, 设置直接用假数据; 否则用真实数据
        let stubClosure = target.sampleData.isEmpty ? MoyaProvider<T>.neverStub: MoyaProvider<T>.delayedStub(0.3)
        MoyaProvider(stubClosure: stubClosure, plugins: plugins).request(target, completion: { result in
            switch result {
            case let .success(response):
                guard let string = String(data: response.data, encoding: .utf8) else {
                    resolver.reject(NetworkError.decodingError(type: String.self))
                    return
                }
                resolver.fulfill(string)
            case let .failure(error):
                resolver.reject(error)
            }
        })
    }
}

/// 获取指定模型
/// - Returns: Promise<M>
public func fetchTargetMeta<T: TargetType, M: Mappable>(targetType: T.Type, target: T, metaType: M.Type, plugins: [PluginType]) -> Promise<M> {
    return Promise<M>.init { resolver in
        fetchJSONString(targetType: targetType, target: target, plugins: plugins).done { result in
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

/// 获取指定模型数组
/// - Returns: Promise<[M]>
public func fetchTargetList<T: TargetType, M: Mappable>(targetType: T.Type, target: T, metaType: M.Type, plugins: [PluginType]) -> Promise<[M]> {
    return Promise<[M]>.init { resolver in
        fetchJSONString(targetType: targetType, target: target, plugins: plugins).done { result in
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

/// 获取数据带进度
public func fetchDataWithProgress<T: TargetType>(targetType: T.Type, target: T, plugins: [PluginType], progressBlock: ProgressBlock? = nil) -> Promise<String> {
    return Promise<String>.init { resolver in
        MoyaProvider(plugins: plugins).request(target, progress: progressBlock, completion: { result in
            switch result {
            case let .success(response):
                guard let string = String(data: response.data, encoding: .utf8) else {
                    resolver.reject(NetworkError.decodingError(type: String.self))
                    return
                }
                resolver.fulfill(string)
            case let .failure(error):
                resolver.reject(error)
            }
        })
    }
}
