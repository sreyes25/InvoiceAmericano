//
//  InvoiceService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/5/25.
//

import Foundation
import Supabase

// MARK: - Brand name helper (source of truth: profiles.display_name)
enum BrandNameProvider {
    /// Fetches the current user's business/brand display name.
    /// Falls back to a safe default if not found.
    static func currentBrandName() async -> String {
        let client = SupabaseManager.shared.client
        // Get current user id
        guard let uid = client.auth.currentSession?.user.id else {
            return "Your Business"
        }

        // Query profiles.display_name (single source of truth)
        struct Row: Decodable { let display_name: String? }
        do {
            let row: Row = try await client
                .from("profiles")
                .select("display_name")
                .eq("id", value: uid.uuidString)
                .single()
                .execute()
                .value

            let name = (row.display_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Your Business" : name
        } catch {
            // If anything fails, return a safe default so PDF/headers still render
            return "Your Business"
        }
    }
}

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
    
    // Lightweight stats for the Account tab
    struct AccountStats {
        let totalCount: Int
        let paidCount: Int
        let outstandingAmount: Double   // sum of totals for open/sent/overdue
    }
    
    // Recent invoices, newest first (used by Home dashboard)
    static func fetchRecentInvoices(limit: Int = 5) async throws -> [InvoiceRow] {
        let client = SupabaseManager.shared.client
        let rows: [InvoiceRow] = try await client
            .from("invoices")
            .select("""
                id, number, status, total, currency, created_at, due_date, client_id,
                client:clients!invoices_client_id_fkey(name)
            """)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows
    }

    static func fetchAccountStats() async throws -> AccountStats {
        let client = SupabaseManager.shared.client

        // Keep it simple and reliable: fetch status + total and compute in-app.
        // (We can replace with SQL aggregates later if needed.)
        struct Row: Decodable { let status: String; let total: Double? }

        let rows: [Row] = try await client
            .from("invoices")
            .select("status,total")
            .execute()
            .value

        let totalCount = rows.count
        let paidCount = rows.filter { $0.status.lowercased() == "paid" }.count
        let outstandingAmount = rows
            .filter { ["open","sent","overdue"].contains($0.status.lowercased()) }
            .reduce(0.0) { $0 + ($1.total ?? 0.0) }

        return AccountStats(
            totalCount: totalCount,
            paidCount: paidCount,
            outstandingAmount: outstandingAmount
        )
    }

    // Generate next invoice number like A1, A2, ... by scanning recent invoices
    static func nextInvoiceNumber() async throws -> String {
        let client = SupabaseManager.shared.client

        // Pull recent numbers and find the max numeric suffix
        let resp = try await client
            .from("invoices")
            .select("number, created_at")
            .order("created_at", ascending: false)
            .limit(50)
            .execute()

        struct Row: Decodable { let number: String? }
        let rows = try JSONDecoder().decode([Row].self, from: resp.data)

        // Parse formats like "A123" (or just "123"). We keep the alpha prefix if present.
        var maxNum = 0
        for r in rows {
            guard let raw = r.number?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            // Extract trailing digits
            let digits = raw.reversed().prefix { $0.isNumber }.reversed()
            if let n = Int(String(digits)) { maxNum = max(maxNum, n) }
        }
        let next = maxNum + 1
        return "A\(next)"
    }

    // List screen data
    static func fetchInvoices(status: InvoiceStatus) async throws -> [InvoiceRow] {
        let client = SupabaseManager.shared.client

        let query = client
            .from("invoices")
            .select("id, number, status, total, created_at, due_date, client_id, client:clients!invoices_client_id_fkey(name)")
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

        guard let clientId = draft.client?.id else {
            throw NSError(domain: "InvoiceService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing client on draft"])
        }

        // ---- 1) Load user defaults once (terms/taxRate/dueDays/footerNotes) ----
        let defaults = try? await InvoiceDefaultsService.loadDefaults()

        // ---- 2) Ensure invoice number exists; auto-generate if user left it blank ----
        let trimmedNumber = draft.number.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNumber: String
        if trimmedNumber.isEmpty {
            finalNumber = try await nextInvoiceNumber()
        } else {
            finalNumber = trimmedNumber
        }

        // ---- 3) Compute issued_at and due_date (string) ----
        // Always stamp today's issued date once here (UI can also show it)
        let ymd = DateFormatter()
        ymd.dateFormat = "yyyy-MM-dd"
        ymd.timeZone = .current

        let issuedAtDate = Date()
        let issuedAtStr = ymd.string(from: issuedAtDate)

        // The draft currently provides a concrete dueDate; if you later make it optional,
        // you can fallback to defaults?.dueDays here.
        let dueDateStr = ymd.string(from: draft.dueDate)

        // ---- 4) Merge defaults for notes and tax if missing/zero ----
        // Notes: if draft.notes is blank, use default footer notes (if present)
        let trimmedNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNotes: String? = {
            if !trimmedNotes.isEmpty { return trimmedNotes }
            if let def = defaults?.footerNotes, !def.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return def
            }
            return nil
        }()

        // Tax/Total: if draft has 0 tax but defaults has a taxRate, recompute
        let effectiveSubtotal = draft.subTotal
        var effectiveTax = draft.taxAmount
        var effectiveTotal = draft.total

        if effectiveTax == 0, let rate = defaults?.taxRate, rate > 0 {
            effectiveTax = (effectiveSubtotal * rate) / 100.0
            effectiveTotal = effectiveSubtotal + effectiveTax
        }

        // ---- 5) Build invoice payload from draft + merged defaults ----
        let payload = NewInvoicePayload(
            number: finalNumber,
            client_id: clientId,
            status: "open",                                  // stays open until it's sent
            subtotal: effectiveSubtotal,
            tax: effectiveTax,
            total: effectiveTotal,
            currency: draft.currency.lowercased(),
            due_date: dueDateStr,
            notes: effectiveNotes,
            user_id: AuthService.currentUserIDFast(),
            issued_at: issuedAtStr
        )

        // ---- 6) Insert invoice, return id ----
        let created: InsertedInvoiceID = try await client
            .from("invoices")
            .insert(payload)
            .select("id")
            .single()
            .execute()
            .value
        let invoiceId = created.id

        // ---- 7) Insert line items ----
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

        // ---- 8) Optionally create checkout (ignore response body if function not deployed) ----
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
            .limit(1)                  // <- extra safety with single()
            .single()
            .execute()
            .value
        return detail
    }
}


