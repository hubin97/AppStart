//
//  BleSession.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  跨页面 Session 层：产品协议注册表 + 当前活跃连接。
//  配置跟「BleConfiguration」走，不跟「页面」走；

import Foundation
import CoreBluetooth

/// 跨页面共享蓝牙会话：持有 `BleCentral`、产品协议注册表与当前活跃连接。
public final class BleSession {

    public static let shared = BleSession()

    public var central: BleCentral
    /// 已注册的产品协议列表（按注册顺序，混扫 resolve 时先注册者优先）
    private var configurations: [BleConfiguration] = []

    /// 当前页面关心的主连接（多设备场景下另有 `activeConnections`）
    public var activeConnection: BlePeripheralConnection?
    public var activeConnections: [BlePeripheralConnection] {
        central.activeConnections
    }

    /// 已注册的协议配置（按注册顺序）
    public var registeredConfigurations: [BleConfiguration] {
        configurations
    }

    public init(central: BleCentral = .shared) {
        self.central = central
    }

    /// 单产品场景：更新 Central 全局默认配置。
    public func configure(_ configuration: BleConfiguration) {
        central.updateConfiguration(configuration)
    }

    /// 注册单款产品协议。
    public func register(_ configuration: BleConfiguration) {
        configurations.append(configuration)
        central.syncLogger(from: configurations)
    }

    public func register(_ configurations: [BleConfiguration]) {
        configurations.forEach { register($0) }
    }

    // MARK: - 扫描

    /// 扫描单款产品（使用 configuration 内绑定的 matching 与 advParser）。
    public func scan(
        configuration: BleConfiguration,
        timeout: TimeInterval? = nil
    ) -> AsyncStream<BleDiscovery> {
        central.scan(products: [configuration], timeout: timeout)
    }

    /// 扫描某一已注册产品（按注册下标）。
    public func scan(
        at index: Int,
        timeout: TimeInterval? = nil
    ) -> AsyncStream<BleDiscovery>? {
        guard configurations.indices.contains(index) else { return nil }
        return scan(configuration: configurations[index], timeout: timeout)
    }

    /// 一次扫描所有已注册产品；各设备经 resolve 定案后使用对应 advParser。
    public func scanAllProducts(timeout: TimeInterval? = nil) -> AsyncStream<BleDiscovery> {
        guard !configurations.isEmpty else {
            return AsyncStream { $0.finish() }
        }
        return central.scan(products: configurations, timeout: timeout)
    }

    public func connection(for peripheral: CBPeripheral) -> BlePeripheralConnection? {
        central.connection(for: peripheral)
    }

    // MARK: - 连接

    /// 内部连接：由 `connect(discovery:)` 调用，绑定 resolve 后的 configuration。
    private func connect(
        to peripheral: CBPeripheral,
        configuration: BleConfiguration,
        timeout: TimeInterval? = nil
    ) async throws -> BlePeripheralConnection {
        let connection = try await central.connect(to: peripheral, configuration: configuration, timeout: timeout)
        activeConnection = connection
        return connection
    }

    /// 从扫描结果连接；`discovery.configuration` 须已由 resolve 写入（App 唯一推荐入口）。
    public func connect(
        discovery: BleDiscovery,
        timeout: TimeInterval? = nil
    ) async throws -> BlePeripheralConnection {
        guard let configuration = discovery.configuration else {
            throw BleError.configurationNotResolved
        }
        return try await connect(to: discovery.peripheral, configuration: configuration, timeout: timeout)
    }
}
