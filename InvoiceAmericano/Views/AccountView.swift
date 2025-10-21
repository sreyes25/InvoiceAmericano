//
//  AccountView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.
//

import SwiftUI
import Foundation
import Supabase   // ← add this

struct AccountView: View {
    // User-facing data
    @State private var displayName: String = "Your Business"
    @State private var email: String = "you@example.com"
    @State private var notificationsEnabled: Bool = true
    @State private var showSignOutConfirm: Bool = false
    @State private var showBrandingSheet = false

    // Stats
    @State private var totalInvoices: Int = 0
    @State private var paidInvoices: Int = 0
    @State private var outstanding: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Header (avatar + name + email)
                header

                // Quick stats
                statsRow

                // Cards / actions
                actionCards

                // Settings list
                settingsList

                // Sign out
                signOutButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Load profile (name/email) from Supabase auth
            await loadProfile()

            // Load invoice stats
            do {
                let s = try await InvoiceService.fetchAccountStats()
                await MainActor.run {
                    totalInvoices = s.totalCount
                    paidInvoices = s.paidCount
                    outstanding  = s.outstandingAmount
                }
            } catch {
                // ok to ignore in v1
            }
            // Load notifications toggle state from settings
            let enabled = await ProfileService.loadNotificationsEnabled()
            await MainActor.run {
                self.notificationsEnabled = enabled
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.15))
                Text(initials(from: displayName))
                    .font(.title3).bold()
                    .foregroundStyle(.blue)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName).font(.title3).bold()
                Text(email).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()

            Button { showBrandingSheet = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showBrandingSheet) {
                NavigationStack { BrandingView() }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(title: "Invoices", value: "\(totalInvoices)")
            statCard(title: "Outstanding", value: currency(outstanding))
            statCard(title: "Paid", value: "\(paidInvoices)")
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.title2).bold()
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var actionCards: some View {
        VStack(spacing: 12) {
            NavigationLink {
                BrandingView()
            } label: {
                actionRowContent(icon: "paintbrush", title: "Branding", subtitle: "Logo & business details")
            }
            NavigationLink {
                InvoiceDefaultsView()
            } label: {
                actionRowContent(icon: "doc.plaintext", title: "Invoice defaults", subtitle: "Terms, notes, tax")
            }
        }
    }
    
    private func actionRowContent(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon).foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).bold()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func actionRow(icon: String, title: String, subtitle: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon).foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).bold()
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var settingsList: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Notifications", systemImage: "bell")
                Spacer()
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )

            HStack {
                Label("Help & Support", systemImage: "questionmark.circle")
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            showSignOutConfirm = true
        } label: {
            HStack {
                Spacer()
                Text("Log Out").bold()
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .padding(.top, 8)
        .confirmationDialog(
            "Are you sure you want to log out?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                Task { try? await AuthService.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        let s = String(chars).uppercased()
        return s.isEmpty ? "U" : s
    }

    private func currency(_ amount: Double, code: String = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    // MARK: - Data

    private func loadProfile() async {
        // Grab the current Supabase user from the shared client
        let client = SupabaseManager.shared.client

        // In Swift 6, `auth.session` is actor-isolated and can throw; use try/await safely
        let session = try? await client.auth.session
        let user = session?.user

        let userEmail = user?.email ?? "you@example.com"

        // Prefer full_name / name from metadata, fall back to email prefix
        var name = ""
        let meta: [String: AnyJSON] = user?.userMetadata ?? [:]

        // Extract strings from AnyJSON safely
        if let fullJSON = meta["full_name"], case let .string(full) = fullJSON,
           !full.trimmingCharacters(in: .whitespaces).isEmpty {
            name = full
        } else if let nJSON = meta["name"], case let .string(n) = nJSON,
                  !n.trimmingCharacters(in: .whitespaces).isEmpty {
            name = n
        }

        if name.isEmpty, let at = userEmail.firstIndex(of: "@") {
            let base = userEmail[..<at]
            name = base.replacingOccurrences(of: ".", with: " ").capitalized
        }

        await MainActor.run {
            self.email = userEmail
            self.displayName = name.isEmpty ? "Your Business" : name
        }
    }
}
