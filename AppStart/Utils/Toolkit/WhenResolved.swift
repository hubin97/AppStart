//
//  Extension+PromiseKit.swift
//  AppStart
//
//  Created by hubin.h on 2025/9/28.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation
import PromiseKit

// MARK: - Global Variables & Functions (if necessary)
// PromiseKit的 when(resolved:) API 仅支持`单一`参数源, 见
// public func when<T>(resolved promises: Promise<T>...) -> Guarantee<[Result<T>]>
// public func when<T>(resolved promises: [Promise<T>]) -> Guarantee<[Result<T>]>
// 扩展when(resolved:)支持元组2~5个不同类型入参

// MARK: - when(resolved:) for 2 promises
public func when<A, B>(resolved p1: Promise<A>, _ p2: Promise<B>) -> Promise<(A?, B?)> {
    let rp1 = p1.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp2 = p2.map { Optional.some($0) }.recover { _ in .value(nil) }

    return when(fulfilled: rp1, rp2)
}

// MARK: - when(resolved:) for 3 promises
public func when<A, B, C>(resolved p1: Promise<A>, _ p2: Promise<B>, _ p3: Promise<C>) -> Promise<(A?, B?, C?)> {
    let rp1 = p1.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp2 = p2.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp3 = p3.map { Optional.some($0) }.recover { _ in .value(nil) }

    return when(fulfilled: rp1, rp2, rp3)
}

// MARK: - when(resolved:) for 4 promises
public func when<A, B, C, D>(resolved p1: Promise<A>, _ p2: Promise<B>, _ p3: Promise<C>, _ p4: Promise<D>) -> Promise<(A?, B?, C?, D?)> {
    let rp1 = p1.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp2 = p2.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp3 = p3.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp4 = p4.map { Optional.some($0) }.recover { _ in .value(nil) }

    return when(fulfilled: rp1, rp2, rp3, rp4)
}

// MARK: - when(resolved:) for 5 promises
public func when<A, B, C, D, E>(resolved p1: Promise<A>, _ p2: Promise<B>, _ p3: Promise<C>, _ p4: Promise<D>, _ p5: Promise<E>) -> Promise<(A?, B?, C?, D?, E?)> {
    let rp1 = p1.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp2 = p2.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp3 = p3.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp4 = p4.map { Optional.some($0) }.recover { _ in .value(nil) }
    let rp5 = p5.map { Optional.some($0) }.recover { _ in .value(nil) }

    return when(fulfilled: rp1, rp2, rp3, rp4, rp5)
}
