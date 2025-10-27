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

    // Local gradients for icons (keeps look consistent with Home)
    private let blueGrad: [Color] = [Color.blue.opacity(0.6), Color.indigo.opacity(0.6)]
    private let greenGrad: [Color] = [Color.green.opacity(0.6), Color.teal.opacity(0.6)]
    private let orangeGrad: [Color] = [Color.orange.opacity(0.7), Color.red.opacity(0.6)]

    // Stats
    @State private var totalInvoices: Int = 0
    @State private var paidInvoices: Int = 0
    @State private var outstanding: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Header (avatar + name + email)
                header

                // Quick stats (match Home style: 2 compact + 1 large)
                summaryCards

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
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .scrollIndicators(.hidden)
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

    private var summaryCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SummaryStatCard(title: "Invoices",
                                 value: "\(totalInvoices)",
                                 systemImage: "doc.on.doc",
                                 gradient: blueGrad)
                SummaryStatCard(title: "Paid",
                                 value: "\(paidInvoices)",
                                 systemImage: "checkmark.seal.fill",
                                 gradient: greenGrad)
            }
            SummaryStatCardLarge(title: "Outstanding Balance",
                                 value: currency(outstanding),
                                 systemImage: "clock.badge",
                                 gradient: orangeGrad)
        }
    }

    private struct SummaryStatCard: View {
        let title: String
        let value: String
        let systemImage: String
        let gradient: [Color]

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: gradient.map{ $0.opacity(0.18) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
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

    private struct SummaryStatCardLarge: View {
        let title: String
        let value: String
        let systemImage: String
        let gradient: [Color]

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(colors: gradient.map{ $0.opacity(0.18) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.05))
            )
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }

    private var actionCards: some View {
        VStack(spacing: 12) {
            NavigationLink {
                BrandingView()
            } label: {
                ActionCard(icon: "paintbrush",
                           title: "Branding",
                           subtitle: "Logo & business details",
                           gradient: blueGrad)
            }
            .buttonStyle(.plain)

            NavigationLink {
                InvoiceDefaultsView()
            } label: {
                ActionCard(icon: "doc.plaintext",
                           title: "Invoice defaults",
                           subtitle: "Terms, notes, tax",
                           gradient: greenGrad)
            }
            .buttonStyle(.plain)
        }
    }

    private var settingsList: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Notifications", systemImage: "bell")
                Spacer()
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .onChange(of: notificationsEnabled) {
                        Task { await ProfileService.updateNotifications(enabled: notificationsEnabled) }
                    }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.05)))

            NavigationLink {
                // Placeholder for Help screen
                Text("Support coming soon")
                    .navigationTitle("Help & Support")
            } label: {
                HStack {
                    Label("Help & Support", systemImage: "questionmark.circle")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
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

    private struct ActionCard: View {
        let icon: String
        let title: String
        let subtitle: String
        let gradient: [Color]

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: gradient.map{ $0.opacity(0.18) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).bold()
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
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
}
