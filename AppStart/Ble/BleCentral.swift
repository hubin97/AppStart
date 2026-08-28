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
    /// 同 peripheral 并发 connect 共享的 in-flight Task
    private var connectTasks: [UUID: Task<BlePeripheralConnection, Error>] = [:]
    private let connectTasksLock = NSLock()

    // MARK: - 扫描会话
    //
    // 一次 `scan()` 调用对应一个 ScanSession，由 `id`（token）标识。
    //
    // 背景：旧实现用 activeScanContinuation / activeScanProducts 等分散字段表示「当前扫描」，
    // 无身份校验，导致三类竞态：
    //   1. 第二次 scan 覆盖 continuation，但 isScanning 为 true 时不重启底层扫描；
    //   2. 旧 stream 的 onTermination 调用 stopScanning，误停新 scan；
    //   3. 旧 timeout Task 到期，同样误停新 scan。
    //
    // 语义（阶段 1 采用「新 scan 替换旧 scan」）：
    //   - replaceScanSession：finish 旧 stream、cancel 旧 timeout，再启动新 session 并 restart 底层 scan；
    //   - stopScanSession(token:)：仅当 activeScanSession.id == token 时才停止（旧 stream 取消/旧超时直接忽略）；
    //   - startScanning(sessionID:)：启动前校验 sessionID，防止已被替换的 session 异步路径误改状态；
    //   - handleDiscovery：只向 activeScanSession.continuation yield。
    //
    // ScanSession 暂作 BleCentral 私有 nested struct，不单独抽文件（与 Central 扫描生命周期强耦合，无第二处复用）。
    private struct ScanSession {
        /// 会话 token；onTermination / 超时回调携带此 id，用于与 activeScanSession 比对
        let id: UUID
        /// 本次 scan 返回的 AsyncStream 消费方
        let continuation: AsyncStream<BleDiscovery>.Continuation
        /// 单配置/临时扫描用的 matching 配置
        var configuration: BleConfiguration?
        /// 混扫产品列表；handleDiscovery 中 resolve 定案与 advParser 解析
        var products: [BleConfiguration]
        /// 仅用于 CoreBluetooth 广播层过滤；产品混扫固定为 nil
        let serviceUUIDs: [CBUUID]?
        /// 从底层真正开始扫描时计时；Central 状态 unknown/resetting 期间不消耗扫描窗口
        let timeout: TimeInterval?
        /// 本次 scan 专属超时 Task；到期调用 stopScanSession(token: id)
        var timeoutTask: Task<Void, Never>?
    }

    /// 当前唯一活跃的扫描会话；新 scan 替换时先 finish 旧 session 再赋值
    private var activeScanSession: ScanSession?
    /// 是否正在 CBCentralManager 扫描中
    private var isScanning = false

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
    /// - Parameter serviceUUIDs: 仅传给 `scanForPeripherals`，按**广播**里的 Service UUID 做系统层过滤；
    ///   `nil` 为全量扫描再走 matching。与 `BleConfiguration.gattProfile.serviceUUIDs`（连上后 `discoverServices`）不是同一份，
    ///   也不可默认复用。日常 / `BleSession` 走 `scan(products:)`，此处保持默认 `nil`；后台扫描或标准 Profile 等逃生口再显式传入。
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
    /// 系统层 `serviceUUIDs` 固定 `nil`（全量扫描），避免与 GATT `gattProfile.serviceUUIDs` 绑死。
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
    /// 新 scan 会 finish 旧 stream 并替换会话；旧 stream 的 onTermination 仅停止对应 token 的会话。
    private func scan(
        products: [BleConfiguration],
        configuration: BleConfiguration?,
        serviceUUIDs: [CBUUID]?,
        timeout: TimeInterval?
    ) -> AsyncStream<BleDiscovery> {
        AsyncStream { continuation in
            let sessionID = UUID()
            Task { @MainActor in
                self.replaceScanSession(
                    id: sessionID,
                    continuation: continuation,
                    products: products,
                    configuration: configuration,
                    serviceUUIDs: serviceUUIDs,
                    timeout: timeout
                )
            }
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.stopScanSession(token: sessionID)
                }
            }
        }
    }

    // MARK: - 连接

    /// 连接外设并等待 GATT 通道就绪（`.ready`）。
    /// 同一 peripheral 若已在 connecting/connected/ready 状态，复用已有连接对象并共享 ready 结果。
    /// - Parameter timeout: 建连 + GATT ready 总超时（由上层传入；App 推荐走 `BleSession.connect` 默认 15s）。
    public func connect(
        to peripheral: CBPeripheral,
        configuration: BleConfiguration? = nil,
        timeout: TimeInterval
    ) async throws -> BlePeripheralConnection {
        let (task, ownsTask) = connectionTask(
            to: peripheral,
            configuration: configuration,
            timeout: timeout
        )
        defer {
            if ownsTask {
                removeConnectionTask(for: peripheral.identifier)
            }
        }
        return try await task.value
    }

    /// 锁只保护极短的 in-flight Task 注册过程；真正的 CoreBluetooth 状态仍在 MainActor 执行。
    private func connectionTask(
        to peripheral: CBPeripheral,
        configuration: BleConfiguration?,
        timeout: TimeInterval
    ) -> (task: Task<BlePeripheralConnection, Error>, ownsTask: Bool) {
        connectTasksLock.lock()
        defer { connectTasksLock.unlock() }
        if let existing = connectTasks[peripheral.identifier] {
            return (existing, false)
        }
        let task = Task<BlePeripheralConnection, Error> { @MainActor [weak self] in
            guard let self else { throw BleError.cancelled }
            return try await self.performConnect(
                to: peripheral,
                configuration: configuration,
                timeout: timeout
            )
        }
        connectTasks[peripheral.identifier] = task
        return (task, true)
    }

    private func removeConnectionTask(for identifier: UUID) {
        connectTasksLock.lock()
        connectTasks.removeValue(forKey: identifier)
        connectTasksLock.unlock()
    }

    private func performConnect(
        to peripheral: CBPeripheral,
        configuration: BleConfiguration?,
        timeout: TimeInterval
    ) async throws -> BlePeripheralConnection {
        guard centralManager.state == .poweredOn else {
            throw BleError.bluetoothUnavailable(centralManager.state)
        }
        let resolvedConfiguration = configuration ?? self.configuration
        syncLogger(from: [resolvedConfiguration])

        if let existing = connectionRegistry[peripheral.identifier] {
            switch existing.currentState {
            case .ready:
                return existing
            case .connecting, .reconnecting, .connected:
                try await existing.waitUntilReady()
                return existing
            case .failed, .timedOut, .disconnected:
                // 复用同一个句柄可同步停止其自动重连，避免「旧 reconnect Task +
                // 新 connection」同时操作同一 CBPeripheral、delegate 回调串线。
                // 同时刷新本次 discovery 的 effectiveConfiguration，兼容固件/子型号动态 GATT。
                existing.updateConfigurationSnapshot(resolvedConfiguration)
                existing.beginWaitingForReady()
                existing.startConnectionTimeout(timeout)
                performConnect(peripheral)
                try await existing.waitUntilReady()
                return existing
            }
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

    /// 意外断开后从注册表移除，避免持有失效连接。
    func unregisterConnectionIfNeeded(_ connection: BlePeripheralConnection) {
        let identifier = connection.peripheral.identifier
        guard connectionRegistry[identifier] === connection else { return }
        connectionRegistry.removeValue(forKey: identifier)
    }

    private func makeConnection(for peripheral: CBPeripheral, configuration: BleConfiguration) -> BlePeripheralConnection {
        BlePeripheralConnection(
            peripheral: peripheral,
            configuration: configuration,
            logger: BleLogger(isEnabled: configuration.debugLog, tag: configuration.logTag),
            central: self
        )
    }

    /// 替换当前扫描会话：finish 旧 stream，启动新 CBCentralManager 扫描。
    private func replaceScanSession(
        id: UUID,
        continuation: AsyncStream<BleDiscovery>.Continuation,
        products: [BleConfiguration],
        configuration: BleConfiguration?,
        serviceUUIDs: [CBUUID]?,
        timeout: TimeInterval?
    ) {
        if let current = activeScanSession {
            finishScanSession(current, emitStopped: true)
        }

        let logSources = !products.isEmpty ? products : [configuration].compactMap { $0 }
        if !logSources.isEmpty {
            syncLogger(from: logSources)
        }

        activeScanSession = ScanSession(
            id: id,
            continuation: continuation,
            configuration: configuration,
            products: products,
            serviceUUIDs: serviceUUIDs,
            timeout: timeout,
            timeoutTask: nil
        )
        startScanning(sessionID: id)
    }

    /// 启动 CBCentralManager 扫描。`serviceUUIDs` 为 nil 时全量扫描，由 matching 策略过滤。
    /// 此处 UUID 只约束广播，不是 GATT 发现目标。
    private func startScanning(sessionID: UUID) {
        guard let session = activeScanSession, session.id == sessionID else { return }
        switch centralManager.state {
        case .poweredOn:
            break
        case .unknown, .resetting:
            // CBCentralManager 初始化/重置期间保留请求，等状态回调到 poweredOn 再启动。
            return
        case .unsupported, .unauthorized, .poweredOff:
            // 非 throwing 的兼容 scan API 无法传递错误；结束 stream，具体原因由 centralStates() 提供。
            stopScanSession(token: sessionID)
            return
        @unknown default:
            stopScanSession(token: sessionID)
            return
        }

        if isScanning {
            centralManager.stopScan()
        }
        isScanning = true
        discoveredDevices.removeAll()
        Task { await scanStateBus.yield(.started) }
        logger.log("开始扫描")
        centralManager.scanForPeripherals(withServices: session.serviceUUIDs, options: nil)

        activeScanSession?.timeoutTask?.cancel()
        if let timeout = session.timeout {
            activeScanSession?.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.stopScanSession(token: sessionID)
            }
        }
    }

    /// 按 token 停止扫描会话；token 不匹配则忽略（旧 stream 取消不得影响新会话）。
    private func stopScanSession(token: UUID) {
        guard activeScanSession?.id == token else { return }
        guard let session = activeScanSession else { return }
        finishScanSession(session, emitStopped: true)
        activeScanSession = nil
    }

    /// 清理扫描会话上下文并 finish AsyncStream。
    public func stopScanning() {
        guard let session = activeScanSession else { return }
        finishScanSession(session, emitStopped: true)
        activeScanSession = nil
    }

    private func finishScanSession(_ session: ScanSession, emitStopped: Bool) {
        session.timeoutTask?.cancel()
        if isScanning {
            isScanning = false
            centralManager.stopScan()
            if emitStopped {
                Task { await scanStateBus.yield(.stopped) }
            }
        }
        session.continuation.finish()
        logger.log("扫描停止")
    }

    /// 扫描发现回调的核心处理链（混扫）：
    /// 1. resolve 定案是哪款产品 → 2. advParser 解析广播 → 3. 组装 BleDiscovery → 4. yield（同设备可多次刷新 RSSI）
    private func handleDiscovery(
        _ peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        guard let session = activeScanSession else { return }

        // 1. 定案：混扫时 resolve 到具体 BleConfiguration（register 顺序优先）；临时扫描走 matching
        let resolvedConfiguration: BleConfiguration?
        if !session.products.isEmpty {
            guard let resolved = session.products.resolve(
                peripheral: peripheral,
                advertisementData: advertisementData
            ) else { return }
            resolvedConfiguration = resolved
        } else {
            let filterConfiguration = session.configuration ?? configuration
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
        session.continuation.yield(discovery)
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

    /// Central 状态变化与扫描会话串行处理：pending 请求在 poweredOn 后启动，
    /// 扫描中途关闭蓝牙则结束当前 stream，避免业务层永久等待。
    private func handleCentralStateChange(_ state: CBManagerState) {
        guard let session = activeScanSession else { return }
        if state == .poweredOn {
            if !isScanning {
                startScanning(sessionID: session.id)
            }
            return
        }
        if isScanning || state == .unsupported || state == .unauthorized || state == .poweredOff {
            stopScanSession(token: session.id)
        }
    }
}

// MARK: - CBCentralManagerDelegate
// CoreBluetooth 回调统一转发到 MainActor，再分发给连接句柄或扫描处理链。

extension BleCentral: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.log("蓝牙状态: \(central.state.rawValue)")
        Task { await centralStateBus.yield(central.state) }
        Task { @MainActor in
            self.handleCentralStateChange(central.state)
        }
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
        Task { @MainActor in
            self.logger.log("已连接: \(peripheral.name ?? "未知")")
            self.connectionRegistry[peripheral.identifier]?.handleConnected()
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            let name = peripheral.name ?? "未知"
            if let error {
                self.logger.log("意外断开: \(name), \(error.localizedDescription)")
            } else {
                self.logger.log("连接已断开（系统未提供错误）: \(name)")
            }
            self.connectionRegistry[peripheral.identifier]?.handleDisconnected(error: error)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.logger.log("连接失败: \(peripheral.name ?? "未知")")
            self.connectionRegistry[peripheral.identifier]?.handleConnectFailed(error)
        }
    }
}
