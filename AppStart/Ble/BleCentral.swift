//
//  BleCentral.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  CBCentralManager 封装层：扫描、连接、多设备注册表。
//  - 扫描结果通过 AsyncStream<BleDiscovery> 推送
//  - 连接生命周期委托给 BlePeripheralConnection
//  - 多产品场景下不在系统层按 Service UUID 过滤（见 scan(products:) 注释）

import Foundation
import CoreBluetooth

/// App 内唯一的 Central 入口，对应一个 `CBCentralManager` 实例。
public final class BleCentral: NSObject {

    public static let shared = BleCentral()

    /// 全局默认配置（单产品 / 非多产品注册场景使用）
    public private(set) var configuration: BleConfiguration
    /// 本轮扫描已发现、且通过 matching 过滤的设备缓存
    public private(set) var discoveredDevices: [BleDiscovery] = []

    private var centralManager: CBCentralManager!
    private var logger: BleLogger
    /// 蓝牙开关状态广播（replayLatest：新订阅者立即拿到当前状态）
    private let centralStateBus = BleAsyncBroadcastStream<CBManagerState>(replayLatest: true)
    private let scanStateBus = BleAsyncBroadcastStream<BleScanState>(replayLatest: true)

    /// peripheral.identifier → 活跃连接句柄
    private var connectionRegistry: [UUID: BlePeripheralConnection] = [:]

    // MARK: - 扫描会话上下文（一次 scan 调用期间有效）

    /// 扫描超时 Task；到期自动 `stopScanning()`
    private var scanTimeoutTask: Task<Void, Never>?
    /// 是否正在 CBCentralManager 扫描中
    private var isScanning = false
    /// 向 `scan()` 返回的 AsyncStream 消费方 yield 发现结果
    private var activeScanContinuation: AsyncStream<BleDiscovery>.Continuation?
    /// 本轮 matching 配置（单产品或 compositeMatching；临时扫描时覆盖全局 configuration）
    private var activeScanConfiguration: BleConfiguration?
    /// 混扫产品列表；`handleDiscovery` 中 resolve 定案与 advParser 解析
    private var activeScanProducts: [BleConfiguration] = []

    public init(configuration: BleConfiguration = BleConfiguration(), centralManager: CBCentralManager? = nil) {
        self.configuration = configuration
        self.logger = BleLogger(isEnabled: configuration.debugLog, tag: configuration.logTag)
        super.init()
        if let centralManager {
            self.centralManager = centralManager
            self.centralManager.delegate = self
        } else {
            self.centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    public func updateConfiguration(_ configuration: BleConfiguration) {
        self.configuration = configuration
        logger = BleLogger(isEnabled: configuration.debugLog, tag: configuration.logTag)
    }

    /// 按已注册/当前扫描的产品配置同步日志（register、scan 时调用）。
    func syncLogger(from configurations: [BleConfiguration]) {
        guard !configurations.isEmpty else { return }
        logger = BleLogger(configurations: configurations)
    }

    /// 蓝牙开关状态；`replayLatest`，新订阅者立即收到当前 `CBManagerState`。
    public func centralStates() async -> AsyncStream<CBManagerState> {
        await centralStateBus.stream()
    }

    /// 扫描生命周期；`.started` / `.stopped`，与 `stopScanning()` 配对。
    public func scanStates() async -> AsyncStream<BleScanState> {
        await scanStateBus.stream()
    }

    public var activeConnections: [BlePeripheralConnection] {
        Array(connectionRegistry.values)
    }

    public func connection(for peripheral: CBPeripheral) -> BlePeripheralConnection? {
        connectionRegistry[peripheral.identifier]
    }

    // MARK: - 扫描

    /// 单配置扫描（matching / advParser 均来自传入的 configuration）。
    public func scan(
        configuration: BleConfiguration? = nil,
        serviceUUIDs: [CBUUID]? = nil,
        timeout: TimeInterval? = nil
    ) -> AsyncStream<BleDiscovery> {
        scan(
            products: [],
            configuration: configuration,
            serviceUUIDs: serviceUUIDs,
            timeout: timeout
        )
    }

    /// 扫描单款或多款产品，使用各 configuration 内的 matching 与 advParser。
    public func scan(
        products: [BleConfiguration],
        timeout: TimeInterval? = nil
    ) -> AsyncStream<BleDiscovery> {
        guard !products.isEmpty else {
            return scan(configuration: nil, timeout: timeout)
        }
        let single = products.count == 1 ? products[0] : nil
        var merged = BleConfiguration()
        merged.matching = products.compositeMatching
        return scan(
            products: products,
            configuration: single ?? merged,
            serviceUUIDs: nil,
            timeout: timeout
        )
    }

    /// 内部统一扫描入口：创建 AsyncStream，在 MainActor 上启动 CBCentralManager 扫描。
    private func scan(
        products: [BleConfiguration],
        configuration: BleConfiguration?,
        serviceUUIDs: [CBUUID]?,
        timeout: TimeInterval?
    ) -> AsyncStream<BleDiscovery> {
        AsyncStream { continuation in
            Task { @MainActor in
                self.activeScanContinuation = continuation
                self.activeScanConfiguration = configuration
                self.activeScanProducts = products
                let logSources = !products.isEmpty ? products : [configuration].compactMap { $0 }
                if !logSources.isEmpty {
                    self.syncLogger(from: logSources)
                }
                await self.startScanning(serviceUUIDs: serviceUUIDs, timeout: timeout)
            }
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.stopScanning()
                }
            }
        }
    }

