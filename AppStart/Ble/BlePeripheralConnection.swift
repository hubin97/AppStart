//
//  BlePeripheralConnection.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  单设备连接句柄：状态机 + GATT 发现 + 写队列 + 可选自动重连。
//
//  状态流转：connecting → connected → ready
//           ↘ failed / timedOut
//           ↘ disconnected

import Foundation
import CoreBluetooth

/// 单个外设的连接生命周期管理，连接时绑定 `BleConfiguration` 快照。
public final class BlePeripheralConnection: NSObject {

    public let id = UUID()
    public let peripheral: CBPeripheral

    /// 连接时绑定的协议快照，后续 register 变更不影响已建立连接
    private var configuration: BleConfiguration
    private var logger: BleLogger
    private let stateBus = BleAsyncBroadcastStream<BlePeripheralState>(replayLatest: true)
    /// Notify 特征值更新广播（不 replay，仅推送增量）
    private let updateBus = BleAsyncBroadcastStream<BleCharacteristicUpdate>(replayLatest: false)
    private var gattSetup: BleGattSetup
    /// 配置为 `.serialized` 时启用，负责 ACK 匹配与串行写
    private var writeQueue: BleWriteCommandQueue?
    private var reconnectHandler: BleReconnectHandler?
    /// GATT 就绪后缓存的主 write 特征，供 `write(_:)` 使用
    private var writeChar: CBCharacteristic?
    /// `connect` 挂起等待 `.ready` 的 continuation 集合（同设备并发 connect 共享）
    private var connectContinuations: [CheckedContinuation<Void, Error>] = []
    /// 保存本轮 attempt 终态，解决 delegate 在 waiter 注册前完成时的先后竞态。
    private var connectionResult: Result<Void, Error>?
    private var connectionTimeoutTask: Task<Void, Never>?
    /// `withoutResponse` 背压等待者；由 peripheralIsReady 回调统一恢复。
    private var writeCapacityContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private let writeCapacityLock = NSLock()
    private var userInitiatedDisconnect = false
    /// 自动重连循环存续期间保持为 true，避免单次失败短暂暴露为最终失败状态。
    private var isAutoReconnecting = false

    weak var central: BleCentral?

    private(set) public var currentState: BlePeripheralState = .connecting {
        didSet {
            Task { await stateBus.yield(currentState) }
        }
    }

    /// 仅 `.ready` 状态允许业务写入，避免重连期间误用上一条链路缓存的特征。
    public var isReady: Bool {
        if case .ready = currentState { return true }
        return false
    }

    /// 建连时解析并冻结的产品配置；业务展示无需再根据 Service UUID 反推产品。
    public var configurationSnapshot: BleConfiguration {
        configuration
    }

    // MARK: - Init

    init(peripheral: CBPeripheral, configuration: BleConfiguration, logger: BleLogger, central: BleCentral) {
        self.peripheral = peripheral
        self.configuration = configuration
        self.logger = logger
        self.central = central
        self.gattSetup = BleGattSetup(configuration: configuration, logger: logger)
        super.init()
        configureRuntimeComponents()
    }

    /// 终态句柄被新 discovery 复用时刷新完整协议快照；ready 链路仍保持建连时快照不变。
    func updateConfigurationSnapshot(_ configuration: BleConfiguration) {
        self.configuration = configuration
        let logger = BleLogger(isEnabled: configuration.debugLog, tag: configuration.logTag)
        self.logger = logger
        gattSetup = BleGattSetup(configuration: configuration, logger: logger)
        configureRuntimeComponents()
    }

