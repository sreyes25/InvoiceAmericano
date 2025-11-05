//
//  ActivityAllView.swift
//  InvoiceAmericano
//

//
//  ActivityAllView.swift
//  InvoiceAmericano
//

import SwiftUI

struct ActivityAllView: View {
    @State private var items: [ActivityJoined] = []
    @State private var loading = false
    @State private var loadingMore = false
    @State private var reachedEnd = false
    @State private var error: String?

    // Page size for “More” button
    private let pageSize = 20

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView("Loading…")
            } else if let e = error {
                VStack(spacing: 8) {
                    Text("Error").font(.headline)
                    Text(e).foregroundStyle(.red)
                    Button("Retry") { Task { await initialLoad() } }
                }
                .padding(.top, 24)
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.badge").font(.largeTitle)
                    Text("No activity yet").foregroundStyle(.secondary)
                }
                .padding(.top, 24)
            } else {
                List {
                    // Precompute groups & keys to keep expressions simple for the compiler
                    let groups = groupByDay(items)
                    let keys = groupedDayKeys(from: groups)

                    // Grouped-by-day sections
                    ForEach(keys, id: \.self) { dayKey in
                        Section(header: Text(dayHeader(from: dayKey))) {
                            let sectionItems = groups[dayKey] ?? []
                            ForEach(sectionItems) { row in
                                if let id = row.invoice_id {
                                    NavigationLink(value: id) {
                                        activityRowCell(row)
                                    }
                                } else {
                                    activityRowCell(row)
                                }
                            }
                            .onDelete { offsets in
                                deleteRowsInSection(dayKey: dayKey, offsets: offsets)
                            }
                        }
                    }

                    // Footer: Load more / spinner
                    if !reachedEnd {
                        Section {
                            HStack {
                                Spacer()
                                if loadingMore {
                                    ProgressView()
                                } else {
                                    Button("More") { Task { await loadMore() } }
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Activity")
        // MARK: Mark visible rows as read (server + optimistic), then notify Home
        .task {
            await load()
            

            // Find unread rows currently shown
            let unreadIndexes = items.enumerated().compactMap { idx, ev in
                ev.read_at == nil ? idx : nil
            }
            let unreadIDs = unreadIndexes.map { items[$0].id }

            // Kick off server update
            Task { await ActivityService.markAsRead(unreadIDs) }
            
            // Optimistically flip local state so blue dots disappear now
            let now = ISO8601DateFormatter().string(from: Date())
            for i in unreadIndexes {
                items[i].read_at = now
            }
            // After optimistic local clear + server mark:
            Task { await recalcAndBroadcastUnread() }

            // Ask Home to recompute badge (it will pull fresh count)
            NotificationCenter.default.post(name: .activityUnreadChanged, object: nil)
        }
        .navigationDestination(for: UUID.self) { invoiceId in
            InvoiceDetailView(invoiceId: invoiceId)
        }
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

    // MARK: - Loading

    // Thin wrapper so the .task snippet can call `load()`
    private func load() async {
        await initialLoad()
    }

    private func initialLoad() async {
        loading = true; error = nil; reachedEnd = false
        do {
            let page = try await ActivityService.fetchPageJoined(offset: 0, limit: pageSize)
            await MainActor.run {
                self.items = page
                self.loading = false
                self.reachedEnd = page.count < pageSize
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }

    private func loadMore() async {
        guard !loadingMore, !reachedEnd else { return }
        loadingMore = true
        do {
            let page = try await ActivityService.fetchPageJoined(offset: items.count, limit: pageSize)
            await MainActor.run {
                self.items.append(contentsOf: page)
                self.loadingMore = false
                if page.count < pageSize { self.reachedEnd = true }
            }
        } catch {
            await MainActor.run {
                self.loadingMore = false
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Deletion (section-aware)

    private func deleteRowsInSection(dayKey: String, offsets: IndexSet) {
        // Map section offsets to global item IDs
        let sectionItems = groupByDay(items)[dayKey] ?? []
        let idsToDelete = offsets.map { sectionItems[$0].id }

        // Remove from overall list
        items.removeAll { idsToDelete.contains($0.id) }

        // Delete on server & recount
        Task {
            for id in idsToDelete {
                try? await ActivityService.delete(id: id)
            }
            // Let Home recompute its badge (it will refetch count)
            NotificationCenter.default.post(name: .activityUnreadChanged, object: nil)
        }
    }

    // MARK: - Row title / icon

    private func title(for row: ActivityJoined) -> String {
        let number = row.invoiceNumber
        let client = row.clientName

        let label: String = {
            if !number.isEmpty && number != "—" { return "Invoice \(number)" }
            return "Invoice " + row.id.uuidString.prefix(8)
        }()

        let action: String
        switch row.event {
        case "created":  action = "created"
        case "sent":     action = "sent"
        case "opened":   action = "opened"
        case "paid":     action = "paid"
        case "archived": action = "archived"
        case "deleted":  action = "deleted"
        case "overdue":  action = "overdue"
        case "due_soon": action = "due soon"
        default:         action = row.event
        }

        if !client.isEmpty && client != "—" {
            return "\(label) — \(action.capitalized) (\(client))"
        } else {
            return "\(label) — \(action.capitalized)"
        }
    }

    private func icon(for event: String) -> String {
        switch event {
        case "created":  return "doc.badge.plus"
        case "opened":   return "eye"
        case "sent":     return "paperplane"
        case "paid":     return "checkmark.seal"
        case "archived": return "archivebox"
        case "deleted":  return "trash"
        case "overdue":  return "exclamationmark.triangle"
        case "due_soon": return "clock.badge.exclamationmark"
        default:         return "clock"
        }
    }

    // New activity row layout: Left = client name + invoice number, Right = event badge + relative time
    @ViewBuilder
    private func activityRowCell(_ row: ActivityJoined) -> some View {
        HStack(spacing: 12) {
            // Left icon (unchanged)
            ZstackIcon(row.event)

            // LEFT: Client name + invoice number
            VStack(alignment: .leading, spacing: 4) {
                Text(row.clientName.isEmpty || row.clientName == "—" ? "Client" : row.clientName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(row.invoiceNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // RIGHT: Event type badge + relative time
            VStack(alignment: .trailing, spacing: 6) {
                Text(eventLabel(for: row.event))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(eventColor(for: row.event).opacity(0.15))
                    )
                    .foregroundStyle(eventColor(for: row.event))

                Text(relativeTime(row.created_at))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Unread indicator dot
            if row.isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Event helpers (badge label & color)
    private func eventLabel(for event: String) -> String {
        switch event {
        case "created":  return "Created"
        case "sent":     return "Sent"
        case "opened":   return "Opened"
        case "paid":     return "Paid"
        case "archived": return "Archived"
        case "deleted":  return "Deleted"
        case "overdue":  return "Overdue"
        case "due_soon": return "Due Soon"
        default:           return event.capitalized
        }
    }

    private func eventColor(for event: String) -> Color {
        switch event {
        case "created":  return .blue
        case "sent":     return .purple
        case "opened":   return .teal
        case "paid":     return .green
        case "archived": return .gray
        case "deleted":  return .red
        case "overdue":  return .orange
        case "due_soon": return .yellow
        default:           return .secondary
        }
    }

    @ViewBuilder
    private func ZstackIcon(_ event: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.indigo.opacity(0.2), .blue.opacity(0.2)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
            Image(systemName: icon(for: event))
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Time helpers

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

    // MARK: - Day grouping

    private func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func groupByDay(_ items: [ActivityJoined]) -> [String: [ActivityJoined]] {
        Dictionary(grouping: items) { row in
            dayKey(for: isoDate(from: row.created_at))
        }
    }

    private func groupedDayKeys(from groups: [String: [ActivityJoined]]) -> [String] {
        groups.keys.sorted(by: >)
    }

    private func groupedDayKeys(_ items: [ActivityJoined]) -> [String] {
        groupedDayKeys(from: groupByDay(items))
    }

    private func dayHeader(from key: String) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
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
}
