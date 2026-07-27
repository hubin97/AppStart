//
//  NetworkPathMonitor.swift
//  AppStart
//
//  基于 NWPathMonitor 的路径监听。

import Network

final class NetworkPathMonitor {

    private let nwMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.appstart.connectivity.path")
    private var latestPath: NWPath?
    private var isStarted = false

    func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        nwMonitor.pathUpdateHandler = { [weak self] path in
            self?.latestPath = path
        }
        nwMonitor.start(queue: queue)
    }

    func currentSnapshot(validation: InternetValidation = .notChecked) -> ConnectivitySnapshot {
        startIfNeeded()
        guard let path = latestPath else {
            return ConnectivitySnapshot(link: .unknown, pathStatus: .unsatisfied, validation: validation)
        }
        return Self.snapshot(from: path, validation: validation)
    }

    func monitor() -> AsyncStream<NWPath> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.appstart.connectivity.path.stream")
            monitor.pathUpdateHandler = { path in
                continuation.yield(path)
            }
            monitor.start(queue: queue)
            continuation.onTermination = { _ in
                monitor.cancel()
            }
        }
    }

    static func snapshot(from path: NWPath, validation: InternetValidation = .notChecked) -> ConnectivitySnapshot {
        ConnectivitySnapshot(
            link: linkKind(from: path),
            pathStatus: pathStatus(from: path),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            validation: validation
        )
    }

    private static func pathStatus(from path: NWPath) -> NetworkPathStatus {
        switch path.status {
        case .satisfied:
            return .satisfied
        case .unsatisfied:
            return .unsatisfied
        case .requiresConnection:
            return .requiresConnection
        @unknown default:
            return .unsatisfied
        }
    }

    private static func linkKind(from path: NWPath) -> NetworkLinkKind {
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.other) { return .other }
        return .unknown
    }
}
