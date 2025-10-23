//
//  HomeView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/22/25.
//

import SwiftUI

struct HomeView: View {
    // Ask parent to switch tabs (0=Home, 1=Invoices, 2=Clients, 3=Activity, 4=Account)
    var onSelectTab: ((Int) -> Void)? = nil

    @State private var stats: InvoiceService.AccountStats?
    @State private var recentInvoices: [InvoiceRow] = []
    @State private var recentActivity: [ActivityJoined] = []
    @State private var isLoading = false
    @State private var errorText: String?

    @State private var showNewInvoice = false

    var body: some View {
        // NOTE: MainTabView already wraps HomeView in a NavigationStack,
        // so we DON'T add another NavigationStack here.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // --- Summary cards ---
                summaryCards

                // --- Quick actions (switch tabs) ---
                quickActions

                // --- Recent invoices ---
                Group {
                    HStack {
                        Text("Recent Invoices").font(.headline)
                        Spacer()
                        Button("View All") { onSelectTab?(1) } // -> Invoices tab
                            .font(.subheadline)
                    }
                    .padding(.horizontal)

                    invoicesList
                }

                // --- Activity preview ---
                Group {
                    HStack {
                        Text("Activity").font(.headline)
                        Spacer()
                        Button("Open Feed") { onSelectTab?(3) } // -> Activity tab
                            .font(.subheadline)
                    }
                    .padding(.horizontal)

                    activityList
                }

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
        .sheet(isPresented: $showNewInvoice) {
            // Keep a stack inside the sheet so NewInvoiceView shows its toolbar
            NavigationStack {
                NewInvoiceView { draft in
                    Task {
                        do {
                            _ = try await InvoiceService.createInvoice(from: draft)
                            await refresh()
                            await MainActor.run { showNewInvoice = false } // dismiss
                        } catch {
                            await MainActor.run { errorText = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: - Sections

    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(
                title: "Total Invoices",
                value: stats.map { "\($0.totalCount)" } ?? "—",
                icon: "doc.on.doc"
            )
            SummaryCard(
                title: "Paid",
                value: stats.map { "\($0.paidCount)" } ?? "—",
                icon: "checkmark.seal"
            )
            SummaryCard(
                title: "Outstanding",
                value: stats.map { currency($0.outstandingAmount) } ?? "—",
                icon: "clock.badge"
            )
        }
        .padding(.horizontal)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions").font(.headline).padding(.horizontal)

            HStack(spacing: 12) {
                // New invoice
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showNewInvoice = true
                } label: {
                    QuickActionCard(title: "New", systemImage: "plus.circle.fill", colors: [.blue, .indigo])
                }
                .buttonStyle(.plain)

                // Invoices -> switch tab
                Button {
                    onSelectTab?(1)
                } label: {
                    QuickActionCard(title: "Invoices", systemImage: "doc.plaintext.fill", colors: [.green, .teal])
                }
                .buttonStyle(.plain)

                // Activity -> switch tab
                Button {
                    onSelectTab?(3)
                } label: {
                    QuickActionCard(title: "Activity", systemImage: "bell.badge.fill", colors: [.purple, .pink])
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    private struct QuickActionCard: View {
        let title: String
        let systemImage: String
        let colors: [Color]

        var body: some View {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12))
            )
        }
    }

    private var invoicesList: some View {
        LazyVStack(spacing: 0) {
            if recentInvoices.isEmpty && !isLoading {
                Text("No recent invoices").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                ForEach(recentInvoices, id: \.id) { row in
                    // ✅ Value-based navigation; handled by MainTabView's destination
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

    private var activityList: some View {
        VStack(spacing: 0) {
            if recentActivity.isEmpty && !isLoading {
                Text("No recent activity").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                ForEach(recentActivity, id: \.id) { a in
                    if let id = a.invoice_id {
                        NavigationLink(value: id) {
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
                        .buttonStyle(.plain)
                    } else {
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

                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Helpers

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

    private func currency(_ value: Double, code: String? = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = (code ?? "USD").uppercased()
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func relativeTime(_ iso: String) -> String {
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

// MARK: - Small components

private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                Spacer()
                Text(value).font(.title3).bold()
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
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
