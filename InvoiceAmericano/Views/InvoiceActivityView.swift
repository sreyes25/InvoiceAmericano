//
//  InvoiceActivityView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import Foundation
import SwiftUI

struct InvoiceActivityView: View {
    let invoiceId: UUID
    @State private var events: [ActivityEvent] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading { ProgressView("Loading activity…") }
            else if let e = error { Text(e).foregroundStyle(.red) }
            else if events.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.badge.plus")
                        .font(.largeTitle)
                    Text("No activity yet").foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            } else {
                List {
                    ForEach(events) { ev in
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: ev.event))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: ev))
                                    .font(.subheadline).bold()
                                Text(relTime(ev.created_at))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { await load() }            // load + mark-as-read + notify
        .navigationTitle("Activity")
    }

    // MARK: - Data

    private func load() async {
        loading = true
        error = nil
        do {
            let evs = try await ActivityService.fetch(invoiceId: invoiceId)
            await MainActor.run {
                self.events = evs
                self.loading = false
            }

            // NOTE: ActivityEvent doesn't expose `read_at`, so mark all loaded
            // rows as read for this invoice. If you later add `read_at` to the
            // model, filter to only unread IDs here.
            let unreadIds = evs.map { $0.id }
            if !unreadIds.isEmpty {
                await ActivityService.markActivitiesRead(ids: unreadIds)

                // Ask Home to recompute the red badge (it will refetch count)
                await MainActor.run {
                    NotificationCenter.default.post(name: .activityUnreadChanged, object: nil)
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }

    // MARK: - UI helpers

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

    private func title(for ev: ActivityEvent) -> String {
        switch ev.event {
        case "created":  return "Invoice created"
        case "opened":   return "Invoice opened"
        case "sent":     return "Invoice sent"
        case "paid":     return "Invoice paid"
        case "archived": return "Invoice archived"
        case "deleted":  return "Invoice deleted"
        default:         return ev.event.capitalized
        }
    }

    private func relTime(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: s) ?? Date()
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .short
        return r.localizedString(for: date, relativeTo: Date())
    }
}
