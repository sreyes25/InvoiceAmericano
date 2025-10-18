//
//  ActivityService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import Foundation
import Supabase
import PostgREST

private struct ActivityInsert: Encodable {
    let invoice_id: UUID
    let event: String
    let metadata: [String: String]?
}

enum ActivityService {
    /// All activity (most recent first)
    static func fetchAll(limit: Int = 200) async throws -> [ActivityEvent] {
        try await SB.shared.client
            .from("invoice_activity")
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Activity for a single invoice (most recent first)
    static func fetch(invoiceId: UUID, limit: Int = 200) async throws -> [ActivityEvent] {
        try await SB.shared.client
            .from("invoice_activity")
            .select()
            .eq("invoice_id", value: invoiceId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Log a new event (optional metadata)
    static func log(invoiceId: UUID, event: String, metadata: [String: String]? = nil) async throws {
        let payload = ActivityInsert(invoice_id: invoiceId, event: event, metadata: metadata)
        _ = try await SB.shared.client
            .from("invoice_activity")
            .insert(payload)
            .execute()
    }

    static func countUnread() async throws -> Int {
        let resp = try await SB.shared.client
            .from("invoice_activity")
            .select("id", head: false, count: .exact)
            .is("read_at", value: nil) 
            .execute()
        return resp.count ?? 0
    }

    static func markAllAsRead() async throws {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        _ = try await SB.shared.client
            .from("invoice_activity")
            .update(["read_at": nowISO])
            .is("read_at", value: nil)  
            .execute()
    }

    /// Delete a single activity row
    static func delete(id: UUID) async throws {
        _ = try await SB.shared.client
            .from("invoice_activity")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}
