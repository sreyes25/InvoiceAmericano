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
    let user_id: String
}

enum ActivityService {
    private static func requireUID() throws -> String {
        try SupabaseManager.shared.requireCurrentUserIDString()
    }
    
    static func markAsRead(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        let client = SupabaseManager.shared.client
        guard let uid = SupabaseManager.shared.currentUserIDString() else { return }
        let now = ISO8601DateFormatter().string(from: Date())

        do {
            _ = try await client
                .from("invoice_activity")
                .update(["read_at": now])
                .in("id", values: ids.map { $0.uuidString })
                .eq("user_id", value: uid)
                .select()
                .execute()
            // After a successful update, broadcast so Home badge refreshes
            await MainActor.run {
                NotificationCenter.default.post(name: .activityUnreadChanged, object: nil)
            }
            print("✅ markAsRead updated \(ids.count) rows")
        } catch {
            print("❌ markAsRead failed: \(error)")
        }
    }
    
    // MARK: - Read / Unread helpers
    private struct ReadUpdate: Encodable { let read_at: String }

    /// Marks the given activity IDs as read (sets read_at = now()).
    /// Non-throwing: tries a bulk update first; falls back to per-row update if the client version
    /// doesn't support `.in("id", value: ...)`.
    static func markActivitiesRead(ids: [UUID]) async {
        guard !ids.isEmpty else { return }

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = f.string(from: Date())
        let payload = ReadUpdate(read_at: now)
        let client = SupabaseManager.shared.client
        guard let uid = SupabaseManager.shared.currentUserIDString() else { return }
        let stringIds = ids.map { $0.uuidString }

        // Attempt bulk update first.
        do {
            _ = try await client
                .from("invoice_activity")
                .update(payload)
                .in("id", values: stringIds)
                .eq("user_id", value: uid)
                .execute()
            return
        } catch {
            // Fallback: update one-by-one for widest compatibility.
            for id in stringIds {
                do {
                    _ = try await client
                        .from("invoice_activity")
                        .update(payload)
                        .eq("id", value: id)
                        .eq("user_id", value: uid)
                        .execute()
                } catch {
                    print("⚠️ markActivitiesRead fallback failed for \(id):", error)
                }
            }
        }
    }

    /// Returns the unread count for the current user by joining invoices (filters by invoices.user_id).
    static func unreadCountForCurrentUser() async -> Int {
        guard let uid = SupabaseManager.shared.currentUserID() else { return 0 }
        do {
            let response = try await SupabaseManager.shared.client
                .from("invoice_activity")
                .select("id, invoices!inner(user_id)", head: true, count: .exact)
                .is("read_at", value: nil)
                .eq("user_id", value: uid.uuidString)
                .eq("invoices.user_id", value: uid.uuidString)
                .execute()
            return response.count ?? 0
        } catch {
            print("⚠️ unreadCountForCurrentUser failed:", error)
            return 0
        }
    }
    
    // Recent joined activity rows for the dashboard preview
    static func fetchRecentActivityJoined(limit: Int = 5) async throws -> [ActivityJoined] {
        let client = SupabaseManager.shared.client
        let uid = try requireUID()
        // Make sure your ActivityJoined matches these columns
        let rows: [ActivityJoined] = try await client
          .from("invoice_activity")
          .select("""
            id,
            invoice_id,
            event,
            created_at,
            read_at,
            invoice:invoices!invoice_activity_invoice_id_fkey(
              number,
              client:clients(name)
            )
          """)
          .eq("user_id", value: uid)
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
            let uid = try requireUID()
            let select = """
                id,
                    invoice_id,
                    event,
                    created_at,
                    read_at,
                    invoice:invoices!invoice_activity_invoice_id_fkey(
                      number,
                      client:clients(name)
                    )
            """
            let resp = try await client
                .from("invoice_activity")
                .select(select)
                .eq("user_id", value: uid)
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
         let uid = try requireUID()
         let response = try await SupabaseManager.shared.client
             .from("invoice_activity")
             .select()
             .is("deleted_at", value: nil)
             .eq("user_id", value: uid)
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
        id, invoice_id, event, created_at, read_at,
        invoice:invoices!invoice_activity_invoice_id_fkey(
            number,
            client:clients!invoices_client_id_fkey(name)
        )
        """

        let uid = try requireUID()
        let resp = try await SupabaseManager.shared.client
            .from("invoice_activity")
            .select(select)
            .eq("user_id", value: uid)
            .order("created_at", ascending: false)
            .range(from: offset, to: to)
            .execute()

        return try JSONDecoder().decode([ActivityJoined].self, from: resp.data)
    }
    
    /// All activity (most recent first)
    static func fetchAll(limit: Int = 200) async throws -> [ActivityEvent] {
        let uid = try requireUID()
        let resp = try await SupabaseManager.shared.client
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
            .eq("user_id", value: uid)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        let rows = try JSONDecoder().decode([ActivityEvent].self, from: resp.data)
        return rows
    }

    /// Activity for a single invoice (most recent first)
    static func fetch(invoiceId: UUID, limit: Int = 200) async throws -> [ActivityEvent] {
        let uid = try requireUID()
        return try await SupabaseManager.shared.client
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
            .eq("user_id", value: uid)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Log a new event (optional metadata)
    static func log(invoiceId: UUID, event: String, metadata: [String: String]? = nil) async throws {
        let uid = try requireUID()
        let payload = ActivityInsert(invoice_id: invoiceId, event: event, metadata: metadata, user_id: uid)
        _ = try await SupabaseManager.shared.client
            .from("invoice_activity")
            .insert(payload)
            .eq("user_id", value: uid)
            .execute()
    }

    static func countUnread() async throws -> Int {
        let client = SupabaseManager.shared.client
        guard let uid = SupabaseManager.shared.currentUserID() else { return 0 }
        let resp = try await client
            .from("invoice_activity")
            .select("id, invoices!inner(user_id)", head: true, count: .exact)
            .is("read_at", value: nil)
            .is("deleted_at", value: nil)
            .eq("user_id", value: uid.uuidString)
            .eq("invoices.user_id", value: uid.uuidString)
            .execute()
        return resp.count ?? 0
    }

    static func markAllAsRead() async throws {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let uid = try requireUID()
        _ = try await SupabaseManager.shared.client
            .from("invoice_activity")
            .update(["read_at": nowISO])
            .is("read_at", value: nil)
            .is("deleted_at", value: nil)
            .eq("user_id", value: uid)
            .execute()
    }

    // MARK: - Soft Delete (update deleted_at)
       static func delete(id: UUID) async throws {
           let nowISO = ISO8601DateFormatter().string(from: Date())
           let uid = try requireUID()
           _ = try await SupabaseManager.shared.client
               .from("invoice_activity")
               .update(["deleted_at": nowISO])
               .eq("id", value: id.uuidString)
               .eq("user_id", value: uid)
               .execute()
       }

}
