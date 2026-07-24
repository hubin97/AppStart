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
    /// GATT 就绪后缓存的写特征，供 `write(_:)` 使用
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

    /// 订阅连接状态机；新订阅者会立即收到当前状态（replayLatest）。
    /// 用法：`for await state in await connection.states() { ... }`
    public func states() async -> AsyncStream<BlePeripheralState> {
        await stateBus.stream()
    }

    /// 订阅 Notify 回包；`uuid == nil` 收全部特征，传入 UUID 则只收该特征。
    /// 用法：`for await update in await connection.characteristicUpdates() { ... }`
    public func characteristicUpdates(matching uuid: CBUUID? = nil) async -> AsyncStream<BleCharacteristicUpdate> {
        let stream = await updateBus.stream()
        guard let uuid else { return stream }
        // 多 Notify 特征时按 UUID 过滤（例如只关心 configuration.notifyCharUUID）
        return AsyncStream { continuation in
            Task {
                for await update in stream {
                    if update.characteristic.uuid == uuid {
                        continuation.yield(update)
                    }
                }
                continuation.finish()
            }
        }
    }

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
                if case .stopped(.exhausted) = phase {
                    self?.updateState(.timedOut)
                }
            }
            reconnectHandler = handler
        }
    }

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

    /// 写指令：有写队列时走串行 ACK 流程，否则直接 writeValue。
    public func write(
        _ data: Data,
        type: CBCharacteristicWriteType = .withoutResponse,
        timeout: TimeInterval? = nil
    ) async throws {
        guard let writeChar else { throw BleError.writeCharacteristicNotFound }
        if let writeQueue {
            let command = BleWriteCommand(
                peripheral: peripheral,
                writeChar: writeChar,
                data: data,
                writeType: type,
                timeout: timeout ?? defaultWriteTimeout()
            )
            try await writeQueue.enqueue(command)
            return
        }
        peripheral.writeValue(data, for: writeChar, type: type)
    }

    private func defaultWriteTimeout() -> TimeInterval {
        switch configuration.writeQueue {
        case .serialized(_, let timeout, _):
            return timeout
        case .direct:
            return 3
        }
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
        writeQueue?.handleCharacteristicUpdate(data)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writeQueue?.handleWriteConfirmation(for: characteristic, error: error)
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
}