    private func configureRuntimeComponents() {
        writeQueue?.cancelAll()
        reconnectHandler?.stop()
        writeQueue = nil
        reconnectHandler = nil

        // 按配置初始化写队列（serialized 模式：ACK 匹配 + 优先级 + 超时）
        if case .serialized(let matcher, let timeout, let order) = configuration.writeQueue {
            let queue = BleWriteCommandQueue(
                ackMatcher: matcher,
                defaultTimeout: timeout,
                order: order,
                logger: logger,
                send: { [weak self] command in
                    guard let self else { throw BleError.cancelled }
                    try await self.sendValue(
                        command.data,
                        to: command.writeChar,
                        type: command.writeType
                    )
                }
            )
            writeQueue = queue
        }

        // 按配置初始化自动重连（意外断开 / 连接失败时触发）
        if configuration.reconnect.enabled {
            let handler = BleReconnectHandler(policy: configuration.reconnect, logger: logger)
            handler.reconnect = { [weak self] attempt, maximumAttempts in
                guard let self else { return false }
                return await Task { @MainActor in
                    await self.performReconnectAttempt(
                        timeout: self.configuration.reconnect.attemptTimeout,
                        attempt: attempt,
                        maximumAttempts: maximumAttempts
                    )
                }.value
            }
            handler.onPhaseChange = { [weak self] phase in
                guard let self else { return }
                Task { @MainActor in
                    switch phase {
                    case .started:
                        break
                    case .stopped(.success):
                        self.isAutoReconnecting = false
                    case .stopped(.exhausted):
                        self.isAutoReconnecting = false
                        self.updateState(.timedOut)
                        // 重连耗尽后取消系统层挂起的 connect，避免设备再次上线时被动连上
                        self.central?.performDisconnect(self.peripheral)
                        self.central?.unregisterConnectionIfNeeded(self)
                    }
                }
            }
            reconnectHandler = handler
        }
    }

    // MARK: - Streams

    /// 订阅连接状态机；新订阅者会立即收到当前状态（replayLatest）。
    /// 用法：`for await state in await connection.states() { ... }`
    public func states() async -> AsyncStream<BlePeripheralState> {
        await stateBus.stream()
    }

    /// 订阅 Notify 回包；`uuid == nil` 时按主通道 notify UUID 过滤（未配置则全量）。
    /// 用法：`for await update in await connection.characteristicUpdates() { ... }`
    public func characteristicUpdates(matching uuid: CBUUID? = nil) async -> AsyncStream<BleCharacteristicUpdate> {
        let stream = await updateBus.stream()
        let filterUUID = uuid ?? configuration.gattProfile.notifyCharUUID
        guard let filterUUID else { return stream }
        return AsyncStream { continuation in
            let task = Task {
                for await update in stream {
                    guard !Task.isCancelled else { break }
                    if BleUUID.matches(update.characteristic.uuid, filterUUID) {
                        continuation.yield(update)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Connection

    /// 重置连接状态，在每次 `connect` 开始前调用。
    func beginWaitingForReady() {
        prepareForConnectionAttempt(stopReconnect: true)
    }

    private func prepareForConnectionAttempt(stopReconnect: Bool) {
        userInitiatedDisconnect = false
        if stopReconnect {
            isAutoReconnecting = false
            reconnectHandler?.prepareForManualConnection()
        }
        writeQueue?.cancelAll()
        cancelWriteCapacityWaiters()
        // 旧 GATT 缓存只属于上一条物理链路；connecting/connected 阶段禁止继续使用。
        writeChar = nil
        connectionResult = nil
        if stopReconnect {
            updateState(.connecting)
        }
    }

    /// 挂起直到 GATT 通道就绪（`.ready`）或失败/超时。
    func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if let connectionResult {
                continuation.resume(with: connectionResult)
                return
            }
            connectContinuations.append(continuation)
        }
    }

    func startConnectionTimeout(_ timeout: TimeInterval) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.handleConnectionTimeout()
        }
    }

    /// CBCentralManager 回调：物理连接已建立，开始 GATT 服务发现。
    func handleConnected() {
        guard !userInitiatedDisconnect, connectionResult == nil else {
            central?.performDisconnect(peripheral)
            return
        }
        peripheral.delegate = self
        updateState(.connected)
        gattSetup.beginServiceDiscovery(on: peripheral)
    }

    func handleConnectFailed(_ error: Error?) {
        guard connectionResult == nil else { return }
        cancelConnectionTimeout()
        if !isAutoReconnecting {
            updateState(.failed(error))
        }
        completeWaitingForReady(with: .failure(BleError.connectionFailed(error)))
        reconnectHandler?.notifyConnectFailed()
    }

    /// 区分用户主动断开 vs 意外断开，决定是否触发自动重连。
    func handleDisconnected(error: Error?) {
        cancelConnectionTimeout()
        writeQueue?.cancelAll()
        cancelWriteCapacityWaiters()

        let unexpectedError = error ?? NSError(
            domain: "BlePeripheralConnection",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "外设断开连接，系统未提供错误"]
        )
        let connectError: Error = userInitiatedDisconnect
            ? BleError.cancelled
            : BleError.connectionFailed(unexpectedError)
        completeWaitingForReady(with: .failure(connectError))

        if userInitiatedDisconnect {
            central?.unregisterConnectionIfNeeded(self)
            updateState(.disconnected(.userInitiated))
            return
        }
        if isAutoReconnecting {
            return
        }
        // CoreBluetooth 的 error == nil 只表示系统没有附带错误，不等于 App 主动断开。
        // 主动性只由 disconnect() 设置的 userInitiatedDisconnect 判定。
        updateState(.disconnected(.unexpected(unexpectedError)))
        reconnectHandler?.notifyUnexpectedDisconnect()
    }

