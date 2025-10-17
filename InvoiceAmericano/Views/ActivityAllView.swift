//
//  ActivityAllView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import Foundation
import SwiftUI

struct ActivityAllView: View {
    @Binding var unreadCount: Int
    @State private var events: [ActivityRow] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading { ProgressView("Loading activity…") }
            else if let e = error { Text(e).foregroundStyle(.red) }
            else if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus").font(.largeTitle)
                    Text("No activity yet").foregroundStyle(.secondary)
                }.padding(.top, 40)
            } else {
                List {
                    ForEach(events) { ev in
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: ev.event)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: ev)).font(.subheadline).bold()
                                Text(relTime(ev.created_at)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteRows)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Activity")
        .task { await loadAndMarkRead() }
    }

    private func loadAndMarkRead() async {
        loading = true; error = nil
        do {
            // First mark all as read on the server
            try await ActivityService.markAllAsRead()
            // Then fetch the latest list
            let evs = try await ActivityService.fetchAll()
            await MainActor.run {
                self.events = evs
                self.unreadCount = 0   // we just marked them all as read
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }

    // MARK: - Helpers
    private func icon(for event: String) -> String {
        switch event {
        case "created": return "doc.badge.plus"
        case "opened": return "eye"
        case "sent": return "paperplane"
        case "paid": return "checkmark.seal"
        case "archived": return "archivebox"
        case "deleted": return "trash"
        case "status_changed": return "arrow.triangle.2.circlepath"
        default: return "clock"
        }
    }

    private func title(for ev: ActivityRow) -> String {
        switch ev.event {
        case "created": return "Invoice created"
        case "opened": return "Invoice opened"
        case "sent": return "Invoice sent"
        case "paid": return "Invoice paid"
        case "archived": return "Invoice archived"
        case "deleted": return "Invoice deleted"
        case "status_changed": return "Status changed"
        default: return ev.event.capitalized
        }
    }

    private func relTime(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? Date()
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .short
        return r.localizedString(for: date, relativeTo: Date())
    }
    private func deleteRows(at offsets: IndexSet) {
        let toDelete = offsets.map { events[$0] }
        // Optimistic UI update
        events.remove(atOffsets: offsets)
        // Soft-delete on the server
        Task {
            for ev in toDelete {
                try? await ActivityService.delete(id: ev.id)
            }
        }
    }
}

#if DEBUG
struct ActivityAllView_Previews: PreviewProvider {
    @State static var count = 3
    static var previews: some View {
        NavigationStack {
            ActivityAllView(unreadCount: $count)
        }
    }
}
#endif
