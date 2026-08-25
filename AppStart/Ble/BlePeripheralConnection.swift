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
    private let configuration: BleConfiguration
    private let logger: BleLogger
    private let stateBus = BleAsyncBroadcastStream<BlePeripheralState>(replayLatest: true)
    /// Notify 特征值更新广播（不 replay，仅推送增量）
    private let updateBus = BleAsyncBroadcastStream<BleCharacteristicUpdate>(replayLatest: false)
    private let gattSetup: BleGattSetup
    /// 配置为 `.serialized` 时启用，负责 ACK 匹配与串行写
    private var writeQueue: BleWriteCommandQueue?
    private var reconnectHandler: BleReconnectHandler?
    /// GATT 就绪后缓存的主 write 特征，供 `write(_:)` 使用
    private var writeChar: CBCharacteristic?
    /// `connect` 挂起等待 `.ready` 的 continuation
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var userInitiatedDisconnect = false

    weak var central: BleCentral?

    private(set) public var currentState: BlePeripheralState = .connecting {
        didSet {
            Task { await stateBus.yield(currentState) }
        }
    }

    // MARK: - Init

    init(peripheral: CBPeripheral, configuration: BleConfiguration, logger: BleLogger, central: BleCentral) {
        self.peripheral = peripheral
        self.configuration = configuration
        self.logger = logger
        self.central = central
        self.gattSetup = BleGattSetup(configuration: configuration, logger: logger)
        super.init()

        // 按配置初始化写队列（serialized 模式：ACK 匹配 + 优先级 + 超时）
        if case .serialized(let matcher, let timeout, let order) = configuration.writeQueue {
            let queue = BleWriteCommandQueue(
                ackMatcher: matcher,
                defaultTimeout: timeout,
                order: order,
                logger: logger
            )
            writeQueue = queue
        }

        // 按配置初始化自动重连（意外断开 / 连接失败时触发）
        if configuration.reconnect.enabled {
            let handler = BleReconnectHandler(policy: configuration.reconnect, logger: logger)
            handler.connect = { [weak self] in
                guard let self else { return }
                self.central?.performConnect(self.peripheral)
            }
            handler.isConnected = { [weak self] in
                self?.central?.isPhysicallyConnected(self?.peripheral) == true
            }
            handler.onPhaseChange = { [weak self] phase in
                guard let self else { return }
                if case .stopped(.exhausted) = phase {
                    self.updateState(.timedOut)
                    // 重连耗尽后取消系统层挂起的 connect，避免设备再次上线时被动连上
                    self.central?.performDisconnect(self.peripheral)
                    self.central?.unregisterConnectionIfNeeded(self)
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
            Task {
                for await update in stream {
                    if BleUUID.matches(update.characteristic.uuid, filterUUID) {
                        continuation.yield(update)
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Connection

    /// 重置连接状态，在每次 `connect` 开始前调用。
    func beginWaitingForReady() {
        userInitiatedDisconnect = false
        reconnectHandler?.stop()
        updateState(.connecting)
    }

    /// 挂起直到 GATT 通道就绪（`.ready`）或失败/超时。
    func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if case .ready = currentState {
                continuation.resume()
                return
            }
            connectContinuation = continuation
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
        connectionTimeoutTask?.cancel()
        peripheral.delegate = self
        updateState(.connected)
        gattSetup.beginServiceDiscovery(on: peripheral)
    }

    func handleConnectFailed(_ error: Error?) {
        connectionTimeoutTask?.cancel()
        updateState(.failed(error))
        connectContinuation?.resume(throwing: BleError.connectionFailed(error))
        connectContinuation = nil
        reconnectHandler?.notifyConnectFailed(peripheral: peripheral)
    }

    /// 区分用户主动断开 vs 意外断开，决定是否触发自动重连。
    func handleDisconnected(error: Error?) {
        connectionTimeoutTask?.cancel()
        writeQueue?.cancelAll()

        if userInitiatedDisconnect {
            central?.unregisterConnectionIfNeeded(self)
            updateState(.disconnected(.userInitiated))
            return
        }
        if let error {
            updateState(.disconnected(.unexpected(error)))
            reconnectHandler?.notifyUnexpectedDisconnect()
        } else {
            central?.unregisterConnectionIfNeeded(self)
            updateState(.disconnected(.userInitiated))
        }
    }

    /// 用户主动断开；不触发自动重连，并清空写队列。
    public func disconnect() {
        userInitiatedDisconnect = true
        reconnectHandler?.notifyUserDisconnect()
        writeQueue?.cancelAll()
        central?.performDisconnect(peripheral)
    }

    private func handleConnectionTimeout() {
        updateState(.timedOut)
        connectContinuation?.resume(throwing: BleError.connectionTimeout)
        connectContinuation = nil
        central?.performDisconnect(peripheral)
    }

    private func updateState(_ state: BlePeripheralState) {
        currentState = state
    }

    private func completeConnectIfNeeded() {
        guard connectContinuation != nil else { return }
        connectContinuation?.resume()
        connectContinuation = nil
        reconnectHandler?.notifyConnected()
    }

    /// GATT 发现完成：记录写特征、订阅 Notify、推进状态到 `.ready`。
    private func finishGattSetup(_ result: BleGattSetup.Result) {
        if let error = result.error {
            updateState(.failed(error))
            connectContinuation?.resume(throwing: BleError.channelSetupFailed(error))
            connectContinuation = nil
            return
        }
        writeChar = result.writeChar
        if let service = result.readyService {
            let info = BleChannelReadyInfo(peripheral: peripheral, service: service)
            updateState(.ready(info))
        }
        completeConnectIfNeeded()
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
        guard let writeChar else { throw BleError.writeCharacteristicNotFound }
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
        guard let target = writeCharacteristic(matching: writeUUID) else {
            throw BleError.writeCharacteristicNotFound
        }
        if let writeChar, BleUUID.matches(target.uuid, writeChar.uuid) {
            return try await performWrite(data, to: target, type: type, timeout: timeout)
        }
        peripheral.writeValue(data, for: target, type: type)
        return nil
    }

    private func performWrite(
        _ data: Data,
        to characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType,
        timeout: TimeInterval?
    ) async throws -> BleWriteAck? {
        guard let writeQueue else {
            peripheral.writeValue(data, for: characteristic, type: type)
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
}
