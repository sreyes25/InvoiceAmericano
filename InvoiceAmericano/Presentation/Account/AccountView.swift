//
//  AccountView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.
//

import SwiftUI
import Foundation
import Supabase
import Auth

/// ✅ Single source of truth for the account display name:
/// We use the **DBA / Business Name** collected during onboarding,
/// stored in your `profiles.display_name`.
/// - Header, Profile screen, and everywhere else show this name.
/// - Apple ID/email are irrelevant for the display name (used only for login & contact).
/// - If `display_name` is empty, we fall back to a cleaned email prefix or "Your Business".
struct AccountView: View {
    // MARK: - User-facing data
    @State private var businessName: String? = nil      // ← DBA from profiles.display_name
    @State private var email: String = "you@example.com"
    @State private var uid: String = ""

    // Settings & stats
    @State private var notificationsEnabled: Bool = true
    @State private var showSignOutConfirm: Bool = false
    @State private var totalInvoices: Int = 0
    @State private var paidInvoices: Int = 0
    @State private var outstanding: Double = 0
    @State private var errorText: String? = nil

    // Stripe Connect
    @State private var stripeStatus: StripeStatus? = nil
    @State private var stripeLoading: Bool = false

    // MARK: - UI Palettes
    private let blueGrad:  [Color] = [Color.blue.opacity(0.6),  Color.indigo.opacity(0.6)]
    private let greenGrad: [Color] = [Color.green.opacity(0.6), Color.teal.opacity(0.6)]
    private let orangeGrad:[Color] = [Color.orange.opacity(0.7), Color.red.opacity(0.6)]

    // MARK: - Derived Properties
    /// The name we actually show everywhere (DBA first, then fallback).
    private var shownDisplayName: String {
        if let bn = businessName?.trimmingCharacters(in: .whitespacesAndNewlines), !bn.isEmpty {
            return bn
        }
        return fallbackName(from: email)
    }

    private var isAppleRelay: Bool {
        email.lowercased().contains("privaterelay.appleid.com")
    }