    // MARK: - 连接

    /// 连接外设并等待 GATT 通道就绪（`.ready`）。
    /// 同一 peripheral 若已在 connecting/connected/ready 状态，复用已有连接对象。
    /// - Parameter timeout: 建连 + GATT ready 总超时（由上层传入；App 推荐走 `BleSession.connect` 默认 15s）。
    public func connect(
        to peripheral: CBPeripheral,
        configuration: BleConfiguration? = nil,
        timeout: TimeInterval
    ) async throws -> BlePeripheralConnection {
        let resolvedConfiguration = configuration ?? self.configuration
        syncLogger(from: [resolvedConfiguration])
        if let existing = connectionRegistry[peripheral.identifier] {
            if case .ready = existing.currentState { return existing }
            if case .connected = existing.currentState { return existing }
        }
        let connection = makeConnection(for: peripheral, configuration: resolvedConfiguration)
        connectionRegistry[peripheral.identifier] = connection
        connection.beginWaitingForReady()
        connection.startConnectionTimeout(timeout)
        performConnect(peripheral)
        try await connection.waitUntilReady()
        return connection
    }

    public func disconnect(_ connection: BlePeripheralConnection) {
        connection.disconnect()
    }

    /// 由 BlePeripheralConnection / BleReconnectHandler 调用，发起底层 connect。
    func performConnect(_ peripheral: CBPeripheral) {
        logger.log("开始连接: \(peripheral.name ?? "未知")")
        centralManager.connect(peripheral, options: nil)
    }

    func performDisconnect(_ peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func isPhysicallyConnected(_ peripheral: CBPeripheral?) -> Bool {
        guard let peripheral else { return false }
        return peripheral.state == .connected
    }

    /// 意外断开后从注册表移除，避免持有失效连接。
    func unregisterConnectionIfNeeded(_ connection: BlePeripheralConnection) {
        connectionRegistry.removeValue(forKey: connection.peripheral.identifier)
    }

    private func makeConnection(for peripheral: CBPeripheral, configuration: BleConfiguration) -> BlePeripheralConnection {
        BlePeripheralConnection(
            peripheral: peripheral,
            configuration: configuration,
            logger: BleLogger(isEnabled: configuration.debugLog, tag: configuration.logTag),
            central: self
        )
    }

    /// 启动 CBCentralManager 扫描。`serviceUUIDs` 为 nil 时全量扫描，由 matching 策略过滤。
    private func startScanning(
        serviceUUIDs: [CBUUID]?,
        timeout: TimeInterval?
    ) async {
        guard centralManager.state == .poweredOn else { return }
        if isScanning { return }
        isScanning = true
        discoveredDevices.removeAll()
        await scanStateBus.yield(.started)
        logger.log("开始扫描")
        centralManager.scanForPeripherals(withServices: serviceUUIDs, options: nil)

        scanTimeoutTask?.cancel()
        if let timeout {
            scanTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.stopScanning()
            }
        }
    }

