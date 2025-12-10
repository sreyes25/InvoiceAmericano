//
//  ActivityJoined.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/20/25.
//

import Foundation

/// Includes `read_at` to support unread indicators and batching read receipts.
struct ActivityJoined: Identifiable, Decodable {
    let id: UUID
    let event: String
    let created_at: String
    var read_at: String?         // CHANGED to var so views can optimistically mark as read
    let invoice_id: UUID?        // NEW: FK from invoice_activity

    // Supabase row shape from:
    // invoice:invoices!invoice_activity_invoice_id_fkey(number)
    // client:invoices!invoice_activity_invoice_id_fkey(client:clients(name))
    let invoice: InvoiceMini?
    let client: ClientLayer1?   // can be { name } or { client: { name } }

    // Flexible accessors so the UI doesn’t care about shape
    var invoiceNumber: String {
        invoice?.number ?? "—"
    }

    var clientName: String {
        client?.name
            ?? client?.client?.name
            ?? invoice?.client?.name   // <— add this fallback
            ?? "—"
    }

    var invoiceId: UUID? {      // NEW: convenience for navigation
        invoice_id
    }

    struct InvoiceMini: Decodable {
        let number: String?
        let client: ClientName?
    }

    struct ClientLayer1: Decodable {
        let name: String?
        let client: ClientName?
    }

    struct ClientName: Decodable {
        let name: String?
    }

    // MARK: - Convenience
    /// True if this activity has not been marked as read (read_at is NULL in DB)
    var isUnread: Bool { read_at == nil }
}