    private var accountType: String {
        let n = shownDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bizHints = [" llc", " inc", " corp", " co", " ltd", " company", " pllc", " pc", " studios", " group"]
        if n == "your business" { return "Business" }
        if bizHints.contains(where: { n.contains($0) }) { return "Business" }
        return "Personal"
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                summaryCards
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                paymentsCard
                actionCards
                settingsList
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
            await loadAuthBasics()       // email + uid
            await loadBusinessName()     // profiles.display_name (DBA)
            // Optional stats & prefs
            do {
                let s = try await InvoiceService.fetchAccountStats()
                await MainActor.run {
                    totalInvoices = s.totalCount
                    paidInvoices = s.paidCount
                    outstanding  = s.outstandingAmount
                    errorText = nil
                }
            } catch {
                await MainActor.run { errorText = error.friendlyMessage }
            }

            let enabled = await ProfileService.loadNotificationsEnabled()
            await MainActor.run { self.notificationsEnabled = enabled }
            await refreshStripeStatus()
        }
        .onAppear {
            // refresh DBA when coming back from Branding or Profile edits
            Task { await loadBusinessName() }
        }
    }

    // MARK: - Header (Profile card)
    private var header: some View {
        NavigationLink {
            AccountDetailsView(
                uid: uid,
                displayName: shownDisplayName,
                email: email,
                onNameChanged: { newName in
                    // Keep single source consistent live
                    self.businessName = newName
                }
            )
        } label: {
            HStack(alignment: .center, spacing: 16) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.red.opacity(0.30), Color.orange.opacity(0.28)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5))
                    Text(initials(from: shownDisplayName))
                        .font(.title3).bold()
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(shownDisplayName)
                        .font(.title3).bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 8) {
                        Text(accountType)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(0.06), in: Capsule())
                        if isAppleRelay {
                            Label("Apple ID", systemImage: "applelogo")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.black.opacity(0.06), in: Capsule())
                        }
                    }
                }
                Spacer()
                // Decorative gear (doesn't open Branding; the card navigates to Profile)
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(8)
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
        .buttonStyle(.plain)
    }

    // MARK: - Branding Name Loader (Single source: profiles.display_name)
    private func loadBusinessName() async {
        let client = SupabaseManager.shared.client
        do {
            let uid = try SupabaseManager.shared.requireCurrentUserIDString()

            struct ProfileRow: Decodable { let display_name: String? }

            let row: ProfileRow = try await client
                .from("profiles")
                .select("display_name")
                .eq("id", value: uid)
                .single()
                .execute()
                .value

            await MainActor.run {
                self.businessName = row.display_name
            }
        } catch {
            // Ignore if the column doesn't exist yet; fallback name will be used.
            // You may run the provided SQL migration to add profiles.display_name.
        }
    }

    // MARK: - Auth basics (email + uid only)
    private func loadAuthBasics() async {
        let client = SupabaseManager.shared.client
        do {
            let session = try await client.auth.session
            let user = session.user
            let userEmail = user.email ?? "you@example.com"
            await MainActor.run {
                self.uid = user.id.uuidString
                self.email = userEmail
            }
        } catch {
            await MainActor.run {
                self.uid = ""
                self.email = "you@example.com"
            }
        }
    }
    // MARK: - Stripe Payments Card
    private var paymentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Payments with Stripe")
                    .font(.headline)
                Spacer()
                Text(stripeStateLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stripeStateColor)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await onStripePrimaryTap() }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.14))
                            .frame(width: 36, height: 36)
                        Image(systemName: stripePrimaryIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stripePrimaryTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(stripeSubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if stripeLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.black.opacity(0.05))
                )
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            }
            .buttonStyle(.plain)

            if (stripeStatus?.connected ?? false) == true {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await IA_openStripeManage() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.2.fill")
                        Text("Manage in Stripe")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
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

    // MARK: - Stripe computed labels
    private var stripePrimaryTitle: String {
        let connected = stripeStatus?.connected ?? false
        return connected ? "Stripe Connected" : "Connect with Stripe"
    }
    private var stripePrimaryIcon: String {
        let connected = stripeStatus?.connected ?? false
        return connected ? "checkmark.seal.fill" : "creditcard.fill"
    }
    private var stripeSubtitle: String {
        if let s = stripeStatus {
            if s.connected == true {
                let ready = (s.details_submitted == true && s.charges_enabled == true && s.payouts_enabled == true)
                return ready ? "Ready: charges & payouts enabled" : "Connected — finish verification to enable payouts"
            } else {
                return "Accept payments from your invoices"
            }
        }
        return "Accept payments from your invoices"
    }
    private var stripeStateLabel: String {
        if let s = stripeStatus {
            if !s.connected { return "Not connected" }
            let ready = (s.details_submitted == true && s.charges_enabled == true && s.payouts_enabled == true)
            return ready ? "Active" : "Needs setup"
        }
        return "Checking…"
    }
    private var stripeStateColor: Color {
        if let s = stripeStatus {
            if !s.connected { return .red }
            let ready = (s.details_submitted == true && s.charges_enabled == true && s.payouts_enabled == true)
            return ready ? .green : .orange
        }
        return .secondary
    }

    // MARK: - Stripe actions/helpers
    private func onStripePrimaryTap() async {
        if stripeStatus?.connected == true {
            await IA_openStripeManage()
        } else {
            await openStripeOnboarding()
        }
    }

    private func refreshStripeStatus() async {
        await MainActor.run { stripeLoading = true }
        let status = await IA_fetchStripeStatus()
        await MainActor.run {
            // Only update if we actually got a status.
            // If `status` is nil (offline / error), keep the last known Stripe state.
            if let status {
                self.stripeStatus = status
            } else if self.stripeStatus == nil {
                self.errorText = self.errorText ?? "You’re offline. Stripe status may be out of date."
            }
            self.stripeLoading = false
        }
    }

    private func openStripeOnboarding() async {
        await MainActor.run { stripeLoading = true }
        defer { Task { await MainActor.run { stripeLoading = false } } }

        let client = SupabaseManager.shared.client
        do {
            let session = try await client.auth.session
            guard let url = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co/functions/v1/create_connect_link") else { return }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let link = dict["url"],
               let linkURL = URL(string: link) {
                await UIApplication.shared.open(linkURL)
            }
        } catch {
            // silent for now
        }
    }

    // MARK: - Summary cards
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
                    Circle()
                        .fill(LinearGradient(colors: gradient.map { $0.opacity(0.18) },
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: gradient,
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
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
                    Circle()
                        .fill(LinearGradient(colors: gradient.map { $0.opacity(0.18) },
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: gradient,
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
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

    // MARK: - Actions
    private var actionCards: some View {
        VStack(spacing: 12) {
            NavigationLink {
                BrandingView(onBrandNameChanged: { new in
                    self.businessName = new
                })
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

    /// Fallback for when `profiles.display_name` hasn't been set yet (first launch etc.)
    private func fallbackName(from email: String) -> String {
        if let at = email.firstIndex(of: "@") {
            let base = email[..<at]
            let cleaned = base.replacingOccurrences(of: ".", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Your Business" : cleaned.capitalized
        }
        return "Your Business"
    }

    // MARK: - Reusable ActionCard
    private struct ActionCard: View {
        let icon: String
        let title: String
        let subtitle: String
        let gradient: [Color]

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: gradient.map { $0.opacity(0.18) },
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .foregroundStyle(LinearGradient(colors: gradient,
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
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

// MARK: - Profile screen (edits the single source of truth)
struct AccountDetailsView: View {
    let uid: String
    let displayName: String            // initial shown name
    let email: String
    var onNameChanged: (String) -> Void = { _ in }

    @State private var currentName: String = ""
    @State private var showEditName = false
    @State private var workingName: String = ""
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        List {
            // Header
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.red.opacity(0.30), Color.orange.opacity(0.28)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5))
                        Text(initials(currentName))
                            .font(.title3).bold()
                            .foregroundStyle(.white)
                    }
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentName).font(.headline)
                        Text("User ID: \(uid)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            // Profile details
            Section("Profile") {
                HStack {
                    Text("Type")
                    Spacer()
                    Text(accountTypeFrom(displayName: currentName))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Email")
                    Spacer()
                    Text(email.lowercased())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Text("Apple ID Relay")
                    Spacer()
                    Text(email.lowercased().contains("privaterelay.appleid.com") ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }
            }

            // Keep Branding separate (logo/colors/etc.)
            Section("Account") {
                NavigationLink {
                    BrandingView(onBrandNameChanged: { new in
                        self.currentName = new
                        self.onNameChanged(new)
                    })
                } label: {
                    Label("Branding", systemImage: "paintpalette")
                }

                NavigationLink {
                    InvoiceDefaultsView()
                } label: {
                    Label("Invoice defaults", systemImage: "doc.text")
                }
            }

            Section("Security") {
                Label("Password & sign-in", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if currentName.isEmpty { currentName = displayName }
        }
        .navigationTitle("Account Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") {
                workingName = currentName
                saveError = nil
                showEditName = true
            }
        }
        .sheet(isPresented: $showEditName) {
            NavigationStack {
                Form {
                    Section(header: Text("Doing Business As")) {
                        TextField("Your business name", text: $workingName)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                    }
                    if let err = saveError, !err.isEmpty {
                        Section { Text(err).foregroundStyle(.red) }
                    }
                }
                .navigationTitle("Edit name")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEditName = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") {
                            Task { await saveName() }
                        }
                        .disabled(saving || workingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Helpers
    private func initials(_ text: String) -> String {
        let parts = text.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        let res = (first + second)
        return res.isEmpty ? String(text.first ?? "A").uppercased() : res.uppercased()
    }

    private func accountTypeFrom(displayName: String) -> String {
        let n = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bizHints = [" llc", " inc", " corp", " co", " ltd", " company", " pllc", " pc", " studios", " group"]
        if n == "your business" { return "Business" }
        if bizHints.contains(where: { n.contains($0) }) { return "Business" }
        return "Personal"
    }

    // MARK: - Persist the single source of truth (profiles.display_name)
    private func saveName() async {
        let newName = workingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        await MainActor.run { saving = true; saveError = nil }

        let client = SupabaseManager.shared.client
        do {
            // 1) Update profiles.display_name (single source of truth)
            struct UpdatePayload: Encodable { let display_name: String }
            _ = try await client
                .from("profiles")
                .update(UpdatePayload(display_name: newName))
                .eq("id", value: uid)
                .execute()

            // 2) Optionally mirror to auth metadata full_name for ecosystem consistency
            let attrs = UserAttributes(data: ["full_name": AnyJSON.string(newName)])
            _ = try await client.auth.update(user: attrs)

            await MainActor.run {
                // Invalidate any cached branding and broadcast change so other screens (PDF, headers) update
                BrandingService.invalidateCache()
                NotificationCenter.default.post(name: .brandingDidChange, object: newName)

                // Update local UI state
                currentName = newName
                onNameChanged(newName)    // notify parent so header updates
                saving = false
                showEditName = false
            }
        } catch {
            await MainActor.run {
                saveError = error.localizedDescription
                saving = false
            }
        }
    }
}
