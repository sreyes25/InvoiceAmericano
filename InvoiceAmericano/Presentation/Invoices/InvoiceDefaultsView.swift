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
        ScrollView {
            VStack(spacing: 16) {

                // ===== Payment Card =====
                CardBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.blue.opacity(0.14))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                            Text("Payment")
                                .font(.subheadline).bold()
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        FieldRow(label: "Terms") {
                            TextField("e.g. Net 30", text: $terms)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                        }

                        FieldRow(label: "Due Days") {
                            TextField("30", text: $dueDays)
                                .keyboardType(.numberPad)
                                .submitLabel(.done)
                        }

                        FieldRow(label: "Tax Rate (%)") {
                            TextField("0", text: $taxRate)
                                .keyboardType(.decimalPad)
                                .submitLabel(.done)
                        }
                    }
                }

                // ===== Footer Card =====
                CardBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.orange.opacity(0.16))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "text.bubble.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                            Text("Invoice Footer")
                                .font(.subheadline).bold()
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Footer Notes")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            TextField("Thanks for your business!", text: $footerNotes, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color(.systemGroupedBackground))
        .scrollIndicators(.hidden)
        .navigationTitle("Invoice Defaults")
        .toolbar {
            // Keep a small action to dismiss if needed
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        // Bottom sticky Save button
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Save Defaults", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(LargeGradientButtonStyle(gradient: [.blue, .indigo]))
                .disabled(isSaving)

                // Small helper text
                Text("These defaults apply to new invoices. You can always edit per-invoice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
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
            await MainActor.run { errorText = "Failed to load defaults: \(error.friendlyMessage)" }
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
            await MainActor.run { errorText = "Save failed: \(error.friendlyMessage)" }
        }
    }
}

private struct CardBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }
}

private struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            content
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct LargeGradientButtonStyle: ButtonStyle {
    let gradient: [Color]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
        guard let uid = SupabaseManager.shared.currentUserIDString() else { return nil }

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
        let uid = try SupabaseManager.shared.requireCurrentUserIDString()

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
