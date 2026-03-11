//
//  NetworkMonitorService.swift
//  InvoiceAmericano
//
//  Created by Codex on 3/11/26.
//

import Foundation
import Network
import Combine

final class NetworkMonitorService: ObservableObject {
    static let shared = NetworkMonitorService()

    @Published private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "invoiceamericano.network.monitor")
    private let lock = NSLock()
    private var connectedValue: Bool = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied

            self.lock.lock()
            let changed = (self.connectedValue != connected)
            self.connectedValue = connected
            self.lock.unlock()

            Task { @MainActor in
                self.isConnected = connected
            }

            if connected && changed {
                Task { await OfflineWriteQueueService.shared.flushPendingWrites() }
            }
        }
        monitor.start(queue: queue)
    }

    static func isConnectedNow() -> Bool {
        shared.currentConnectionValue()
    }

    private func currentConnectionValue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return connectedValue
    }
}