    /// 用户主动断开；不触发自动重连，并清空写队列。
    public func disconnect() {
        userInitiatedDisconnect = true
        reconnectHandler?.notifyUserDisconnect()
        writeQueue?.cancelAll()
        cancelWriteCapacityWaiters()
        central?.performDisconnect(peripheral)
    }

    private func handleConnectionTimeout() {
        if !isAutoReconnecting {
            updateState(.timedOut)
        }
        completeWaitingForReady(with: .failure(BleError.connectionTimeout))
        central?.performDisconnect(peripheral)
    }

    /// 自动重连与手动 connect 共用同一 ready barrier，但不能在每次 attempt 开始时停止重连循环本身。
    @MainActor
    private func performReconnectAttempt(
        timeout: TimeInterval,
        attempt: Int,
        maximumAttempts: Int
    ) async -> Bool {
        guard !userInitiatedDisconnect else { return false }
        isAutoReconnecting = true
        prepareForConnectionAttempt(stopReconnect: false)
        updateState(.reconnecting(attempt: attempt, maximumAttempts: maximumAttempts))
        startConnectionTimeout(timeout)
        central?.performConnect(peripheral)
        do {
            try await waitUntilReady()
            return true
        } catch {
            return false
        }
    }

    private func updateState(_ state: BlePeripheralState) {
        currentState = state
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
    }

    private func completeWaitingForReady(with result: Result<Void, Error>) {
        cancelConnectionTimeout()
        connectionResult = result
        let continuations = connectContinuations
        connectContinuations = []
        switch result {
        case .success:
            continuations.forEach { $0.resume() }
        case .failure(let error):
            continuations.forEach { $0.resume(throwing: error) }
        }
    }

    /// GATT 发现及 Notify barrier 完成后推进状态；失败统一映射为建链错误。
    private func finishGattSetup(_ result: BleGattSetup.Result) {
        // timeout / disconnect 后到达的旧 GATT 回调不可覆盖本轮终态。
        guard connectionResult == nil else { return }
        switch result {
        case .failure(let error):
            if !isAutoReconnecting {
                updateState(.failed(error))
            }
            let connectionError = (error as? BleError) ?? BleError.channelSetupFailed(error)
            completeWaitingForReady(with: .failure(connectionError))
        case .ready(let writeChar, let service):
            self.writeChar = writeChar
            let info = BleChannelReadyInfo(peripheral: peripheral, service: service)
            updateState(.ready(info))
            completeWaitingForReady(with: .success(()))
        }
    }

    // MARK: - Write

