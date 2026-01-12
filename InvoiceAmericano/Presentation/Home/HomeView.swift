//
//  HomeView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/22/25.
//

import SwiftUI
import SceneKit
import Supabase
import Auth
import UIKit

// Fallback wrapper so NavigationStack can push an invoice preview.
// If your real screen is `InvoiceDetailView`, this forwards to it.
struct InvoicePreviewView: View {
    let invoiceId: UUID
    var body: some View {
        InvoiceDetailView(invoiceId: invoiceId)
    }
}

private struct PayLinkPayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct HomeView: View {
    @AppStorage("stripeLastStatusJSON") private var stripeLastStatusJSON: String = ""
    // Parent can switch tabs if needed (0=Home, 1=Invoices, 2=Clients, 3=Activity, 4=Account)
    var onSelectTab: ((Int) -> Void)? = nil

    @State private var stats: InvoiceService.AccountStats?
    @State private var recentInvoices: [InvoiceRow] = []
    @State private var recentActivity: [ActivityJoined] = []

    /// Single source of truth for “which invoice detail should we show?”
    @State private var activeInvoiceId: UUID? = nil

    @State private var isLoading = false
    @State private var errorText: String?

    // Stripe Connect state
    @State private var stripeStatus: StripeStatus?
    @State private var stripeLoading = false
    // MARK: - Stripe status cache (offline-friendly)
    private func loadCachedStripeStatus() -> StripeStatus? {
        guard !stripeLastStatusJSON.isEmpty,
              let data = stripeLastStatusJSON.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(StripeStatus.self, from: data)
    }

    private func saveCachedStripeStatus(_ status: StripeStatus) {
        guard let data = try? JSONEncoder().encode(status),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        stripeLastStatusJSON = json
    }
    
    // Stripe brand color (#635BFF) and "fully ready" state
    private let stripeBrand = Color(red: 0.388, green: 0.357, blue: 1.0) // #635BFF
    private var stripeFullyReady: Bool {
        if let s = stripeStatus, s.connected == true {
            return (s.details_submitted == true) && (s.charges_enabled == true) && (s.payouts_enabled == true)
        }
        return false
    }

    private var stripeSectionStatus: String {
        if stripeStatus == nil { return "Checking…" }
        return stripeFullyReady ? "Active" : "Action needed"
    }

    // Sheets
    @State private var showNewInvoice = false
    @State private var showInvoicesSheet = false
    @State private var showActivitySheet = false
    @State private var showAISheet = false
    @State private var payLinkPayload: PayLinkPayload? = nil

    // Unread activity count (for badge)
    @State private var unreadCount: Int = 0

    var body: some View {
        AppBackground {
            // MainTabView already wraps this in a NavigationStack
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // --- Summary cards ---
                    summaryCards
                    
                    // --- Quick actions (now adaptive grid) ---
                    quickActions
                    
                    // --- Payments (Stripe Connect) ---
                    paymentsSection
                    
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                    Spacer(minLength: 16)
                }
                .padding(.top, 12)
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewInvoice = true
                } label: {
                    Label("New Invoice", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationDestination(item: $activeInvoiceId) { invoiceId in
            InvoiceDetailView(invoiceId: invoiceId)
        }

        // ====== Sheets ======

        // New invoice sheet — after saving, jump straight to the new invoice detail
        .sheet(isPresented: $showNewInvoice) {
            NavigationStack {
                NewInvoiceView(onSaved: { draft in
                    Task {
                        do {
                            let (newId, checkoutURL) = try await InvoiceService.createInvoice(from: draft)
                            AnalyticsService.track(.invoiceCreated, metadata: ["source": "home"])
                            await refresh()
                            await MainActor.run {
                                activeInvoiceId = newId            // navigate to detail after dismiss
                                showNewInvoice = false
                            }

                            if let checkoutURL {
                                try? await Task.sleep(nanoseconds: 250_000_000) // allow sheet to dismiss smoothly
                                await MainActor.run {
                                    payLinkPayload = PayLinkPayload(url: checkoutURL)
                                }
                            }
                        } catch {
                            await MainActor.run { errorText = error.friendlyMessage }
                        }
                    }
                })
                .navigationTitle("New Invoice")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            }
        }

        .sheet(item: $payLinkPayload) { payload in
            ActivitySheet(items: ["Pay this invoice", payload.url]) { _, _ in
                payLinkPayload = nil
            }
        }
        
        // Recent Invoices sheet
        .sheet(isPresented: $showInvoicesSheet) {
            NavigationStack {
                RecentInvoicesSheet(
                    recentInvoices: recentInvoices,
                    onOpenFullInvoices: {
                        showInvoicesSheet = false
                        onSelectTab?(1)
                    },
                    onOpenInvoice: { invoiceId in
                        showInvoicesSheet = false
                        activeInvoiceId = invoiceId
                    }
                )
                .background(Color(.systemBackground).ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .navigationTitle("Recent Invoices")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showInvoicesSheet = false }
                    }
                }
            }
            .presentationDetents([.fraction(0.92), .large])
            .presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
            .scrollDismissesKeyboard(.immediately)
        }

