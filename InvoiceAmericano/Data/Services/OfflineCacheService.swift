//
//  OfflineCacheService.swift
//  InvoiceAmericano
//
//  Created by Codex on 3/11/26.
//

import Foundation

enum OfflineCacheService {
    private static let defaults = UserDefaults.standard
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func key(_ base: String, uid: String) -> String {
        "offline_cache.\(uid).\(base)"
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func saveInvoices(_ rows: [InvoiceRow], uid: String) {
        save(rows, key: key("invoices.all", uid: uid))
    }

    static func loadInvoices(uid: String) -> [InvoiceRow]? {
        load([InvoiceRow].self, key: key("invoices.all", uid: uid))
    }

    static func saveRecentInvoices(_ rows: [InvoiceRow], uid: String) {
        save(rows, key: key("invoices.recent", uid: uid))
    }

    static func loadRecentInvoices(uid: String) -> [InvoiceRow]? {
        load([InvoiceRow].self, key: key("invoices.recent", uid: uid))
    }

    static func saveInvoiceDetail(_ detail: InvoiceDetail, uid: String) {
        save(detail, key: key("invoice.detail.\(detail.id.uuidString)", uid: uid))
    }

    static func loadInvoiceDetail(id: UUID, uid: String) -> InvoiceDetail? {
        load(InvoiceDetail.self, key: key("invoice.detail.\(id.uuidString)", uid: uid))
    }

    static func saveClients(_ rows: [ClientRow], uid: String) {
        save(rows, key: key("clients.all", uid: uid))
    }

    static func loadClients(uid: String) -> [ClientRow]? {
        load([ClientRow].self, key: key("clients.all", uid: uid))
    }
}