    /// 写指令至主通道 write 特征；有写队列时走串行 ACK，否则直接 writeValue。
    /// - Returns: 串行队列模式下匹配到的 ACK；`.direct` 或无 Notify 应答时为 nil。
    @discardableResult
    public func write(
        _ data: Data,
        type: CBCharacteristicWriteType = .withoutResponse,
        timeout: TimeInterval? = nil
    ) async throws -> BleWriteAck? {
        guard isReady else { throw BleError.notConnected }
        guard let writeChar else { throw BleError.writeCharacteristicNotFound }
        try validatePayloadSize(data, type: type)
        return try await performWrite(data, to: writeChar, type: type, timeout: timeout)
    }

    /// 写指令至指定 write 特征 UUID。目标即已绑定的主 `writeChar` 时走 ACK 队列；否则直接 `writeValue`。
    /// 附加写忽略 `timeout`（不等待协议 ACK）。
    @discardableResult
    public func write(
        _ data: Data,
        to writeUUID: CBUUID,
        type: CBCharacteristicWriteType = .withoutResponse,
        timeout: TimeInterval? = nil
    ) async throws -> BleWriteAck? {
        guard isReady else { throw BleError.notConnected }
        guard let target = writeCharacteristic(matching: writeUUID) else {
            throw BleError.writeCharacteristicNotFound
        }
        try validatePayloadSize(data, type: type)
        if let writeChar, BleUUID.matches(target.uuid, writeChar.uuid) {
            return try await performWrite(data, to: target, type: type, timeout: timeout)
        }
        try await sendValue(data, to: target, type: type)
        return nil
    }

    /// CoreBluetooth 当前链路允许的单次写入上限；数值会随 write 类型与协商 MTU 变化。
    public func maximumWriteValueLength(for type: CBCharacteristicWriteType = .withoutResponse) -> Int {
        peripheral.maximumWriteValueLength(for: type)
    }

