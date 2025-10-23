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
    
    // Recent joined activity rows for the dashboard preview
    static func fetchRecentActivityJoined(limit: Int = 5) async throws -> [ActivityJoined] {
        let client = SupabaseManager.shared.client
        // Make sure your ActivityJoined matches these columns
        let rows: [ActivityJoined] = try await client
          .from("invoice_activity")
          .select("""
            id,
            invoice_id,
            event,
            created_at,
            invoice:invoices!invoice_activity_invoice_id_fkey(
              number,
              client:clients(name)
            )
          """)
          .order("created_at", ascending: false)
          .limit(limit)
          .execute()
          .value
        return rows
    }
    
    // Debug: dump the raw JSON so we can confirm shape and fix models exactly.
    // Safe to keep during development; remove when done.
    static func debugDumpRecentActivityJSON(limit: Int = 5) async {
        do {
            let client = SupabaseManager.shared.client
            let select = """
                id,
                    invoice_id,
                    event,
                    created_at,
                    invoice:invoices!invoice_activity_invoice_id_fkey(
                      number,
                      client:clients(name)
                    )
            """
            let resp = try await client
                .from("invoice_activity")
                .select(select)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()

            if let json = String(data: resp.data, encoding: .utf8) {
                print("🔎 Activity JSON:\n\(json)")
            } else {
                print("🔎 Activity JSON: <non-utf8 \(resp.data.count) bytes>")
            }
        } catch {
            print("🔎 Activity JSON dump failed: \(error)")
        }
    }
    
    // Paged fetch for Activity tab

    static func fetchPage(offset: Int = 0, limit: Int = 50) async throws -> [ActivityEvent] {
         let to = offset + limit - 1
         let response = try await SB.shared.client
             .from("invoice_activity")
             .select()
             .is("deleted_at", value: nil)
             .order("created_at", ascending: false)
             .range(from: offset, to: to)
             .execute()
         return try JSONDecoder().decode([ActivityEvent].self, from: response.data)
     }
    
    static func fetchPageJoined(offset: Int, limit: Int) async throws -> [ActivityJoined] {
        let to = offset + limit - 1

        // Replace both constraint names below with your actual Supabase FK constraint names.
        let select =
        """
        id, invoice_id, event, created_at,
        invoice:invoices!invoice_activity_invoice_id_fkey(
            number,
            client:clients!invoices_client_id_fkey(name)
        )
        """

        let resp = try await SB.shared.client
            .from("invoice_activity")
            .select(select)
            .order("created_at", ascending: false)
            .range(from: offset, to: to)
            .execute()

        return try JSONDecoder().decode([ActivityJoined].self, from: resp.data)
    }
    
    /// All activity (most recent first)
    static func fetchAll(limit: Int = 200) async throws -> [ActivityEvent] {
        let resp = try await SB.shared.client
            .from("invoice_activity")
            .select("""
                id,
                invoice_id,
                event,
                metadata,
                actor_user,
                created_at,
                inv:invoices!invoice_activity_invoice_id_fkey(number, client:clients(name))
            """)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        let rows = try JSONDecoder().decode([ActivityEvent].self, from: resp.data)
        return rows
    }

    /// Activity for a single invoice (most recent first)
    static func fetch(invoiceId: UUID, limit: Int = 200) async throws -> [ActivityEvent] {
        try await SB.shared.client
            .from("invoice_activity")
            .select("""
                id,
                invoice_id,
                event,
                metadata,
                actor_user,
                created_at,
                inv:invoices!invoice_activity_invoice_id_fkey(number, client:clients(name))
            """)
            .eq("invoice_id", value: invoiceId.uuidString)
            .is("deleted_at", value: nil)
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
            .is("deleted_at", value: nil)
            .execute()
        return resp.count ?? 0
    }

    static func markAllAsRead() async throws {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        _ = try await SB.shared.client
            .from("invoice_activity")
            .update(["read_at": nowISO])
            .is("read_at", value: nil)
            .is("deleted_at", value: nil)
            .execute()
    }

    // MARK: - Soft Delete (update deleted_at)
       static func delete(id: UUID) async throws {
           let nowISO = ISO8601DateFormatter().string(from: Date())
           _ = try await SB.shared.client
               .from("invoice_activity")
               .update(["deleted_at": nowISO])
               .eq("id", value: id.uuidString)
               .execute()
       }

}
