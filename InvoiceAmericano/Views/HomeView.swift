//
//  HomeView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/22/25.
//

import SwiftUI
import SceneKit

struct HomeView: View {
    // Parent can switch tabs if needed (0=Home, 1=Invoices, 2=Clients, 3=Activity, 4=Account)
    var onSelectTab: ((Int) -> Void)? = nil

    @State private var stats: InvoiceService.AccountStats?
    @State private var recentInvoices: [InvoiceRow] = []
    @State private var recentActivity: [ActivityJoined] = []

    @State private var isLoading = false
    @State private var errorText: String?

    // Sheets
    @State private var showNewInvoice = false
    @State private var showInvoicesSheet = false
    @State private var showActivitySheet = false
    @State private var showAISheet = false

    var body: some View {
        // MainTabView already wraps this in a NavigationStack
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // --- Summary cards ---
                summaryCards

                // --- Quick actions (now adaptive grid) ---
                quickActions

                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                        .padding(.horizontal)
                }
                Spacer(minLength: 16)
            }
            .padding(.top, 12)
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewInvoice = true
                } label: {
                    Label("New Invoice", systemImage: "plus.circle.fill")
                }
            }
        }

        // ====== Sheets ======

        // New invoice sheet
        .sheet(isPresented: $showNewInvoice) {
            ThemedNewInvoiceSheet(
                onSaved: { draft in
                    Task {
                        do {
                            _ = try await InvoiceService.createInvoice(from: draft)
                            await refresh()
                            await MainActor.run { showNewInvoice = false }
                        } catch {
                            await MainActor.run { errorText = error.localizedDescription }
                        }
                    }
                },
                onClose: { showNewInvoice = false }
            )
            // Keep it tall and on-brand
            .presentationDetents([.fraction(0.90), .large])   // lets users pull higher if needed
            .presentationCornerRadius(28)
            .presentationDragIndicator(.hidden)               // we draw our own
            .presentationBackground(.ultraThinMaterial)       // subtle glass
        }

        // Recent Invoices sheet
        .sheet(isPresented: $showInvoicesSheet) {
            NavigationStack {
                RecentInvoicesSheet(
                    recentInvoices: recentInvoices,
                    onClose: { showInvoicesSheet = false },
                    onOpenFullInvoices: {
                        // dismiss then jump to the Invoices tab
                        showInvoicesSheet = false
                        onSelectTab?(1)
                    }
                )
                // keep this so tapping rows in the sheet can still go to details
                .navigationDestination(for: UUID.self) { invoiceId in
                    InvoiceDetailView(invoiceId: invoiceId)
                }
            }
        }

        // Recent Activity sheet
        .sheet(isPresented: $showActivitySheet) {
            NavigationStack {
                RecentActivitySheet(
                    recentActivity: recentActivity,
                    onClose: { showActivitySheet = false },
                    onOpenFullActivity: {
                        // dismiss then jump to the Activity tab
                        showActivitySheet = false
                        onSelectTab?(3)
                    }
                )
                .navigationDestination(for: UUID.self) { invoiceId in
                    InvoiceDetailView(invoiceId: invoiceId)
                }
            }
        }

        // AI Assistant sheet
        .sheet(isPresented: $showAISheet) {
            NavigationStack {
                AIAssistantComingSoonSheet(onClose: { showAISheet = false })
            }
        }

        .task { await refresh() }
        .refreshable { await refresh() }
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
                    QuickActionCard(title: "Activity",
                                    systemImage: "bell.badge.fill",
                                    colors: [.purple, .pink])
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
                ForEach(recentActivity, id: \.id) { a in
                    if let id = a.invoice_id {
                        NavigationLink(value: id) {
                            activityRow(a)
                        }
                        .buttonStyle(.plain)
                    } else {
                        activityRow(a)
                    }
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func activityRow(_ a: ActivityJoined) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: a.event))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle(a)).font(.subheadline)
                Text(relativeTime(a.created_at))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
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
                self.errorText = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Helpers

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
    var onClose: (() -> Void)? = nil
    var onOpenFullInvoices: (() -> Void)? = nil

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
        List {
            // Header controls
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    // Quick filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases, id: \.self) { f in
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
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                }
                .listRowInsets(.init(top: 8, leading: 16, bottom: 4, trailing: 16))
            }

            // Invoices
            Section {
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").font(.title2)
                        Text(emptyCopy)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                } else {
                    ForEach(filtered) { inv in
                        NavigationLink(value: inv.id) {
                            InvoiceCardRow(inv: inv)
                        }
                        // trailing swipe: Send
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                // TODO: integrate send flow
                                // await InvoiceService.sendInvoice(id: inv.id)
                            } label: { Label("Send", systemImage: "paperplane") }
                            .tint(.blue)
                        }
                        // leading swipe: Mark Paid
                        .swipeActions(edge: .leading) {
                            Button {
                                // TODO: integrate mark paid
                                // await InvoiceService.markPaid(id: inv.id)
                            } label: { Label("Mark Paid", systemImage: "checkmark.seal") }
                            .tint(.green)
                        }
                    }
                }
            }

            // FooterR
            Section {
                Button {
                    onOpenFullInvoices?()   // dismiss sheet + switch tab
                } label: {
                    Label("Open full invoices list", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Recent Invoices")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onClose?() }
            }
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
        List {
            // Header controls
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    // Filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases, id: \.self) { f in
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
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                }
                .listRowInsets(.init(top: 8, leading: 16, bottom: 4, trailing: 16))
            }

            // Grouped by day sections
            let groups = groupByDay(filtered)
            let keys = groupedDayKeys(from: groups)

            if filtered.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "bell.slash").font(.title2)
                        Text(search.isEmpty ? "No activity for this filter yet" : "No results for “\(search)”")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                }
            } else {
                ForEach(keys, id: \.self) { dayKey in
                    Section(header: Text(dayHeader(from: dayKey))) {
                        let rows = groups[dayKey] ?? []
                        ForEach(rows) { a in
                            // If we have an invoice ID, allow drill-in via value navigation
                            Group {
                                if let id = a.invoice_id {
                                    NavigationLink(value: id) { ActivityCardRow(a: a) }
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
                }
            }

            // Footer
            Section {
                Button {
                    onOpenFullActivity?()   // dismiss sheet + switch tab
                } label: {
                    Label("Open full activity feed", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Recent Activity")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onClose?() }
            }
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
    private func recalcAndBroadcastUnread() async {
        let n = (try? await ActivityService.countUnread()) ?? 0
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
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconGradient)
                Image(systemName: iconFor(a.event))
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleFor(a))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(relativeTime(a.created_at))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Tiny status chip when event implies a state
            if let chip = statusChipText(a.event) {
                StatusPillTiny(text: chip)
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
    }

    private var iconGradient: LinearGradient {
        let colors: [Color]
        switch a.event {
        case "created":  colors = [.blue, .indigo]
        case "sent":     colors = [.teal, .blue]
        case "opened":   colors = [.purple, .pink]
        case "paid":     colors = [.green, .teal]
        case "due_soon": colors = [.orange, .pink]
        case "overdue":  colors = [.red, .orange]
        default:         colors = [.gray, .gray.opacity(0.7)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func titleFor(_ a: ActivityJoined) -> String {
        let number = a.invoiceNumber
        let client = a.clientName
        let action: String = {
            switch a.event {
            case "created":  return "Created"
            case "sent":     return "Sent"
            case "opened":   return "Opened"
            case "paid":     return "Paid"
            case "overdue":  return "Overdue"
            case "due_soon": return "Due Soon"
            default:         return a.event.capitalized
            }
        }()
        let left = number.isEmpty || number == "—" ? "Invoice" : "Invoice \(number)"
        return client == "—" ? "\(left) — \(action)" : "\(left) — \(action) (\(client))"
    }

    private func iconFor(_ event: String) -> String {
        switch event {
        case "created":  return "doc.badge.plus"
        case "opened":   return "eye"
        case "sent":     return "paperplane"
        case "paid":     return "checkmark.seal"
        case "overdue":  return "exclamationmark.triangle"
        case "due_soon": return "clock.badge.exclamationmark"
        default:         return "bell"
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

    private func statusChipText(_ event: String) -> String? {
        switch event {
        case "paid": return "Paid"
        case "overdue": return "Overdue"
        case "sent": return "Sent"
        default: return nil
        }
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
        return m
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
//-----

// Mobius-like morphing loop shape
private struct WobbleLoop: Shape {
    // progress: 0...1, 0=base, 1=fully morphed
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = w/2
        let cy = h/2
        let loops = 1.0
        let points = 120
        let baseR = min(w, h) * 0.42
        let amplitude = baseR * (0.22 + 0.08 * progress)
        let twist = .pi * (1 + progress)
        let phase = progress * .pi
        var path = Path()
        for i in 0...points {
            let t = Double(i) / Double(points)
            let angle = t * 2 * .pi * loops
            let r = baseR + amplitude * CGFloat(sin(angle * 2 + Double(phase)))
            let x = cx + r * cos(CGFloat(angle + Double(twist) * CGFloat(t)))
            let y = cy + r * sin(CGFloat(angle + Double(twist) * CGFloat(t)))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

// Animated Mobius strip badge for AI
// MARK: - Möbius badge (animated twisted ribbon)
private struct AIMobiusBadge: View {
    var size: CGFloat = 36
    @State private var rot: Double = 0
    @State private var breathe: Bool = false

    private var loopWidth: CGFloat { size * 1.28 }
    private var loopHeight: CGFloat { size * 0.80 }
    private var lineWidth: CGFloat { max(1.8, size * 0.10) }

    var body: some View {
        ZStack {
            // Soft glow behind the ribbon
            MobiusStrip()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.28),
                            Color.indigo.opacity(0.18),
                            Color.purple.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: lineWidth * 1.9
                )
                .blur(radius: 4)
                .opacity(0.9)

            // Twisted ribbon stroke (the Möbius look)
            MobiusStrip()
                .stroke(
                    LinearGradient(
                        colors: [.cyan, .blue, .indigo, .purple, .pink, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .overlay {
                    // subtle highlight band to sell the twist
                    MobiusStrip()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.00),
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.00)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: lineWidth * 0.45
                        )
                        .blendMode(.screen)
                        .opacity(breathe ? 0.85 : 0.55)
                        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                                   value: breathe)
                }

            // A small traveling “specular” segment for life
            MobiusStrip()
                .trim(from: 0.84, to: 0.98)
                .stroke(
                    LinearGradient(colors: [.white, .clear],
                                   startPoint: .leading,
                                   endPoint: .trailing),
                    style: StrokeStyle(lineWidth: lineWidth * 1.1, lineCap: .round)
                )
                .blur(radius: 0.4)
        }
        .frame(width: loopWidth, height: loopHeight)
        .rotationEffect(.degrees(rot))
        .shadow(color: .cyan.opacity(0.22), radius: 8)
        .onAppear {
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                rot = 360
            }
            breathe = true
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Möbius-like path
/// A 2D twisted loop that suggests a Möbius strip by modulating an ellipse
/// radius with a sin(2θ) term (gives the “half-twist” feel).
private struct MobiusStrip: Shape {
    var wobble: CGFloat = 0.18   // twist amplitude

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.5, cy = h * 0.5
        let a = min(w, h) * 0.45        // base x radius
        let b = a * 0.65                // base y radius
        let steps = 240

        var path = Path()
        var first = true

        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2.0 * Double.pi
            // sin(2t) modulates the radius → visually reads like a half-twist
            let twist = wobble * CGFloat(sin(2.0 * t))
            let x = cx + (a + a * twist) * CGFloat(cos(t))
            let y = cy + (b - b * twist) * CGFloat(sin(t))
            if first {
                path.move(to: CGPoint(x: x, y: y))
                first = false
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Solid Möbius badge (sculptural look)
private struct AIMobiusSolidBadge: View {
    var size: CGFloat = 36
    @State private var spin: Double = 0
    @State private var shimmer: CGFloat = 0

    private var frame: CGSize { .init(width: size * 1.35, height: size * 0.92) }

    var body: some View {
        ZStack {
            // Soft ambient glow behind
            MobiusStrip(wobble: 0.20)
                .stroke(
                    LinearGradient(
                        colors: [Color.orange, Color.pink, Color.purple, Color.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(2.0, size * 0.16)
                )
                .blur(radius: 3.0)
                .opacity(0.9)

            // Filled ribbon (gives the sculptural “solid” look)
            MobiusStrip(wobble: 0.20)
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .cyan, .blue, .indigo, .purple, .pink, .cyan
                        ]),
                        center: .center
                    )
                )
                .overlay(
                    // Edge highlight that moves slowly (subtle shimmer)
                    MobiusStrip(wobble: 0.20)
                        .trim(from: shimmer, to: min(shimmer + 0.18, 1))
                        .stroke(
                            LinearGradient(colors: [.white.opacity(0.75), .clear],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: max(1.4, size * 0.10), lineCap: .round)
                        )
                        .shadow(color: .white.opacity(0.25), radius: 1.2)
                        .mask(
                            MobiusStrip(wobble: 0.20)
                                .stroke(style: StrokeStyle(lineWidth: max(1.4, size * 0.10)))
                        )
                )
                .overlay(
                    // Inner shadow to enhance depth
                    MobiusStrip(wobble: 0.20)
                        .stroke(Color.black.opacity(0.20), lineWidth: max(0.8, size * 0.06))
                        .blur(radius: 0.5)
                        .blendMode(.multiply)
                        .opacity(0.7)
                )
        }
        .frame(width: frame.width, height: frame.height)
        .rotationEffect(.degrees(spin))
        .shadow(color: .cyan.opacity(0.20), radius: 6, y: 1)
        .onAppear {
            withAnimation(.linear(duration: 6.5).repeatForever(autoreverses: false)) {
                spin = 360
            }
            withAnimation(.linear(duration: 3.8).repeatForever(autoreverses: false)) {
                shimmer = 1
            }
        }
        .accessibilityHidden(true)
    }
}

// ===== Apple‑style animated infinity ribbon (lemniscate) =====
private struct InfinityRibbonShape: Shape {
    // 0...1 phase for animating highlight position
    var phase: CGFloat = 0
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let a = min(w, h) * 0.42
        let cx = w/2, cy = h/2
        let steps = 360
        var p = Path()
        var first = true
        // Parametric lemniscate (Gerono): x = a * sin(t), y = a * sin(t) * cos(t)
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2.0 * Double.pi
            let x = cx + a * CGFloat(sin(t))
            let y = cy + a * CGFloat(sin(t) * cos(t))
            if first { p.move(to: CGPoint(x: x, y: y)); first = false } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

private struct AIInfinityBadge: View {
    var size: CGFloat = 36
    @State private var phase: CGFloat = 0
    @State private var wobble: CGFloat = 0
    private var lineWidth: CGFloat { max(2.0, size * 0.10) }
    private var frame: CGSize { .init(width: size * 1.6, height: size * 1.05) }

    private var wobbleSin: CGFloat {
        CGFloat(sin(Double(wobble) * 2.0 * .pi))
    }

    var body: some View {
        ZStack {
            // soft outer glow
            InfinityRibbonShape()
                .stroke(LinearGradient(colors: [Color.cyan.opacity(0.25), Color.purple.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: lineWidth*1.7)
                .blur(radius: 3)
                .opacity(0.9)

            // main colorful ribbon stroke
            InfinityRibbonShape()
                .stroke(LinearGradient(colors: [.cyan, .blue, .indigo, .purple, .pink, .cyan], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .overlay(
                    // subtle inner highlight band
                    InfinityRibbonShape()
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.45), .clear, Color.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing), lineWidth: lineWidth*0.45)
                        .blendMode(.screen)
                        .opacity(0.65)
                )

            // traveling specular highlight (wrap-safe)
            Group {
                InfinityRibbonShape(phase: phase)
                    .trim(from: phase, to: min(phase + 0.12, 1))
                    .stroke(LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: lineWidth*1.1, lineCap: .round))
                if phase + 0.12 > 1 {
                    InfinityRibbonShape(phase: phase)
                        .trim(from: 0, to: (phase + 0.12).truncatingRemainder(dividingBy: 1))
                        .stroke(LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: lineWidth*1.1, lineCap: .round))
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .rotation3DEffect(
            .degrees(16.0 * Double(wobbleSin)),
            axis: (x: 0, y: 1, z: 0),
            anchor: .trailing,
            perspective: 0.9
        )
        .scaleEffect(
            x: 1.0 + 0.14 * wobbleSin,
            y: 1.0 - 0.10 * wobbleSin,
            anchor: .trailing
        )
        .offset(x: (size * 0.14) * wobbleSin)
        .rotationEffect(.degrees(4 * wobbleSin))
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                phase = 1
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                wobble = 1
            }
        }
        .accessibilityHidden(true)
    }
}
// MARK: - Coming Soon Sheet for AI Assistant
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

                Text("Soon, you’ll be able to integrate your smart glasses to take pictures & videos, record audible notes with translation for your assistant to auto‑generate the estimate or invoices for at your convenience.")
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

private struct ThemedNewInvoiceSheet: View {
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
                // Background glow that matches the tile
                gradient.opacity(0.20)
                    .ignoresSafeArea()

                // Content card
                VStack(spacing: 0) {
                    // Grabber + title area
                    VStack(spacing: 10) {
                        Capsule()
                            .fill(.secondary.opacity(0.35))
                            .frame(width: 36, height: 5)
                            .padding(.top, 8)

                        HStack {
                            Label("New Invoice", systemImage: "plus.circle.fill")
                                .font(.headline.bold())
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                onClose?()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .background(.ultraThinMaterial)

                    // Your invoice form
                    NewInvoiceView(onSaved: onSaved)
                        .scrollContentBackground(.hidden) // Form blends into our bg
                        .background(Color.clear)
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
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
        }
    }
}
