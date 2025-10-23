//
//  HomeView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/22/25.
//

import SwiftUI

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
            NavigationStack {
                NewInvoiceView { draft in
                    Task {
                        do {
                            _ = try await InvoiceService.createInvoice(from: draft)
                            await refresh()
                            await MainActor.run { showNewInvoice = false }
                        } catch {
                            await MainActor.run { errorText = error.localizedDescription }
                        }
                    }
                }
            }
        }

        // Recent Invoices sheet
        .sheet(isPresented: $showInvoicesSheet) {
            NavigationStack {
                RecentInvoicesSheet(
                    recentInvoices: recentInvoices,
                    onClose: { showInvoicesSheet = false }
                )
                // allow pushing by UUID from this sheet
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
                    onClose: { showActivitySheet = false }
                )
                // allow pushing by UUID from this sheet
                .navigationDestination(for: UUID.self) { invoiceId in
                    InvoiceDetailView(invoiceId: invoiceId)
                }
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
            }
            .padding(.horizontal)
        }
    }

    private var invoicesList: some View {
        LazyVStack(spacing: 0) {
            if recentInvoices.isEmpty && !isLoading {
                Text("No recent invoices").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                ForEach(recentInvoices, id: \.id) { row in
                    // Value-based link -> handled by MainTabView’s NavigationStack destination for UUID
                    NavigationLink(value: row.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.number)
                                    .font(.subheadline).bold()
                                Text(row.client?.name ?? "—")
                                    .font(.footnote).foregroundStyle(.secondary)
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
                    // If we have invoice_id, allow drill-in by UUID; otherwise show static row
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

// ===== Sheets =====

private struct RecentInvoicesSheet: View {
    let recentInvoices: [InvoiceRow]
    var onClose: (() -> Void)? = nil

    var body: some View {
        List {
            Section {
                if recentInvoices.isEmpty {
                    Text("No recent invoices")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentInvoices) { inv in
                        NavigationLink(value: inv.id) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(inv.number).font(.subheadline).bold()
                                    Text(inv.client?.name ?? "—")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(currency(inv.total))
                                        .font(.subheadline)
                                    StatusChip(status: displayStatus(inv))
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    InvoiceListView()
                } label: {
                    Label("View all invoices", systemImage: "list.bullet.rectangle")
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

    // local helpers so this view is self-contained
    private func currency(_ total: Double?) -> String {
        let n = NumberFormatter()
        n.numberStyle = .currency
        n.currencyCode = "USD"
        return n.string(from: NSNumber(value: total ?? 0)) ?? "$0.00"
    }
    private func displayStatus(_ inv: InvoiceRow) -> String {
        if inv.status == "open", inv.sent_at != nil { return "sent" }
        return inv.status
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

private struct RecentActivitySheet: View {
    let recentActivity: [ActivityJoined]
    var onClose: (() -> Void)? = nil
    
    var body: some View {
        List {
            Section {
                if recentActivity.isEmpty {
                    Text("No recent activity")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentActivity) { a in
                        if let id = a.invoice_id {
                            NavigationLink(value: id) {
                                row(a)
                            }
                        } else {
                            row(a)
                        }
                    }
                }
            }
            
            Section {
                NavigationLink {
                    ActivityAllView()
                } label: {
                    Label("Open full feed", systemImage: "list.bullet.rectangle")
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
    
    // MARK: - Row + helpers
    
    @ViewBuilder
    private func row(_ a: ActivityJoined) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconFor(a.event))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleFor(a)).font(.subheadline)
                Text(relativeTime(a.created_at))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
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
            case "archived": return "Archived"
            case "deleted":  return "Deleted"
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
        case "archived": return "archivebox"
        case "deleted":  return "trash"
        case "overdue":  return "exclamationmark.triangle"
        case "due_soon": return "clock.badge.exclamationmark"
        default:         return "bell"
        }
    }
    // Inside RecentActivitySheet
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
}