        // Recent Activity sheet
        .sheet(isPresented: $showActivitySheet) {
            NavigationStack {
                RecentActivitySheet(
                    recentActivity: recentActivity,
                    onClose: { showActivitySheet = false },
                    onOpenFullActivity: {
                        showActivitySheet = false
                        onSelectTab?(3)
                    },
                    onOpenInvoice: { invoiceId in
                        showActivitySheet = false
                        activeInvoiceId = invoiceId
                    }
                )
                .background(Color(.systemBackground).ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .navigationTitle("Recent Activity")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showActivitySheet = false }
                    }
                }
            }
            .presentationDetents([.fraction(0.92), .large])
            .presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
            .scrollDismissesKeyboard(.immediately)
        }

        // AI Assistant sheet
        .sheet(isPresented: $showAISheet) {
            NavigationStack {
                AIAssistantComingSoonSheet(onClose: { showAISheet = false })
            }
        }

        .task {
            await refresh()
            await refreshStripe()
            await syncUnreadBadgesFromServer() // ← fetch unread count on first load
        }
        // Listen for unread count broadcasts from Activity screens
        .onReceive(NotificationCenter.default.publisher(for: .activityUnreadChanged)) { note in
            if let n = note.userInfo?["count"] as? Int {
                unreadCount = n
            }
        }
        .refreshable {
            await refresh()
            await syncUnreadBadgesFromServer()
        }
        .onChange(of: showActivitySheet) { _, isShowing in
            Task {
                if isShowing {
                    await markActivityAsSeenAndSyncBadges()
                } else {
                    await syncUnreadBadgesFromServer()
                }
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
//        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
    } // <-- close body

    // MARK: - Payments section (Stripe Connect)
    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Payments with Stripe")
                    .font(.headline)
                Spacer()
                Text(stripeSectionStatus)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        stripeStatus == nil
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(stripeFullyReady ? Color.green : Color.orange)
                    )
            }
            .padding(.horizontal)

            // --- Status card ---
            // Show the status/onboarding card unless the account is fully ready
            if stripeStatus == nil || !stripeFullyReady {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await onStripePrimaryTap() }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill((stripeFullyReady ? Color.green : Color.orange).opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: stripeFullyReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(stripeFullyReady ? .green : .orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stripeFullyReady ? "Stripe Connected" : "Connect with Stripe")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(stripeStatusText())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }

            // --- Primary action button under the card ---
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    if stripeFullyReady { await IA_openStripeManage() }
                    else { await openStripeOnboarding() }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(stripeBrand)
                    Group {
                        if stripeFullyReady {
                            // Centered, bold "stripe" wordmark-style label (no icon)
                            Text("stripe")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .kerning(0.5)
                        } else {
                            // Connect CTA with icon
                            HStack(spacing: 10) {
                                Image(systemName: "link.badge.plus")
                                    .foregroundStyle(.white)
                                Text("Connect with Stripe")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                if stripeLoading { ProgressView().tint(.white) }
                            }
                            .padding(18)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 68)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .disabled(stripeLoading)
            .opacity(stripeLoading ? 0.8 : 1.0)
        }
        .padding(.top, 2)
        .onAppear { Task { await refreshStripe() } }
    }

    private func stripeStatusText() -> String {
        // If we don't have a status yet, show the generic connect prompt
        guard let s = stripeStatus else {
            return "Connect to accept payments from your invoices."
        }
        // Not connected yet
        guard s.connected == true else {
            return "Connect to accept payments from your invoices."
        }
        // Fully ready
        if stripeFullyReady { return "Ready: charges & payouts enabled" }
        // Connected but still needs steps
        var parts: [String] = []
        if s.details_submitted != true { parts.append("finish verification") }
        if s.charges_enabled != true { parts.append("enable charges") }
        if s.payouts_enabled != true { parts.append("enable payouts") }
        if parts.isEmpty { return "Finalizing Stripe setup…" }
        return "Connected — " + parts.joined(separator: " • ") + "."
    }

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
                let all = [s.details_submitted == true, s.charges_enabled == true, s.payouts_enabled == true]
                if all.allSatisfy({ $0 }) {
                    return "Ready: charges & payouts enabled"
                } else {
                    return "Connected — finish verification to enable payouts"
                }
            } else {
                return "Connect to accept payments"
            }
        }
        return "Connect to accept payments"
    }

    // Primary tap handler: connect if not connected, otherwise open manage
    private func onStripePrimaryTap() async {
        if stripeStatus?.connected == true {
            await IA_openStripeManage()
        } else {
            await openStripeOnboarding()
        }
    }

    // MARK: - Stripe helpers
    private func refreshStripe() async {
        await MainActor.run { stripeLoading = true }

        // Try to fetch live status from Stripe via Supabase
        let status = await IA_fetchStripeStatus()

        await MainActor.run {
            stripeLoading = false

            if let s = status {
                // ✅ Online and got a real status: use it and cache it
                stripeStatus = s
                saveCachedStripeStatus(s)
            } else {
                // ❌ Could not fetch (e.g., offline). If we have nothing in memory yet,
                // fall back to the last known good status from local storage.
                if stripeStatus == nil, let cached = loadCachedStripeStatus() {
                    stripeStatus = cached
                }
            }
        }
    }

    // Opens the Connect onboarding link from your Edge Function
    private func openStripeOnboarding() async {
        await MainActor.run { stripeLoading = true }
        defer { Task { await MainActor.run { stripeLoading = false } } }

        do {
            let client = SupabaseManager.shared.client
            guard
                let session = try? await client.auth.session,
                let url = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co/functions/v1/create_connect_link")
            else { return }

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
            await MainActor.run { self.errorText = error.friendlyMessage }
        }
    }

    // MARK: - Sections

    private var summaryCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SummaryStatCard(title: "Invoices", value: "\(stats?.totalCount ?? 0)", systemImage: "doc.on.doc", tint: .blue)
                SummaryStatCard(title: "Paid", value: "\(stats?.paidCount ?? 0)", systemImage: "checkmark.seal.fill", tint: .green)
            }
            SummaryStatCardLarge(
                title: "Outstanding Balance",
                value: currency(stats?.outstandingAmount ?? 0),
                systemImage: "clock.badge",
                tint: .orange
            )
        }
        .padding(.horizontal)
    }

    private struct SummaryStatCard: View {
        let title: String
        let value: String
        let systemImage: String
        let tint: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                // Icon badge
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }

                // Big value — mono digits, never wraps
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                // Title
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
                    .strokeBorder(.black.opacity(0.04))
            )
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(title): \(value)"))
        }
    }

    private struct SummaryStatCardLarge: View {
        let title: String
        let value: String
        let systemImage: String
        let tint: Color

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(10)
                    .background(Circle().fill(tint.opacity(0.15)))
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
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }

    private var quickActions: some View {
        // Adaptive grid: 1–3 columns depending on width
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

        return VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions").font(.headline).padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 12) {
                // New
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showNewInvoice = true
                } label: {
                    QuickActionCard(title: "New",
                                    systemImage: "plus.circle.fill",
                                    colors: [.blue, .indigo])
                                    .scaleEffect(showNewInvoice ? 0.97 : 1.0)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showNewInvoice)
                }
                .buttonStyle(.plain)

                // Invoices -> slide up recent invoices
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showInvoicesSheet = true
                } label: {
                    QuickActionCard(title: "Invoices",
                                    systemImage: "doc.plaintext.fill",
                                    colors: [.green, .teal])
                }
                .buttonStyle(.plain)

                // Activity -> slide up recent activity
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showActivitySheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        QuickActionCard(title: "Activity",
                                        systemImage: "bell.badge.fill",
                                        colors: [.purple, .pink])
                        if unreadCount > 0 {
                            UnreadBadge(count: unreadCount)
                                .padding(.top, 6)
                                .padding(.trailing, 6)
                        }
                    }
                }
                .buttonStyle(.plain)

                // AI Assistant -> custom animated badge
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAISheet = true
                } label: {
                    VStack(spacing: 10) {
                        AIMobius3DBadge(size: 45)
                        Text("AI Assistant")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .padding(.vertical, 12)
                    .background(
                        // darker “AI” gradient card for contrast
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.75), Color.indigo.opacity(0.85)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    // You’re currently not showing these in the main body, but keeping them for reuse.
    private var invoicesList: some View {
        LazyVStack(spacing: 0) {
            if recentInvoices.isEmpty && !isLoading {
                Text("No recent invoices").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                ForEach(recentInvoices, id: \.id) { row in
                    NavigationLink(value: row.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.client?.name ?? "—")
                                    .font(.subheadline).bold()
                                Text(row.number)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(currency(row.total ?? 0))
                                    .font(.subheadline)
                                StatusPill(status: row.status)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private var activityPreview: some View {
        VStack(spacing: 0) {
            if recentActivity.isEmpty && !isLoading {
                Text("No recent activity").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(recentActivity, id: \.id) { (a: ActivityJoined) in
                        if let id = a.invoice_id {
                            NavigationLink(value: id) {
                                ActivityCardRow(a: a)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ActivityCardRow(a: a)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color(.systemBackground))
    }


    // MARK: - Data load

    private func refresh() async {
        await MainActor.run {
            isLoading = true
            errorText = nil
        }

        async let s = InvoiceService.fetchAccountStats()
        async let inv = InvoiceService.fetchRecentInvoices(limit: 5)
        async let act: [ActivityJoined] = {
            do {
                let rows = try await ActivityService.fetchRecentActivityJoined(limit: 5)
                if rows.isEmpty {
                    await ActivityService.debugDumpRecentActivityJSON(limit: 5)
                }
                return rows
            } catch {
                await ActivityService.debugDumpRecentActivityJSON(limit: 5)
                print("⚠️ Activity decode failed, defaulting to empty: \(error)")
                return []
            }
        }()

        do {
            let (stats, invoices, activity) = try await (s, inv, act)
            await MainActor.run {
                self.stats = stats
                self.recentInvoices = invoices
                self.recentActivity = activity
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorText = error.friendlyMessage
                self.isLoading = false
            }
        }
    }

    // MARK: - Helpers
    

    /// Marks unread activity + notifications as read, then re-syncs badges from the server.
    private func markActivityAsSeenAndSyncBadges() async {
        // Mark activity feed rows as read
        _ = await ActivityService.markAllUnreadForCurrentUser()

        // Also mark push-backed notification rows as read so the APNs badge stops growing
        await NotificationService.markAllNotificationsReadForCurrentUser()

        // Recount from server and broadcast
        await syncUnreadBadgesFromServer()
    }

    /// Recounts unread activity and updates in-app + app icon badges consistently.
    private func syncUnreadBadgesFromServer() async {
        let n = (try? await ActivityService.countUnread()) ?? 0

        await MainActor.run {
            unreadCount = n
            NotificationCenter.default.post(
                name: .activityUnreadChanged,
                object: nil,
                userInfo: ["count": n]
            )
        }

        // Keep the app icon badge aligned with the latest unread count.
        await NotificationService.setAppBadgeCount(n)
    }

    private func currency(_ value: Double, code: String? = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = (code ?? "USD").uppercased()
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func relativeTime(_ iso: String) -> String {
        // Try ISO with/without fractional seconds; fallback to yyyy-MM-dd
        let isoNoFS = ISO8601DateFormatter()
        isoNoFS.formatOptions = [.withInternetDateTime]
        let isoFS = ISO8601DateFormatter()
        isoFS.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ymd = DateFormatter()
        ymd.dateFormat = "yyyy-MM-dd"
        ymd.timeZone = TimeZone(secondsFromGMT: 0)

        let d = isoNoFS.date(from: iso) ?? isoFS.date(from: iso) ?? ymd.date(from: iso) ?? Date()
        let comps = Calendar.current.dateComponents([.minute,.hour,.day], from: d, to: Date())
        if let day = comps.day, day > 0 { return "\(day)d ago" }
        if let hour = comps.hour, hour > 0 { return "\(hour)h ago" }
        if let min = comps.minute, min > 0 { return "\(min)m ago" }
        return "just now"
    }

    private func icon(for event: String) -> String {
        switch event.lowercased() {
        case "created": return "doc.badge.plus"
        case "sent": return "paperplane"
        case "paid": return "checkmark.seal"
        case "status_changed": return "arrow.triangle.2.circlepath"
        default: return "bell"
        }
    }

    private func activityTitle(_ a: ActivityJoined) -> String {
        let inv = a.invoiceNumber
        let who = a.clientName
        switch a.event.lowercased() {
        case "paid":    return "Invoice \(inv) — Paid\(who == "—" ? "" : " (\(who))")"
        case "sent":    return "Invoice \(inv) — Sent\(who == "—" ? "" : " (\(who))")"
        case "created": return "Invoice \(inv) — Created\(who == "—" ? "" : " (\(who))")"
        default:        return "Invoice \(inv) — \(a.event.capitalized)\(who == "—" ? "" : " (\(who))")"
        }
    }
}

// ===== Custom UI Pieces =====

// Polished quick-action card
private struct QuickActionCard: View {
    let title: String
    let systemImage: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// Pill used in Home list for recent invoices

// Tiny red badge used on Activity quick action
private struct UnreadBadge: View {
    let count: Int
    var body: some View {
        Text(display)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.red))
            .foregroundStyle(.white)
            .accessibilityLabel(Text("\(display) unread"))
    }
    private var display: String {
        count > 99 ? "99+" : "\(count)"
    }
}
private struct StatusPill: View {
    let status: String
    var body: some View {
        Text(status.capitalized)
            .font(.caption2).bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(color(for: status).opacity(0.15))
            )
            .foregroundStyle(color(for: status))
    }

    private func color(for s: String) -> Color {
        switch s.lowercased() {
        case "paid": return .green
        case "sent": return .blue
        case "overdue": return .red
        case "open", "draft": return .orange
        default: return .gray
        }
    }
}

// ===== Sheets =====
private struct RecentInvoicesSheet: View {
    enum Filter: String, CaseIterable { case all, open, sent, paid, overdue }

    let recentInvoices: [InvoiceRow]
    var onOpenFullInvoices: (() -> Void)? = nil
    var onOpenInvoice: ((UUID) -> Void)? = nil

    @State private var filter: Filter = .all
    @State private var search = ""

    // --- derived list ---
    private var filtered: [InvoiceRow] {
        let base = recentInvoices.filter { inv in
            guard !search.isEmpty else { return true }
            let hay = "\(inv.number) \(inv.client?.name ?? "")".lowercased()
            return hay.contains(search.lowercased())
        }
        guard filter != .all else { return base }
        return base.filter { inv in
            switch filter {
            case .all: return true
            case .open: return inv.status == "open" && inv.sent_at == nil
            case .sent: return inv.status == "open" && inv.sent_at != nil
            case .paid: return inv.status == "paid"
            case .overdue: return inv.status == "overdue"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ===== Header controls (filters + search) =====
                VStack(alignment: .leading, spacing: 8) {
                    // Quick filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases, id: \.self) { (f: Filter) in
                                Button {
                                    filter = f
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: icon(for: f))
                                        Text(title(for: f))
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(
                                            filter == f
                                            ? Color.blue.opacity(0.18)
                                            : Color(.secondarySystemBackground)
                                        )
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(
                                            filter == f ? Color.blue.opacity(0.35)
                                                        : Color.black.opacity(0.06)
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    // Search
                    TextField("Search by number or client", text: $search)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
                .padding(.horizontal)

                // ===== Invoices list (cards) =====
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").font(.title2)
                        Text(emptyCopy)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { (inv: InvoiceRow) in
                            Button {
                                onOpenInvoice?(inv.id)
                            } label: {
                                InvoiceCardRow(inv: inv)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                // ===== Footer =====
                Button {
                    onOpenFullInvoices?()
                } label: {
                    Label("Open full invoices list", systemImage: "list.bullet.rectangle")
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Small helpers
    private func title(for f: Filter) -> String {
        switch f {
        case .all: return "All"
        case .open: return "Open"
        case .sent: return "Sent"
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        }
    }
    private func icon(for f: Filter) -> String {
        switch f {
        case .all: return "line.3.horizontal.decrease.circle"
        case .open: return "clock"
        case .sent: return "paperplane"
        case .paid: return "checkmark.seal"
        case .overdue: return "exclamationmark.triangle"
        }
    }
    private var emptyCopy: String {
        search.isEmpty ? "No invoices for this filter yet" : "No results for “\(search)”"
    }
}

// ==============================
// Card-style row used above
// ==============================
private struct InvoiceCardRow: View {
    let inv: InvoiceRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left icon
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(gradient)
                Image(systemName: "doc.text")
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(width: 36, height: 36)

            // Title & client
            VStack(alignment: .leading, spacing: 2) {
                Text(inv.client?.name ?? "—")
                    .font(.subheadline.weight(.semibold))
                Text(inv.number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Amount + status
            VStack(alignment: .trailing, spacing: 6) {
                Text(currency(inv.total))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                StatusPillSmall(text: displayStatus(inv))
            }

            // Chevron INSIDE the card
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.black.opacity(0.05))
        )
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private func displayStatus(_ inv: InvoiceRow) -> String {
        if inv.status == "open", inv.sent_at != nil { return "Sent" }
        return inv.status.capitalized
    }
    private func currency(_ total: Double?) -> String {
        let n = NumberFormatter()
        n.numberStyle = .currency
        n.currencyCode = "USD"
        return n.string(from: NSNumber(value: total ?? 0)) ?? "$0.00"
    }
}

// small chip to match Home
private struct StatusPillSmall: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var color: Color {
        switch text.lowercased() {
        case "paid": return .green
        case "overdue": return .red
        case "sent": return .blue
        case "open", "draft": return .orange
        default: return .gray
        }
    }
}

// minimal chip used only inside the sheet
private struct StatusChip: View {
    let status: String
    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var color: Color {
        switch status.lowercased() {
        case "paid": return .green
        case "sent": return .yellow
        case "overdue": return .red
        case "open": return .blue
        default: return .gray
        }
    }
}

// RecentActivitySheet
private struct RecentActivitySheet: View {
    enum Filter: String, CaseIterable {
        case all, created, sent, opened, paid, dueSoon, overdue
    }

    let recentActivity: [ActivityJoined]
    var onClose: (() -> Void)? = nil
    var onOpenFullActivity: (() -> Void)? = nil
    var onOpenInvoice: ((UUID) -> Void)? = nil

    @State private var filter: Filter = .all
    @State private var search = ""

    // MARK: - Derived list
    private var filtered: [ActivityJoined] {
        let base = recentActivity.filter { a in
            guard !search.isEmpty else { return true }
            let hay = "\(a.invoiceNumber) \(a.clientName)".lowercased()
            return hay.contains(search.lowercased())
        }
        guard filter != .all else { return base }
        return base.filter { a in
            switch filter {
            case .all:      return true
            case .created:  return a.event == "created"
            case .sent:     return a.event == "sent"
            case .opened:   return a.event == "opened"
            case .paid:     return a.event == "paid"
            case .dueSoon:  return a.event == "due_soon"
            case .overdue:  return a.event == "overdue"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ===== Header controls (filters + search) =====
                VStack(alignment: .leading, spacing: 8) {
                    // Filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases, id: \.self) { (f: Filter) in
                                Button {
                                    filter = f
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: iconFor(filter: f))
                                        Text(titleFor(filter: f))
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(
                                            filter == f
                                            ? Color.purple.opacity(0.18)
                                            : Color(.secondarySystemBackground)
                                        )
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(
                                            filter == f ? Color.purple.opacity(0.35)
                                                        : Color.black.opacity(0.06)
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    // Search
                    TextField("Search by invoice or client", text: $search)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
                .padding(.horizontal)

                // ===== Grouped activity list (cards) =====
                let groups = groupByDay(filtered)
                let keys = groupedDayKeys(from: groups)

                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bell.slash").font(.title2)
                        Text(search.isEmpty ? "No activity for this filter yet"
                                            : "No results for “\(search)”")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                } else {
                    VStack(spacing: 18) {
                        ForEach(keys, id: \.self) { dayKey in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(dayHeader(from: dayKey))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)

                                LazyVStack(spacing: 12) {
                                    let rows: [ActivityJoined] = groups[dayKey] ?? []
                                    ForEach(rows) { (a: ActivityJoined) in
                                        Group {
                                            if let id = a.invoice_id {
                                                Button {
                                                    onOpenInvoice?(id)
                                                } label: {
                                                    ActivityCardRow(a: a)
                                                }
                                                .buttonStyle(.plain)
                                            } else {
                                                ActivityCardRow(a: a)
                                            }
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                Task {
                                                    try? await ActivityService.delete(id: a.id)
                                                    await recalcAndBroadcastUnread()
                                                }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }

                // ===== Footer =====
                Button {
                    onOpenFullActivity?()
                } label: {
                    Label("Open full activity feed", systemImage: "list.bullet.rectangle")
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Helpers (self-contained)

    private func titleFor(filter f: Filter) -> String {
        switch f {
        case .all: return "All"
        case .created: return "Created"
        case .sent: return "Sent"
        case .opened: return "Opened"
        case .paid: return "Paid"
        case .dueSoon: return "Due Soon"
        case .overdue: return "Overdue"
        }
    }
    private func iconFor(filter f: Filter) -> String {
        switch f {
        case .all: return "line.3.horizontal.decrease.circle"
        case .created: return "doc.badge.plus"
        case .sent: return "paperplane"
        case .opened: return "eye"
        case .paid: return "checkmark.seal"
        case .dueSoon: return "clock.badge.exclamationmark"
        case .overdue: return "exclamationmark.triangle"
        }
    }

    // Sectioning
    private func groupByDay(_ items: [ActivityJoined]) -> [String: [ActivityJoined]] {
        Dictionary(grouping: items) { row in
            dayKey(for: isoDate(from: row.created_at))
        }
    }
    private func groupedDayKeys(from groups: [String: [ActivityJoined]]) -> [String] {
        groups.keys.sorted(by: >)
    }
    private func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    private func dayHeader(from key: String) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key) else { return key }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        return out.string(from: d)
    }

    // Time + unread
    private func isoDate(from s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s) ?? Date()
    }
    private func relativeTime(_ s: String) -> String {
        let d = isoDate(from: s)
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .short
        return r.localizedString(for: d, relativeTo: Date())
    }
    
    // CHANGE: Recompute unread count and broadcast the real value to Home/others.
    // This helper intentionally does not navigate or mutate parent state;
    // listeners (e.g., HomeView) update their own `unreadCount` from the notification.
    private func recalcAndBroadcastUnread() async {
        let n = (try? await ActivityService.countUnread()) ?? 0
        await NotificationService.setAppBadgeCount(n)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .activityUnreadChanged,
                object: nil,
                userInfo: ["count": n]
            )
        }
    }
}


// Card-style activity row

private struct ActivityCardRow: View {
    let a: ActivityJoined

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Leading icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconGradient)
                Image(systemName: iconFor(a.event))
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(width: 36, height: 36)

            // LEFT: Client name + invoice number (two-line, like Invoices UI)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.clientName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(a.invoiceNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // RIGHT: Event type chip + chevron (inside the card)
            HStack(spacing: 8) {
                StatusPillTiny(text: eventDisplay(a.event))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.black.opacity(0.05))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(relativeTime(a.created_at)))
    }

    // Gradient tint for the icon based on event
    private var iconGradient: LinearGradient {
        let colors: [Color]
        switch a.event {
        case "created":  colors = [.blue, .indigo]
        case "sent":     colors = [.teal, .blue]
        case "opened":   colors = [.purple, .pink]
        case "paid":     colors = [.green, .teal]
        case "due_soon": colors = [.orange, .pink]
        case "overdue":  colors = [.red, .orange]
        default:          colors = [.gray, .gray.opacity(0.7)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func iconFor(_ event: String) -> String {
        switch event {
        case "created":  return "doc.badge.plus"
        case "opened":   return "eye"
        case "sent":     return "paperplane"
        case "paid":     return "checkmark.seal"
        case "overdue":  return "exclamationmark.triangle"
        case "due_soon": return "clock.badge.exclamationmark"
        default:          return "bell"
        }
    }

    private func eventDisplay(_ event: String) -> String {
        switch event.lowercased() {
        case "created":  return "Created"
        case "sent":     return "Sent"
        case "opened":   return "Opened"
        case "paid":     return "Paid"
        case "overdue":  return "Overdue"
        case "due_soon": return "Due Soon"
        default:          return event.capitalized
        }
    }

    private func relativeTime(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) {
            let r = RelativeDateTimeFormatter()
            r.unitsStyle = .short
            return r.localizedString(for: d, relativeTo: Date())
        }
        return s
    }

    // Single, compact accessibility label mirroring the visual layout
    private var accessibilityLabel: Text {
        Text("\(a.clientName), \(a.invoiceNumber), \(eventDisplay(a.event)), \(relativeTime(a.created_at))")
    }
}

// tiny chip used on activity rows
private struct StatusPillTiny: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var color: Color {
        switch text.lowercased() {
        case "paid": return .green
        case "overdue": return .red
        case "sent": return .blue
        default: return .gray
        }
    }
}

// ===== Custom AI badge (fix for missing AIMobiusBadge) =====

// === 3D Möbius strip badge (SceneKit) ===

private struct AIMobius3DBadge: View {
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            // subtle glow – does NOT clip content
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .blur(radius: 2)

            // 3D Möbius ribbon (no padding, no clipping)
            MobiusSceneView()
        }
        // Give the 3D view generous height and keep aspect square so it won't crop
        .frame(width: size * 1.2, height: size * 1.2)
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct MobiusSceneView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.layer.masksToBounds = false
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.allowsCameraControl = false
        view.backgroundColor = .clear

        // Scene
        let scene = SCNScene()
        view.scene = scene
        view.isPlaying = true
        view.antialiasingMode = .multisampling4X

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0.05, 3.4)
        if let cam = cameraNode.camera {
            cam.wantsHDR = true
            cam.bloomIntensity = 0.8
            cam.bloomThreshold = 0.6
            cam.bloomBlurRadius = 8.0
            cam.fieldOfView = 38
        }
        scene.rootNode.addChildNode(cameraNode)

        // Key light
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.position = SCNVector3(3, 4, 5)
        key.light?.intensity = 1200
        scene.rootNode.addChildNode(key)

        // Rim light
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.eulerAngles = SCNVector3(-Float.pi/3, Float.pi/6, 0)
        rim.light?.intensity = 900
        scene.rootNode.addChildNode(rim)

        // Ambient fill so the ribbon is always visible
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        ambient.light?.color = UIColor(white: 1.0, alpha: 1.0)
        scene.rootNode.addChildNode(ambient)

        // Möbius node
        let mobiusNode = SCNNode(geometry: makeMobiusGeometry(R: 1.0, width: 0.35, uCount: 180, vCount: 24))
        mobiusNode.geometry?.firstMaterial = Self.makeMaterial()
        mobiusNode.eulerAngles = SCNVector3(-0.25, 0.45, 0) // slight tilt
        mobiusNode.scale = SCNVector3(0.75, 0.75, 0.75)
        scene.rootNode.addChildNode(mobiusNode)

        // Slow continuous spin + gentle bob
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 9.0))
        let bobUp = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 1.8)
        bobUp.timingMode = .easeInEaseOut
        let bobDown = bobUp.reversed()
        let bob = SCNAction.repeatForever(.sequence([bobUp, bobDown]))
        mobiusNode.runAction(SCNAction.group([spin, bob]))

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    private static func makeMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased

        // Create a colorful gradient texture once and use it for both diffuse & emission.
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor.systemPink.cgColor,
            UIColor.cyan.cgColor,
            UIColor.systemBlue.cgColor,
            UIColor.systemIndigo.cgColor,
            UIColor.systemPurple.cgColor,
            UIColor.systemPink.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint   = CGPoint(x: 1, y: 0.5)
        gradient.frame = CGRect(x: 0, y: 0, width: 512, height: 512)
        
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 12
        rotation.repeatCount = .infinity
        gradient.add(rotation, forKey: "rotate")

        UIGraphicsBeginImageContextWithOptions(gradient.frame.size, false, 2)
        gradient.render(in: UIGraphicsGetCurrentContext()!)
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Use gradient for color + a soft glow to ensure visibility.
        m.diffuse.contents = img
        m.emission.contents = img
        m.emission.intensity = 0.55

        // Slightly glossy metal look
        m.metalness.contents = 0.6
        m.roughness.contents = 0.3

        m.isDoubleSided = true
        return m;
    }
}

// MARK: - Möbius generator
/// Builds a Möbius strip mesh parameterized over (u, v):
///  u in [0, 1] around the loop; v in [-1, 1] across the width.
private func makeMobiusGeometry(R: Float, width: Float, uCount: Int, vCount: Int) -> SCNGeometry {
    // Clamp counts
    let U = max(12, uCount)
    let V = max(2, vCount)

    var vertices: [SCNVector3] = []
    var normals:  [SCNVector3] = []
    var uvs:      [CGPoint] = []
    var indices:  [CInt] = []

    func p(u: Float, v: Float) -> SIMD3<Float> {
        // u ∈ [0, 1], v ∈ [-1, 1]
        let theta = u * 2.0 * Float.pi                // loop angle
        let halfTwist = theta / 2.0                   // half twist over one revolution
        let w = (width * v)

        // Center circle + rotated offset
        let x = (R + w * cos(halfTwist)) * cos(theta)
        let y = (R + w * cos(halfTwist)) * sin(theta)
        let z =  w * sin(halfTwist)
        return SIMD3<Float>(x, y, z)
    }

    // Generate grid
    for ui in 0...U {
        for vi in 0...V {
            let uu = Float(ui) / Float(U)         // [0, 1]
            let vv = (Float(vi) / Float(V)) * 2 - 1  // [-1, 1]

            // Position
            let pos = p(u: uu, v: vv)
            vertices.append(SCNVector3(pos))

            // Approximate normal via local derivatives
            let eps: Float = 0.001
            let pu = p(u: min(1, uu + eps), v: vv) - p(u: max(0, uu - eps), v: vv)
            let pv = p(u: uu, v: min(1, vv + eps)) - p(u: uu, v: max(-1, vv - eps))
            var n = simd_normalize(simd_cross(pu, pv))
            if !(n.x.isFinite && n.y.isFinite && n.z.isFinite) || simd_length(n) == 0 {
                n = SIMD3<Float>(0, 0, 1)
            }
            normals.append(SCNVector3(n))

            // Simple UVs
            uvs.append(CGPoint(x: CGFloat(uu), y: CGFloat((vv + 1) * 0.5)))
        }
    }

    // Triangles
    let stride = V + 1
    for ui in 0..<U {
        for vi in 0..<V {
            let a = CInt(ui * stride + vi)
            let b = CInt((ui + 1) * stride + vi)
            let c = CInt((ui + 1) * stride + (vi + 1))
            let d = CInt(ui * stride + (vi + 1))

            // two triangles: a-b-c and a-c-d
            indices.append(contentsOf: [a, b, c, a, c, d])
        }
    }

    let vSrc = SCNGeometrySource(vertices: vertices)
    let nSrc = SCNGeometrySource(normals: normals)
    let tSrc = SCNGeometrySource(textureCoordinates: uvs)
    let idxData = Data(bytes: indices, count: indices.count * MemoryLayout<CInt>.size)
    let elem = SCNGeometryElement(data: idxData,
                                  primitiveType: .triangles,
                                  primitiveCount: indices.count / 3,
                                  bytesPerIndex: MemoryLayout<CInt>.size)

    let geo = SCNGeometry(sources: [vSrc, nSrc, tSrc], elements: [elem])
    return geo
}
private struct AIAssistantComingSoonSheet: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AIMobius3DBadge(size: 64)
                    .padding(.top, 20)

                Text("AI Assistant")
                    .font(.title2.bold())

                Text("Coming in Version 2.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Soon, you’ll be able to integrate your smart glasses to take pictures & videos, record audible notes with translation for your assistant to auto-generate the estimate or invoices for at your convenience.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Button("Done") {
                    onClose?()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
        // Allow the sheet to grow and be scrolled to full height
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }
}
// MARK: - AI Ouroboros Badge
private struct AIOuroborosBadge: View {
    var size: CGFloat = 36

    @State private var spin: Double = 0
    @State private var breathe: CGFloat = 0

    var body: some View {
        let ring = size
        let lineW = max(1.8, size * 0.09)
        let headSize = max(6, size * 0.22)
        let radius = ring * 0.42

        ZStack {
            // soft glow halo
            Circle()
                .stroke(
                    RadialGradient(
                        colors: [Color.indigo.opacity(0.35), .clear],
                        center: .center, startRadius: 0, endRadius: ring * 0.65
                    ),
                    lineWidth: lineW
                )
                .frame(width: ring, height: ring)
                .blur(radius: 1.2)
                .opacity(0.9)

            // scales/body (subtle dashed arc that breathes)
            Circle()
                .trim(from: 0, to: 0.88)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .cyan, .blue, .indigo, .purple, .cyan
                        ]),
                        center: .center,
                        angle: .degrees(spin)
                    ),
                    style: StrokeStyle(
                        lineWidth: lineW,
                        lineCap: .round,
                        dash: [max(1.2, lineW * 0.9), max(2.2, lineW * 1.6 + breathe)],
                        dashPhase: breathe * 6
                    )
                )
                .frame(width: ring, height: ring)
                .rotationEffect(.degrees(-90))

            // tail nib (tiny fade at the end of the trim)
            Circle()
                .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: lineW * 0.9, height: lineW * 0.9)
                .offset(x: 0, y: -radius)
                .rotationEffect(.degrees(spin + 220))

            // head (simple, tasteful “snake head” with eye)
            ZStack {
                // head
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: headSize * 1.1, height: headSize * 0.72)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)

                // eye
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: headSize * 0.22, height: headSize * 0.22)
                    .offset(x: headSize * 0.18)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: headSize * 0.08)
                            .offset(x: headSize * 0.22, y: -headSize * 0.06)
                    )
            }
            .offset(x: 0, y: -radius)
            .rotationEffect(.degrees(spin))

        }
        .frame(width: ring, height: ring)
        .onAppear {
            // smooth continuous spin
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                spin = 360
            }
            // gentle breathing of the dash spacing
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathe = 1
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Themed "New Invoice" Sheet

struct ThemedNewInvoiceSheet: View {
    let onSaved: (InvoiceDraft) -> Void
    var onClose: (() -> Void)? = nil

    // Match the "New" quick action gradient
    private let gradient = LinearGradient(
        colors: [Color.blue, Color.indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        NavigationStack {
            ZStack {
                // Background: flatten to a single layer to prevent streaks
                Color(.systemBackground).ignoresSafeArea()
                gradient.opacity(0.08).blendMode(.overlay)

                // Content card
                VStack(spacing: 0) {
                    // Grabber + title area
                    VStack(spacing: 10) {
                        Capsule()
                            .fill(.secondary.opacity(0.35))
                            .frame(width: 36, height: 5)
                            .padding(.top, 8)
                    }
                    // .background(.ultraThinMaterial) // Removed to prevent translucency streak

                    // Your invoice form
                    NewInvoiceView(onSaved: onSaved)
                        .scrollContentBackground(.hidden) // Form blends into our bg
                        // .background(Color.clear) // Removed to prevent translucency streak
                        .tint(.indigo) // controls buttons/links inside the form
                }
                .background(
                    // Soft card behind the form for contrast
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.background) // adapts to light/dark
                        .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
                        .ignoresSafeArea()
                )
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: ((Bool, UIActivity.ActivityType?) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { activityType, completed, _, _ in
            onComplete?(completed, activityType)
        }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