    /// 显式分片写大数据，不进入命令 ACK 队列。
    ///
    /// 普通 `write` 不会自动拆包，因为协议指令帧通常要求原子发送；OTA/批量数据调用方明确选择
    /// 此 API 后，才按当前 MTU 分片，并在 `.withoutResponse` 容量耗尽时等待系统 ready 回调。
    public func writeChunked(
        _ data: Data,
        to writeUUID: CBUUID? = nil,
        type: CBCharacteristicWriteType = .withoutResponse
    ) async throws {
        guard isReady else { throw BleError.notConnected }
        let characteristic: CBCharacteristic
        if let writeUUID {
            guard let target = writeCharacteristic(matching: writeUUID) else {
                throw BleError.writeCharacteristicNotFound
            }
            characteristic = target
        } else {
            guard let writeChar else { throw BleError.writeCharacteristicNotFound }
            characteristic = writeChar
        }

        let maximumLength = maximumWriteValueLength(for: type)
        guard maximumLength > 0 else {
            throw BleError.writeDataTooLong(actual: data.count, maximum: maximumLength)
        }
        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            let end = min(offset + maximumLength, data.count)
            try await sendValue(data.subdata(in: offset..<end), to: characteristic, type: type)
            offset = end
        }
    }

    private func performWrite(
        _ data: Data,
        to characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType,
        timeout: TimeInterval?
    ) async throws -> BleWriteAck? {
        guard let writeQueue else {
            try await sendValue(data, to: characteristic, type: type)
            return nil
        }
        let command = BleWriteCommand(
            peripheral: peripheral,
            writeChar: characteristic,
            data: data,
            writeType: type,
            timeout: timeout ?? defaultWriteTimeout()
        )
        return try await writeQueue.enqueue(command)
    }

    private func validatePayloadSize(_ data: Data, type: CBCharacteristicWriteType) throws {
        let maximumLength = maximumWriteValueLength(for: type)
        guard data.count <= maximumLength else {
            throw BleError.writeDataTooLong(actual: data.count, maximum: maximumLength)
        }
    }

    private func sendValue(
        _ data: Data,
        to characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType
    ) async throws {
        guard isReady else { throw BleError.notConnected }
        if type == .withoutResponse {
            try await waitForWriteCapacity()
            guard isReady else { throw BleError.notConnected }
        }
        logger.log("写入数据: \(data.count) bytes → \(characteristic.uuid)")
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    /// CoreBluetooth 在 withoutResponse 缓冲区满时不会排队保证；必须等待 delegate ready 回调。
    private func waitForWriteCapacity() async throws {
        if peripheral.canSendWriteWithoutResponse { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writeCapacityLock.lock()
                if Task.isCancelled {
                    writeCapacityLock.unlock()
                    continuation.resume(throwing: BleError.cancelled)
                    return
                }
                if peripheral.canSendWriteWithoutResponse {
                    writeCapacityLock.unlock()
                    continuation.resume()
                    return
                }
                writeCapacityContinuations[id] = continuation
                writeCapacityLock.unlock()
            }
        } onCancel: {
            cancelWriteCapacityWaiter(id: id)
        }
    }

    private func cancelWriteCapacityWaiter(id: UUID) {
        writeCapacityLock.lock()
        let continuation = writeCapacityContinuations.removeValue(forKey: id)
        writeCapacityLock.unlock()
        continuation?.resume(throwing: BleError.cancelled)
    }

    private func resumeWriteCapacityWaiters() {
        writeCapacityLock.lock()
        let continuations = Array(writeCapacityContinuations.values)
        writeCapacityContinuations.removeAll()
        writeCapacityLock.unlock()
        continuations.forEach { $0.resume() }
    }

    private func cancelWriteCapacityWaiters() {
        writeCapacityLock.lock()
        let continuations = Array(writeCapacityContinuations.values)
        writeCapacityContinuations.removeAll()
        writeCapacityLock.unlock()
        continuations.forEach { $0.resume(throwing: BleError.cancelled) }
    }

    /// 不另缓存：discover 完成后特征已挂在 `CBPeripheral.services` 上。
    private func writeCharacteristic(matching writeUUID: CBUUID) -> CBCharacteristic? {
        guard let services = peripheral.services else { return nil }
        for service in services {
            guard let characteristics = service.characteristics else { continue }
            if let found = characteristics.first(where: {
                BleUUID.matches($0.uuid, writeUUID)
                    && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse))
            }) {
                return found
            }
        }
        return nil
    }

    private func defaultWriteTimeout() -> TimeInterval {
        switch configuration.writeQueue {
        case .serialized(_, let timeout, _):
            return timeout
        case .direct:
            return 3
        }
    }

    /// 附加 Profile 的 Notify 不进入主串行 ACK 队列。
    private func shouldFeedWriteQueue(characteristic: CBCharacteristic) -> Bool {
        guard writeQueue != nil else { return false }
        for profile in configuration.supplementaryGattProfiles {
            if let notify = profile.notifyCharUUID,
               BleUUID.matches(characteristic.uuid, notify) {
                return false
            }
        }
        if let primaryNotify = configuration.gattProfile.notifyCharUUID {
            return BleUUID.matches(characteristic.uuid, primaryNotify)
        }
        return true
    }
}

// MARK: - CBPeripheralDelegate

extension BlePeripheralConnection: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let result = gattSetup.handleDiscoveredServices(peripheral, error: error) {
            finishGattSetup(result)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let result = gattSetup.handleDiscoveredCharacteristics(peripheral: peripheral, service: service, error: error) {
            finishGattSetup(result)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let result = gattSetup.handleUpdatedNotificationState(
            peripheral: peripheral,
            for: characteristic,
            error: error
        ) {
            finishGattSetup(result)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.log("特征更新失败: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        let update = BleCharacteristicUpdate(peripheral: peripheral, characteristic: characteristic, data: data)
        // Notify 双消费：业务层 characteristicUpdates + 写队列 ACK（serialized 模式）
        Task { await updateBus.yield(update) }
        if shouldFeedWriteQueue(characteristic: characteristic) {
            writeQueue?.handleCharacteristicUpdate(data)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writeQueue?.handleWriteConfirmation(for: characteristic, error: error)
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        resumeWriteCapacityWaiters()
    }
}
