//
//  OfflineWriteQueueService.swift
//  InvoiceAmericano
//
//  Created by Codex on 3/11/26.
//

import Foundation

struct PendingClientCreate: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let localClientID: UUID
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
}

struct PendingInvoiceItem: Codable {
    let title: String
    let description: String
    let quantity: Int
    let unitPrice: Double
}

struct PendingInvoiceCreate: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let localInvoiceID: UUID
    let number: String
    let clientID: UUID
    let clientName: String?
    let clientColorHex: String?
    let dueDate: Date
    let currency: String
    let taxPercent: Double
    let notes: String
    let paymentMethod: InvoicePaymentMethod
    let paymentDetails: String
    let paymentAddress: String
    let items: [PendingInvoiceItem]
}

actor OfflineWriteQueueService {
    static let shared = OfflineWriteQueueService()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func clientKey(uid: String) -> String {
        "offline_queue.\(uid).clients"
    }

    private func invoiceKey(uid: String) -> String {
        "offline_queue.\(uid).invoices"
    }

    private func loadClients(uid: String) -> [PendingClientCreate] {
        guard let data = defaults.data(forKey: clientKey(uid: uid)),
              let rows = try? decoder.decode([PendingClientCreate].self, from: data) else {
            return []
        }
        return rows
    }

    private func saveClients(_ rows: [PendingClientCreate], uid: String) {
        guard let data = try? encoder.encode(rows.sorted(by: { $0.createdAt < $1.createdAt })) else { return }
        defaults.set(data, forKey: clientKey(uid: uid))
    }

    private func loadInvoices(uid: String) -> [PendingInvoiceCreate] {
        guard let data = defaults.data(forKey: invoiceKey(uid: uid)),
              let rows = try? decoder.decode([PendingInvoiceCreate].self, from: data) else {
            return []
        }
        return rows
    }

    private func saveInvoices(_ rows: [PendingInvoiceCreate], uid: String) {
        guard let data = try? encoder.encode(rows.sorted(by: { $0.createdAt < $1.createdAt })) else { return }
        defaults.set(data, forKey: invoiceKey(uid: uid))
    }

    private func loadCachedClients(uid: String) async -> [ClientRow]? {
        await MainActor.run { OfflineCacheService.loadClients(uid: uid) }
    }

    private func saveCachedClients(_ rows: [ClientRow], uid: String) async {
        await MainActor.run { OfflineCacheService.saveClients(rows, uid: uid) }
    }

    private func loadCachedInvoices(uid: String) async -> [InvoiceRow]? {
        await MainActor.run { OfflineCacheService.loadInvoices(uid: uid) }
    }

    private func saveCachedInvoices(_ rows: [InvoiceRow], uid: String) async {
        await MainActor.run { OfflineCacheService.saveInvoices(rows, uid: uid) }
    }

    private func loadCachedRecentInvoices(uid: String) async -> [InvoiceRow]? {
        await MainActor.run { OfflineCacheService.loadRecentInvoices(uid: uid) }
    }

    private func saveCachedRecentInvoices(_ rows: [InvoiceRow], uid: String) async {
        await MainActor.run { OfflineCacheService.saveRecentInvoices(rows, uid: uid) }
    }

    private func saveCachedInvoiceDetail(_ detail: InvoiceDetail, uid: String) async {
        await MainActor.run { OfflineCacheService.saveInvoiceDetail(detail, uid: uid) }
    }

    static func shouldQueueForOffline(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut:
                return true
            default:
                break
            }
        }

        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return true
        }

        let text = ns.localizedDescription.lowercased()
        if text.contains("offline") || text.contains("network") || text.contains("internet") {
            return true
        }

        return false
    }

    func enqueueClientCreate(
        uid: String,
        name: String,
        email: String?,
        phone: String?,
        address: String?,
        city: String?,
        state: String?,
        zip: String?
    ) async {
        let op = PendingClientCreate(
            id: UUID(),
            createdAt: Date(),
            localClientID: UUID(),
            name: name,
            email: email,
            phone: phone,
            address: address,
            city: city,
            state: state,
            zip: zip
        )

        var queued = loadClients(uid: uid)
        queued.append(op)
        saveClients(queued, uid: uid)

        // Show the pending client in local cache immediately.
        var cached = await loadCachedClients(uid: uid) ?? []
        cached.insert(
            ClientRow(
                id: op.localClientID,
                name: op.name,
                email: op.email,
                phone: op.phone,
                address: op.address,
                city: op.city,
                state: op.state,
                zip: op.zip,
                created_at: Date(),
                color_hex: nil
            ),
            at: 0
        )
        await saveCachedClients(cached, uid: uid)
    }

    func enqueueInvoiceCreate(uid: String, draft: InvoiceDraft) async throws -> UUID {
        guard let client = draft.client else {
            throw NSError(domain: "OfflineQueue", code: 2, userInfo: [NSLocalizedDescriptionKey: "Select a client before saving the invoice."])
        }

        let localInvoiceID = UUID()
        let op = PendingInvoiceCreate(
            id: UUID(),
            createdAt: Date(),
            localInvoiceID: localInvoiceID,
            number: draft.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Draft-\(Int(Date().timeIntervalSince1970))" : draft.number,
            clientID: client.id,
            clientName: client.name,
            clientColorHex: client.color_hex,
            dueDate: draft.dueDate,
            currency: draft.currency,
            taxPercent: draft.taxPercent,
            notes: draft.notes,
            paymentMethod: draft.paymentMethod,
            paymentDetails: draft.paymentDetails,
            paymentAddress: draft.paymentAddress,
            items: draft.items.map { item in
                PendingInvoiceItem(
                    title: item.title,
                    description: item.description,
                    quantity: item.quantity,
                    unitPrice: item.unitPrice
                )
            }
        )

        var queued = loadInvoices(uid: uid)
        queued.append(op)
        saveInvoices(queued, uid: uid)

        await addLocalPendingInvoice(op: op, uid: uid)
        return localInvoiceID
    }

    private func addLocalPendingInvoice(op: PendingInvoiceCreate, uid: String) async {
        let subtotal = op.items.reduce(0.0) { $0 + (Double(max(1, $1.quantity)) * $1.unitPrice) }
        let tax = max(0, op.taxPercent) > 0 ? (subtotal * op.taxPercent / 100.0) : 0.0
        let total = subtotal + tax

        let row = InvoiceRow(
            id: op.localInvoiceID,
            number: op.number,
            status: "open",
            clientId: op.clientID,
            total: total,
            created_at: ISO8601DateFormatter().string(from: Date()),
            dueDate: {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.timeZone = .current
                return f.string(from: op.dueDate)
            }(),
            client: ClientRef(name: op.clientName, colorHex: op.clientColorHex),
            sent_at: nil,
            checkout_url: nil,
            pdf_saved_at: nil
        )

        var invoices = await loadCachedInvoices(uid: uid) ?? []
        invoices.insert(row, at: 0)
        await saveCachedInvoices(invoices, uid: uid)

        var recent = await loadCachedRecentInvoices(uid: uid) ?? []
        recent.insert(row, at: 0)
        await saveCachedRecentInvoices(Array(recent.prefix(10)), uid: uid)

        let detail = InvoiceDetail(
            id: op.localInvoiceID,
            number: op.number,
            status: "open",
            subtotal: subtotal,
            tax: tax,
            total: total,
            currency: op.currency,
            created_at: row.created_at,
            issued_at: row.created_at,
            dueDate: row.dueDate,
            checkout_url: nil,
            notes: op.notes.isEmpty ? nil : op.notes,
            client: ClientRef(name: op.clientName, colorHex: op.clientColorHex),
            line_items: op.items.map { item in
                LineItemRow(
                    id: UUID(),
                    title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : item.title,
                    description: item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Item" : item.description,
                    qty: max(1, item.quantity),
                    unit_price: item.unitPrice,
                    amount: Double(max(1, item.quantity)) * item.unitPrice
                )
            }
        )
        await saveCachedInvoiceDetail(detail, uid: uid)
    }

    func pendingInvoiceRows(uid: String) -> [InvoiceRow] {
        loadInvoices(uid: uid).map { op in
            let subtotal = op.items.reduce(0.0) { $0 + (Double(max(1, $1.quantity)) * $1.unitPrice) }
            let tax = max(0, op.taxPercent) > 0 ? (subtotal * op.taxPercent / 100.0) : 0.0
            let total = subtotal + tax
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = .current
            return InvoiceRow(
                id: op.localInvoiceID,
                number: op.number,
                status: "open",
                clientId: op.clientID,
                total: total,
                created_at: ISO8601DateFormatter().string(from: op.createdAt),
                dueDate: f.string(from: op.dueDate),
                client: ClientRef(name: op.clientName, colorHex: op.clientColorHex),
                sent_at: nil,
                checkout_url: nil,
                pdf_saved_at: nil
            )
        }
    }

    func flushPendingWrites() async {
        let connected = await MainActor.run { NetworkMonitorService.isConnectedNow() }
        guard connected else { return }

        let uid: String
        do {
            uid = try await MainActor.run {
                try SupabaseManager.shared.requireCurrentUserIDString()
            }
        } catch {
            return
        }

        let queuedClients = loadClients(uid: uid)
        let queuedInvoices = loadInvoices(uid: uid)
        if queuedClients.isEmpty && queuedInvoices.isEmpty { return }

        var clientIDMap: [UUID: UUID] = [:]
        var remainingClients: [PendingClientCreate] = []

        for op in queuedClients {
            do {
                let created = try await ClientService.createClientOnline(
                    name: op.name,
                    email: op.email,
                    phone: op.phone,
                    address: op.address,
                    city: op.city,
                    state: op.state,
                    zip: op.zip,
                    uid: uid
                )
                clientIDMap[op.localClientID] = created.id
                await replaceLocalClientID(local: op.localClientID, remote: created.id, uid: uid)
            } catch {
                remainingClients.append(op)
            }
        }
        saveClients(remainingClients, uid: uid)

        var remainingInvoices: [PendingInvoiceCreate] = []
        for op in queuedInvoices {
            let resolvedClientID = clientIDMap[op.clientID] ?? op.clientID
            if clientIDMap[op.clientID] == nil && queuedClients.contains(where: { $0.localClientID == op.clientID }) {
                remainingInvoices.append(op)
                continue
            }

            do {
                _ = try await InvoiceService.createInvoiceOnline(
                    from: op,
                    uid: uid,
                    resolvedClientID: resolvedClientID
                )
                await removePendingLocalInvoice(id: op.localInvoiceID, uid: uid)
            } catch {
                remainingInvoices.append(op)
            }
        }
        saveInvoices(remainingInvoices, uid: uid)

        if remainingClients.count != queuedClients.count || remainingInvoices.count != queuedInvoices.count {
            await MainActor.run {
                NotificationCenter.default.post(name: .offlineQueueDidSync, object: nil)
            }
        }
    }

    private func replaceLocalClientID(local: UUID, remote: UUID, uid: String) async {
        if var cachedClients = await loadCachedClients(uid: uid),
           let idx = cachedClients.firstIndex(where: { $0.id == local }) {
            let current = cachedClients[idx]
            cachedClients[idx] = ClientRow(
                id: remote,
                name: current.name,
                email: current.email,
                phone: current.phone,
                address: current.address,
                city: current.city,
                state: current.state,
                zip: current.zip,
                created_at: current.created_at,
                color_hex: current.color_hex
            )
            await saveCachedClients(cachedClients, uid: uid)
        }

        if var cachedInvoices = await loadCachedInvoices(uid: uid) {
            cachedInvoices = cachedInvoices.map { row in
                guard row.clientId == local else { return row }
                return InvoiceRow(
                    id: row.id,
                    number: row.number,
                    status: row.status,
                    clientId: remote,
                    total: row.total,
                    created_at: row.created_at,
                    dueDate: row.dueDate,
                    client: row.client,
                    sent_at: row.sent_at,
                    checkout_url: row.checkout_url,
                    pdf_saved_at: row.pdf_saved_at
                )
            }
            await saveCachedInvoices(cachedInvoices, uid: uid)
        }
    }

    private func removePendingLocalInvoice(id: UUID, uid: String) async {
        if var cachedInvoices = await loadCachedInvoices(uid: uid) {
            cachedInvoices.removeAll { $0.id == id }
            await saveCachedInvoices(cachedInvoices, uid: uid)
        }
        if var recent = await loadCachedRecentInvoices(uid: uid) {
            recent.removeAll { $0.id == id }
            await saveCachedRecentInvoices(recent, uid: uid)
        }
    }
}

extension Notification.Name {
    static let offlineQueueDidSync = Notification.Name("offlineQueueDidSync")
}