    /// 清理扫描会话上下文并 finish AsyncStream。
    public func stopScanning() {
        guard isScanning else { return }
        isScanning = false
        centralManager.stopScan()
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        activeScanConfiguration = nil
        activeScanProducts = []
        activeScanContinuation?.finish()
        activeScanContinuation = nil
        Task { await scanStateBus.yield(.stopped) }
        logger.log("扫描停止")
    }

    /// 扫描发现回调的核心处理链（混扫）：
    /// 1. resolve 定案是哪款产品 → 2. advParser 解析广播 → 3. 组装 BleDiscovery → 4. yield（同设备可多次刷新 RSSI）
    private func handleDiscovery(
        _ peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        // 1. 定案：混扫时 resolve 到具体 BleConfiguration（register 顺序优先）；临时扫描走 matching
        let resolvedConfiguration: BleConfiguration?
        if !activeScanProducts.isEmpty {
            guard let resolved = activeScanProducts.resolve(
                peripheral: peripheral,
                advertisementData: advertisementData
            ) else { return }
            resolvedConfiguration = resolved
        } else {
            let filterConfiguration = activeScanConfiguration ?? configuration
            guard filterConfiguration.matching.shouldConnect(
                to: peripheral,
                advertisementData: advertisementData
            ) else { return }
            resolvedConfiguration = nil
        }

        let advertisement = BlePeripheralData(advertisementData: advertisementData, rssi: rssi)

        // 2. 用「那一款」的 advParser 解析；失败 parsedData = nil，展示由业务层 formatter 处理
        let parsedData = resolvedConfiguration?.parseAdvertisement(advertisementData)

        // 3. 组装 discovery；connect(discovery:) 直接使用 discovery.configuration
        let discovery = BleDiscovery(
            peripheral: peripheral,
            advertisement: advertisement,
            parsedData: parsedData,
            configuration: resolvedConfiguration
        )

        // 4. 同 identifier 更新缓存并 yield；首次发现打日志
        let isNewDevice: Bool
        if let index = discoveredDevices.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier }) {
            discoveredDevices[index] = discovery
            isNewDevice = false
        } else {
            discoveredDevices.append(discovery)
            isNewDevice = true
        }

        if isNewDevice, let detail = parsedDataLogDescription(parsedData) {
            logger.log("发现外设: \(detail)")
        }
        activeScanContinuation?.yield(discovery)
    }

    /// 发现日志：优先 parsedData.mac，否则将 parsedData 转为字符串
    private func parsedDataLogDescription(_ parsedData: Any?) -> String? {
        guard let parsedData else { return nil }
        if let text = parsedData as? String, !text.isEmpty {
            return text
        }
        let mirror = Mirror(reflecting: parsedData)
        if let mac = mirror.children.first(where: { $0.label == "mac" })?.value as? String, !mac.isEmpty {
            return mac
        }
        return String(describing: parsedData)
    }
}

// MARK: - CBCentralManagerDelegate
// CoreBluetooth 回调统一转发到 MainActor，再分发给连接句柄或扫描处理链。

extension BleCentral: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.log("蓝牙状态: \(central.state.rawValue)")
        Task { await centralStateBus.yield(central.state) }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            self.handleDiscovery(peripheral, advertisementData: advertisementData, rssi: RSSI)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.log("已连接: \(peripheral.name ?? "未知")")
        connectionRegistry[peripheral.identifier]?.handleConnected()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.log("已断开: \(peripheral.name ?? "未知")")
        connectionRegistry[peripheral.identifier]?.handleDisconnected(error: error)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.log("连接失败: \(peripheral.name ?? "未知")")
        connectionRegistry[peripheral.identifier]?.handleConnectFailed(error)
    }
}
