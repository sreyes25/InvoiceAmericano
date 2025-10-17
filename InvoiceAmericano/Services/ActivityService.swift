//
//  ActivityService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import Foundation
import Supabase
import PostgREST

public struct ActivityRow: Decodable, Identifiable {
    public let id: UUID
    public let invoice_id: UUID
    public let event: String
    public let created_at: String
    public let read_at: String?
    public let deleted_at: String?
}

enum ActivityService {
    
    static func fetch(invoiceId: UUID, limit: Int = 200) async throws -> [ActivityEvent] {
        let resp = try await SB.shared.client
            .from("invoice_activity")
            .select()
            .eq("invoice_id", value: invoiceId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        return try JSONDecoder().decode([ActivityEvent].self, from: resp.data)
    }
    
    // 1) List (exclude soft-deleted)
    static func fetchAll() async throws -> [ActivityRow] {
        let client = SupabaseManager.shared.client
        return try await client
            .from("invoice_activity")
            .select("id, invoice_id, event, created_at, read_at, deleted_at")
            .is("deleted_at", value: nil)               // deleted_at IS NULL
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // 2) Mark all read (only unread & not deleted)
    static func markAllAsRead() async throws {
        let client = SupabaseManager.shared.client
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await client
            .from("invoice_activity")
            .update(["read_at": now])
            .is("read_at", value: nil)                  // read_at IS NULL
            .is("deleted_at", value: nil)               // deleted_at IS NULL
            .execute()
    }

    // 3) Soft delete one row
    static func delete(id: UUID) async throws {
        let client = SupabaseManager.shared.client
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await client
            .from("invoice_activity")
            .update(["deleted_at": now])
            .eq("id", value: id.uuidString)
            .execute()
    }
}
