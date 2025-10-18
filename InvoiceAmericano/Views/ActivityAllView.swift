//
//  ActivityAllView.swift
//  InvoiceAmericano
//

import SwiftUI

struct ActivityAllView: View {
    @State private var items: [ActivityEvent] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView("Loading…")
            } else if let e = error {
                VStack(spacing: 8) {
                    Text("Error").font(.headline)
                    Text(e).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                }
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.badge").font(.largeTitle)
                    Text("No activity yet").foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(items) { row in
                        NavigationLink(value: row.invoice_id) {
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: row.event))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title(for: row))
                                        .font(.subheadline).bold()
                                    Text(relativeTime(row.created_at))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Activity")
        .task { await load() }
    }

    // MARK: - Data

    private func load() async {
        loading = true; error = nil
        do {
            // Optional: mark-as-read when opening the tab view
            try? await ActivityService.markAllAsRead()
            let evs = try await ActivityService.fetchAll(limit: 200)
            await MainActor.run {
                items = evs
                loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }

    // MARK: - Helpers

    private func title(for row: ActivityEvent) -> String {
        // Simple readable title like: "Invoice – paid"
        "\(displayName(for: row)) – \(row.event.capitalized)"
    }

    private func displayName(for _: ActivityEvent) -> String {
        // If you later join invoice number/title, swap this out.
        "Invoice"
    }

    private func icon(for event: String) -> String {
        switch event {
        case "created":  return "doc.badge.plus"
        case "opened":   return "eye"
        case "sent":     return "paperplane"
        case "paid":     return "checkmark.seal"
        case "archived": return "archivebox"
        case "deleted":  return "trash"
        default:         return "clock"
        }
    }

    private func relativeTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .short
        return r.localizedString(for: date ?? Date(), relativeTo: Date())
    }
}
