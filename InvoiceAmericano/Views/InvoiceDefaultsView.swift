//
//  InvoiceDefaultsView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.
//

import SwiftUI

struct InvoiceDefaultsView: View {
    @State private var taxRate: String = "0"           // as string for TextField
    @State private var dueDays: String = "30"          // e.g., Net 30
    @State private var terms: String = "Net 30"
    @State private var footerNotes: String = "Thank you for your business!"

    @State private var isSaving = false
    @State private var errorText: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(header: Text("Payment")) {
                TextField("Default terms (e.g., Net 30)", text: $terms)
                TextField("Default due days (e.g., 30)", text: $dueDays)
                    .keyboardType(.numberPad)
                TextField("Default tax rate (%)", text: $taxRate)
                    .keyboardType(.decimalPad)
            }

            Section(header: Text("Invoice Footer")) {
                TextField("Footer notes", text: $footerNotes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
        }
        .navigationTitle("Invoice Defaults")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await save() } } label: {
                    if isSaving { ProgressView() } else { Text("Save").bold() }
                }
                .disabled(isSaving)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            if let d = try await InvoiceDefaultsService.loadDefaults() {
                await MainActor.run {
                    taxRate = String(d.taxRate)
                    dueDays = String(d.dueDays)
                    terms = d.terms ?? ""
                    footerNotes = d.footerNotes ?? ""
                }
            }
        } catch {
            await MainActor.run { errorText = "Failed to load defaults: \(error.localizedDescription)" }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let tax = Double(taxRate) ?? 0
            let due = Int(dueDays) ?? 30
            try await InvoiceDefaultsService.upsertDefaults(
                taxRate: tax,
                dueDays: due,
                terms: terms.isEmpty ? nil : terms,
                footerNotes: footerNotes.isEmpty ? nil : footerNotes
            )
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { errorText = "Save failed: \(error.localizedDescription)" }
        }
    }
}

// InvoiceDefaultsService.swift
// InvoiceAmericano

import Foundation
import Supabase

struct InvoiceDefaults: Codable {
    let taxRate: Double
    let dueDays: Int
    let terms: String?
    let footerNotes: String?
}

enum InvoiceDefaultsService {
    // Reuse the 'settings' table with additional columns
    // Columns to add if missing:
    //   default_tax_rate double precision default 0
    //   default_due_days integer default 30
    //   default_terms text
    //   default_footer_notes text

    static func loadDefaults() async throws -> InvoiceDefaults? {
        let client = SupabaseManager.shared.client
        let session = try? await client.auth.session
        guard let uid = session?.user.id.uuidString else { return nil }

        struct Row: Decodable {
            let default_tax_rate: Double?
            let default_due_days: Int?
            let default_terms: String?
            let default_footer_notes: String?
        }

        let rows: [Row] = try await client
            .from("settings")
            .select("default_tax_rate, default_due_days, default_terms, default_footer_notes")
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value

        guard let r = rows.first else { return nil }
        return InvoiceDefaults(
            taxRate: r.default_tax_rate ?? 0,
            dueDays: r.default_due_days ?? 30,
            terms: r.default_terms,
            footerNotes: r.default_footer_notes
        )
    }

    static func upsertDefaults(
        taxRate: Double,
        dueDays: Int,
        terms: String?,
        footerNotes: String?
    ) async throws {
        let client = SupabaseManager.shared.client
        let session = try? await client.auth.session
        guard let uid = session?.user.id.uuidString else { throw NSError(domain: "auth", code: 401) }

        struct UpsertRow: Encodable {
            let user_id: String
            let default_tax_rate: Double
            let default_due_days: Int
            let default_terms: String?
            let default_footer_notes: String?
        }

        let payload = UpsertRow(
            user_id: uid,
            default_tax_rate: taxRate,
            default_due_days: dueDays,
            default_terms: terms?.nilIfBlank,
            default_footer_notes: footerNotes?.nilIfBlank
        )

        _ = try await client
            .from("settings")
            .upsert(payload, onConflict: "user_id")
            .execute()
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
