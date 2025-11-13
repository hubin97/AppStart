//
//  NetworkAsync.swift
//  LuteBase
//
//  Created by hubin.h on 2025/11/10.
//  Copyright © 2025 路特创新. All rights reserved.

import Foundation
import Moya

/// 调用示例
///
///  // 获取原始 JSON
///  let json = try await NetworkAsync.json(from: APITarget.userInfo)
///
///  // 解码单模型
///  let user: User = try await NetworkAsync.decode(APITarget.userInfo, as: User.self)
///
///  // 解码数组
///  let items: [Article] = try await NetworkAsync.decodeArray(APITarget.articles, as: Article.self)
///
///  // 带进度下载
///  let fileURL = try await NetworkAsync.download(APITarget.file, onProgress: { print($0) })

// MARK: - NetworkAsync (Moya + async/await + Decodable)
public enum NetworkAsync {
    
    // MARK: - Provider 构建
    private static func makeStub<T: TargetType>(for target: T) -> MoyaProvider<T>.StubClosure {
        target.sampleData.isEmpty ? MoyaProvider.neverStub: MoyaProvider.delayedStub(0.3)
    }
    
    private static func makeProvider<T: TargetType>(for target: T, plugins: [PluginType]) -> MoyaProvider<T> {
        MoyaProvider<T>(stubClosure: makeStub(for: target), plugins: plugins)
    }
    
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
}

// MARK: - Public APIs
public extension NetworkAsync {
    
    /// 获取原始 JSON 字符串
    static func json<T: TargetType>(
        from target: T,
        plugins: [PluginType] = []
    ) async throws -> String {
        let response = try await perform(target, plugins: plugins)
        guard let string = String(data: response.data, encoding: .utf8) else {
            throw NetworkError.decodingError(type: String.self)
        }
        return string
    }
    
    /// 获取原始 JSON 字符串（带进度回调）
    static func json<T: TargetType>(
        from target: T,
        plugins: [PluginType] = [],
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> String {
        let response = try await perform(target, plugins: plugins) { progress in
            onProgress?(progress.progress)
        }
        guard let string = String(data: response.data, encoding: .utf8) else {
            throw NetworkError.decodingError(type: String.self)
        }
        return string
    }
    
    /// 解码为单个模型
    static func decode<T: TargetType, M: Decodable>(
        _ target: T,
        as model: M.Type,
        plugins: [PluginType] = []
    ) async throws -> M {
        let response = try await perform(target, plugins: plugins)
        do {
            return try JSONDecoder().decode(M.self, from: response.data)
        } catch {
            throw NetworkError.decodingError(type: M.self)
        }
    }
    
    /// 解码为模型数组
    static func decodeArray<T: TargetType, M: Decodable>(
        _ target: T,
        as model: M.Type,
        plugins: [PluginType] = []
    ) async throws -> [M] {
        let response = try await perform(target, plugins: plugins)
        do {
            return try JSONDecoder().decode([M].self, from: response.data)
        } catch {
            throw NetworkError.decodingError(type: M.self)
        }
    }
    
    /// 下载文件
    static func download<T: TargetType>(
        _ target: T,
        to destination: URL? = nil,
        plugins: [PluginType] = [],
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let response = try await perform(target, plugins: plugins) { progress in
            onProgress?(progress.progress)
        }
        
        // 目标文件路径
        let fileURL = destination ?? {
            let name = response.response?.url?.lastPathComponent ?? UUID().uuidString
            return FileManager.default.temporaryDirectory.appendingPathComponent(name)
        }()
        
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        do {
            try response.data.write(to: fileURL)
            return fileURL
        } catch {
            throw NetworkError.unknown(message: "文件保存失败: \(error.localizedDescription)")
        }
    }
    
    /// 上传
    static func upload<T: TargetType, M: Decodable>(
        _ target: T,
        as type: M.Type,
        plugins: [PluginType] = [],
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> M {
        let response = try await perform(target, plugins: plugins) { progress in
            onProgress?(progress.progress)
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(M.self, from: response.data)
        } catch {
            throw NetworkError.decodingError(type: M.self)
        }
    }
}
