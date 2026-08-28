//
//  BleAsyncBroadcastStream.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
// 这实际上是用 AsyncStream 手动实现了 RxSwift 的 BehaviorSubject 功能。如果引入 swift-async-algorithms ，可以简化为：
// import AsyncAlgorithms

// public actor BleAsyncBroadcastStream<Element> {
//     private let channel = AsyncChannel<Element>()
//     private var latest: Element?
//     private let replayLatest: Bool
    
//     public func stream() -> AsyncStream<Element> {
//         let id = UUID()
//         return AsyncStream { continuation in
//             if replayLatest, let latest {
//                 continuation.yield(latest)
//             }
//             Task {
//                 for await element in channel {
//                     continuation.yield(element)
//                 }
//             }
//         }
//     }
    
//     public func yield(_ element: Element) {
//         latest = element
//         channel.send(element)
//     }
// }
//
//  多订阅者广播流：一个事件源可同时推送给多个 AsyncStream 消费者。
//  replayLatest 模式下新订阅者立即收到最近一次值（用于状态类事件）。

import Foundation

public actor BleAsyncBroadcastStream<Element> {

    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    /// replayLatest 时缓存最近一次 yield 的值
    private var latest: Element?
    private let replayLatest: Bool

    public init(replayLatest: Bool = false) {
        self.replayLatest = replayLatest
    }

    public func stream() -> AsyncStream<Element> {
        let id = UUID()
        var capturedContinuation: AsyncStream<Element>.Continuation?
        let stream = AsyncStream<Element> { continuation in
            capturedContinuation = continuation
        }
        guard let continuation = capturedContinuation else { return stream }
        continuation.onTermination = { @Sendable _ in
            Task { await self.removeContinuation(id: id) }
        }
        // AsyncStream builder 同步执行；在 actor 方法返回前完成注册，避免非 replay 的首个 Notify
        // 恰好落在「stream 已返回、异步 addContinuation 尚未执行」窗口而丢失。
        continuations[id] = continuation
        if replayLatest, let latest {
            continuation.yield(latest)
        }
        return stream
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    public func yield(_ element: Element) {
        latest = element
        continuations.values.forEach { $0.yield(element) }
    }

    public func finish() {
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }
}