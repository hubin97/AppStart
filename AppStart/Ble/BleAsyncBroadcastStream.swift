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
        return AsyncStream { continuation in
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(id: id) }
            }
            Task { await self.addContinuation(id: id, continuation: continuation) }
        }
    }

    /// 新订阅者注册；若 replayLatest 则立即补发 latest
    private func addContinuation(id: UUID, continuation: AsyncStream<Element>.Continuation) {
        continuations[id] = continuation
        if replayLatest, let latest {
            continuation.yield(latest)
        }
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