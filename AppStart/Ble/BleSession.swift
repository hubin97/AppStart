//
//  BleSession.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  跨页面 Session 层：产品协议配置 + 当前活跃连接。
//  配置跟「BleConfiguration」走，不跟「页面」走；

import Foundation
import CoreBluetooth

/// 跨页面共享蓝牙会话：持有 `BleCentral`、产品协议配置与当前活跃连接。
public final class BleSession {

    public static let shared = BleSession()

    public var central: BleCentral
    /// 当前会话支持的全部产品协议配置。
    ///
    /// 数组顺序也是混扫 resolve 的匹配优先级：多个配置同时命中时，位置靠前者优先。
    public private(set) var configurations: [BleConfiguration] = []

    /// 当前页面关心的主连接（多设备场景下另有 `activeConnections`）
    public var activeConnection: BlePeripheralConnection?
    public var activeConnections: [BlePeripheralConnection] {
        central.activeConnections
    }

    public init(central: BleCentral = .shared) {
        self.central = central
    }

    /// 配置当前会话支持的全部产品协议。
    ///
    /// 每次调用都会整体替换现有配置，不追加也不自动去重；重复传入同一数组时结果保持一致。
    /// 单产品与多产品使用同一入口，App 应在启动配置阶段调用。
    public func configure(with configurations: [BleConfiguration]) {
        self.configurations = configurations
        central.syncLogger(from: configurations)
    }

    // MARK: - 扫描

    /// 扫描单款产品（使用 configuration 内绑定的 matching 与 advParser）。
    public func scan(configuration: BleConfiguration, timeout: TimeInterval? = nil) -> AsyncStream<BleDiscovery> {
        central.scan(products: [configuration], timeout: timeout)
    }

    /// 扫描 `configurations` 中指定下标的产品。
    public func scan(at index: Int, timeout: TimeInterval? = nil) -> AsyncStream<BleDiscovery>? {
        guard configurations.indices.contains(index) else { return nil }
        return scan(configuration: configurations[index], timeout: timeout)
    }

    /// 扫描 `configurations` 中的全部产品；各设备经 resolve 定案后使用对应 advParser。
    public func scanAllProducts(timeout: TimeInterval? = nil) -> AsyncStream<BleDiscovery> {
        guard !configurations.isEmpty else {
            return AsyncStream { $0.finish() }
        }
        return central.scan(products: configurations, timeout: timeout)
    }

    /// 停止当前扫描会话；业务层无需下探 `session.central`。
    public func stopScanning() {
        central.stopScanning()
    }

    public func connection(for peripheral: CBPeripheral) -> BlePeripheralConnection? {
        central.connection(for: peripheral)
    }

    // MARK: - 连接

    /// 从扫描结果连接；使用 `effectiveConfiguration`（含 GattProfile merge）。
    /// - Parameters:
    ///   - timeout: 建连 + GATT ready 总超时，默认 15 秒。
    ///   - setAsActive: 是否设为 `activeConnection`；多设备时可设为 false 保留原主连接。
    public func connect(
        discovery: BleDiscovery,
        timeout: TimeInterval = 15,
        setAsActive: Bool = true
    ) async throws -> BlePeripheralConnection {
        guard let effectiveConfiguration = discovery.effectiveConfiguration else {
            throw BleError.configurationNotResolved
        }
        let connection = try await central.connect(
            to: discovery.peripheral,
            configuration: effectiveConfiguration,
            timeout: timeout
        )
        if setAsActive {
            activeConnection = connection
        }
        return connection
    }

    /// 断开并清空当前主连接；多设备场景仍可通过具体 connection 单独断开。
    public func disconnectActiveConnection() {
        activeConnection?.disconnect()
        activeConnection = nil
    }
}
