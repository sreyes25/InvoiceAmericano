//
//  InvoicePDFSnapshot.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 12/7/25.
//

import Foundation
// MARK: - Shared PDF Snapshot for Invoice + Draft

/// A neutral shape that the PDF generator can use for both:
/// 1) Saved invoices coming from Supabase (`InvoiceDetail`)
/// 2) Draft invoices in the UI (`InvoiceDraft`)
struct InvoicePDFSnapshot {
    struct Client {
        let name: String
        let email: String?
        let city: String?
        let state: String?
    }

    struct LineItem {
        let title: String?
        let description: String
        let quantity: Int
        let unitPrice: Double
        let amount: Double
    }

    let number: String
    let status: String
    let currency: String
    let subtotal: Double
    let tax: Double
    let total: Double

    let issuedAt: Date?
    let dueDate: Date?

    let notes: String?
    let client: Client?
    let items: [LineItem]
}

// MARK: - Snapshot builders

extension InvoicePDFSnapshot {

    /// Build a snapshot from a saved invoice returned by the backend.
    init(from detail: InvoiceDetail) {
        self.number   = detail.number
        self.status   = detail.status
        self.currency = (detail.currency ?? "USD").uppercased()

        self.subtotal = detail.subtotal ?? 0
        self.tax      = detail.tax ?? 0
        self.total    = detail.total ?? 0

        self.issuedAt = Self.parseSupabaseDate(detail.issued_at ?? detail.created_at)
        self.dueDate  = Self.parseSupabaseDate(detail.dueDate)

        self.notes = detail.notes

        if let c = detail.client {
            self.client = Client(
                name: c.name ?? "—",
                email: nil,      // not present in InvoiceDetail.ClientRef today
                city: nil,
                state: nil
            )
        } else {
            self.client = nil
        }

        self.items = detail.line_items.map { row in
            LineItem(
                title: row.title,
                description: row.description,
                quantity: row.qty,
                unitPrice: row.unit_price,
                amount: row.amount
            )
        }
    }

    /// Build a snapshot from an in-progress draft in the UI.
    /// This lets us feed *almost* the same data into the PDF generator
    /// before the invoice is saved.
    init(from draft: InvoiceDraft) {
        self.number   = draft.number.isEmpty ? "—" : draft.number
        self.status   = "draft"
        self.currency = draft.currency.uppercased()

        self.subtotal = draft.subTotal
        self.tax      = draft.taxAmount
        self.total    = draft.total

        self.issuedAt = Date()                      // "now" for preview
        self.dueDate  = draft.dueDate

        self.notes = draft.notes.isEmpty ? nil : draft.notes

        if let c = draft.client {
            self.client = Client(
                name: c.name,
                email: c.email,
                city: c.city,
                state: c.state
            )
        } else {
            self.client = nil
        }

        self.items = draft.items.map { li in
            let qty = max(1, li.quantity)
            let unit = max(0, li.unitPrice)
            return LineItem(
                title: li.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : li.title,
                description: li.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (li.title.isEmpty ? "Item" : li.title)
                    : li.description,
                quantity: qty,
                unitPrice: unit,
                amount: Double(qty) * unit
            )
        }
    }

    // MARK: - Date parsing helpers

    private static func parseSupabaseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }

        // Try a few common Supabase / ISO formats
        let fmts: [String] = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)

        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }

        // Fallback to ISO8601DateFormatter
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }
}
