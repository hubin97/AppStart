//
//  BlePriorityQueue.swift
//  AppStart
//
//  Created by hubin.h on 2024/11/28.
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  支持优先级排序的 FIFO 队列，用于写指令调度。

import Foundation

public struct BlePriorityQueue<Element: Comparable & Equatable> {

    public enum Order {
        case ascending   // 小值优先
        case descending  // 大值优先
    }

    private(set) var elements: [Element] = []
    private let order: Order?

    public var isEmpty: Bool { elements.isEmpty }
    public var size: Int { elements.count }

    public init(order: Order? = nil) {
        self.order = order
    }

    public func peek() -> Element? {
        elements.first
    }

    public mutating func enqueue(_ element: Element, at index: Int? = nil) {
        if let index, order == nil {
            guard index >= 0, index <= elements.count else {
                fatalError("Index out of bounds.")
            }
            elements.insert(element, at: index)
        } else {
            elements.append(element)
        }
        if let order {
            elements.sort { lhs, rhs in
                order == .ascending ? (lhs < rhs) : (lhs > rhs)
            }
        }
    }

    @discardableResult
    public mutating func dequeue() -> Element? {
        guard !elements.isEmpty else { return nil }
        return elements.removeFirst()
    }

    public func contains(_ element: Element) -> Bool {
        elements.contains(element)
    }

    public mutating func remove(_ element: Element) {
        elements.removeAll { $0 == element }
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Element {
        elements.remove(at: index)
    }
}

extension BlePriorityQueue: CustomDebugStringConvertible {
    public var debugDescription: String {
        elements.debugDescription
    }
}
