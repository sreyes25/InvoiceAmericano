//
//  InvoiceService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/5/25.
//

import Foundation
import Supabase

// MARK: - Payload/DTO helpers

private struct InsertedInvoiceID: Decodable { let id: UUID }

private struct NewInvoicePayload: Encodable {
    let number: String
    let client_id: UUID
    let status: String
    let subtotal: Double
    let tax: Double
    let total: Double
    let currency: String
    let due_date: String?
    let notes: String?
    let user_id: String?
    let issued_at: String?     // <-- added so we can stamp issued date once
}

private struct NewLineItemPayload: Encodable {
    let invoice_id: UUID
    let description: String
    let qty: Int
    let unit_price: Double
    let amount: Double
}

private struct CreateCheckoutRequest: Encodable {
    let invoice_id: String
}

private struct _CheckoutURLRow: Decodable { let checkout_url: String? }
private struct _SentUpdate: Encodable { let status: String; let sent_at: String }

// MARK: - Service

enum InvoiceService {

    // List screen data
    static func fetchInvoices(status: InvoiceStatus) async throws -> [InvoiceRow] {
        let client = SupabaseManager.shared.client

        let query = client
            .from("invoices")
            .select("id, number, status, total, created_at, due_date, client:clients!invoices_client_id_fkey(name)")
            .order("created_at", ascending: false)

        let rows: [InvoiceRow] = try await query.execute().value

        // Client-side filter to support "overdue" virtual tab
        if case .overdue = status {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())

            let iso = ISO8601DateFormatter()
            var ymd: DateFormatter {
                let d = DateFormatter()
                d.dateFormat = "yyyy-MM-dd"
                d.timeZone = TimeZone(secondsFromGMT: 0)   // <-- no fileprivate dependency
                return d
            }

            return rows.filter { row in
                guard let s = row.dueDate else { return false }
                let due = ymd.date(from: s) ?? iso.date(from: s)
                let isUnpaid = (row.status == "open" || row.status == "draft")
                return isUnpaid && (due.map { cal.startOfDay(for: $0) < today } ?? false)
            }
        }

        if let target = status.filterValue {
            return rows.filter { $0.status == target }
        }
        return rows
    }

    // Create an invoice + items, optionally trigger checkout
    static func createInvoice(from draft: InvoiceDraft) async throws -> (id: UUID, checkoutURL: URL?) {
        let client = SupabaseManager.shared.client

        // Formatter for short issue date (month/day/year)
        let shortDateFormatter = DateFormatter()
        shortDateFormatter.dateFormat = "yyyy-MM-dd"   // keep only date
        shortDateFormatter.timeZone = .current
        let shortDate = shortDateFormatter.string(from: Date())

        // ISO formatter for due date
        let iso = ISO8601DateFormatter()

        // Build invoice payload
        let payload = NewInvoicePayload(
            number: draft.number,
            client_id: draft.client!.id,
            status: "open",  // <-- stays open until it's sent
            subtotal: draft.subTotal,
            tax: draft.taxAmount,
            total: draft.total,
            currency: draft.currency.lowercased(),
            due_date: iso.string(from: draft.dueDate),
            notes: draft.notes.isEmpty ? nil : draft.notes,
            user_id: AuthService.currentUserIDFast(),
            issued_at: shortDate  // <-- short date format
        )

        // 1) Insert invoice, return id
        let created: InsertedInvoiceID = try await client
            .from("invoices")
            .insert(payload)
            .select("id")
            .single()
            .execute()
            .value
        let invoiceId = created.id

        // 2) Insert line items
        let itemsPayload = draft.items.map {
            NewLineItemPayload(
                invoice_id: invoiceId,
                description: $0.description,
                qty: max(1, $0.quantity),
                unit_price: $0.unitPrice,
                amount: Double(max(1, $0.quantity)) * $0.unitPrice
            )
        }
        _ = try await client.from("line_items").insert(itemsPayload).execute()

        // 3) Optionally create checkout (we ignore the return body for SDK compatibility)
        let checkoutURL: URL? = nil
        do {
            _ = try await client.functions.invoke(
                "create_checkout",
                options: FunctionInvokeOptions(
                    headers: ["Content-Type": "application/json"],
                    body: CreateCheckoutRequest(invoice_id: invoiceId.uuidString)
                )
            )
        } catch {
            // ignore if function not deployed yet
        }

        return (invoiceId, checkoutURL)
    }

    /// Creates/refreshes checkout session, stamps sent_at, and tries to fetch checkout_url.
    static func sendInvoice(id: UUID) async throws -> URL? {
        let client = SupabaseManager.shared.client

        // 1) Trigger checkout session (ignore response body)
        _ = try? await client.functions.invoke(
            "create_checkout",
            options: FunctionInvokeOptions(
                headers: ["Content-Type": "application/json"],
                body: CreateCheckoutRequest(invoice_id: id.uuidString)
            )
        )

        // 2) Try to read back the checkout_url if your function writes it
        var checkoutURL: URL? = nil
        do {
            let row: _CheckoutURLRow = try await client
                .from("invoices")
                .select("checkout_url")
                .match(["id": id.uuidString])
                .single()
                .execute()
                .value
            if let s = row.checkout_url, let u = URL(string: s) { checkoutURL = u }
        } catch {
            // It's okay if it's not there yet
        }

        

        return checkoutURL
    }

    // Explicitly mark an invoice as sent after a successful user share action.
    static func markSent(id: UUID) async throws {
        let client = SupabaseManager.shared.client
        let iso = ISO8601DateFormatter()
        _ = try await client
            .from("invoices")
            .update(_SentUpdate(status: "sent", sent_at: iso.string(from: Date())))
            .match(["id": id.uuidString])
            .execute()
    }

    // Detail screen data (includes items & issued_at)
    static func fetchInvoiceDetail(id: UUID) async throws -> InvoiceDetail {
        let client = SupabaseManager.shared.client
        let detail: InvoiceDetail = try await client
            .from("invoices")
            .select("""
                id, number, status, subtotal, tax, total, currency, created_at, issued_at, due_date, checkout_url,
                client:clients!invoices_client_id_fkey(name),
                line_items(id, description, qty, unit_price, amount)
            """)
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
        return detail
    }
}
