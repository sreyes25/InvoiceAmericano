//
//  ActivityService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import Foundation
import Supabase
import PostgREST

// Payload used for inserts (must be Encodable)
private struct ActivityInsert: Encodable {
    let invoice_id: UUID
    let event: String
    let metadata: [String: String]?
}

enum ActivityService {
    static func fetch(invoiceId: UUID, limit: Int = 200) async throws -> [ActivityEvent] {
        // NOTE: Using SB.shared.client (singleton) and proper API labels
        let response = try await SB.shared.client
            .from("invoice_activity")
            .select()
            .eq("invoice_id", value: invoiceId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        let events = try JSONDecoder().decode([ActivityEvent].self, from: response.data)
        return events
    }

    static func fetchAll(limit: Int = 200) async throws -> [ActivityEvent] {
        let response = try await SB.shared.client
            .from("invoice_activity")
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        let events = try JSONDecoder().decode([ActivityEvent].self, from: response.data)
        return events
    }

    static func log(invoiceId: UUID, event: String, metadata: [String: String]? = nil) async throws {
        let payload = ActivityInsert(invoice_id: invoiceId, event: event, metadata: metadata)

        _ = try await SB.shared.client
            .from("invoice_activity")
            .insert(payload)
            .execute()
    }

    // Count unread (where read_at is null)
    static func countUnread() async throws -> Int {
        let resp = try await SB.shared.client
            .from("invoice_activity")
            .select("id", head: false, count: .exact)
            .filter("read_at", operator: "is", value: "null")
            .execute()
        return resp.count ?? 0
    }

    // Mark all as read by setting read_at to current timestamp
    static func markAllAsRead() async throws {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        _ = try await SB.shared.client
            .from("invoice_activity")
            .update(["read_at": nowISO])
            .filter("read_at", operator: "is", value: "null")
            .execute()
    }
}
