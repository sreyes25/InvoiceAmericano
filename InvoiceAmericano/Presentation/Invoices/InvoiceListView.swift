//
//  InvoiceListView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/6/25.
//

import SwiftUI
import UIKit

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct InvoiceListView: View {
    @State private var status: InvoiceStatus = .all
    @State private var showNew = false
    @State private var invoices: [InvoiceRow] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var isSendingId: UUID? = nil
    @State private var sharePayload: SharePayload? = nil
    @State private var pushInvoiceId: UUID? = nil
    @State private var search: String = ""

    // MARK: - Sections

    private var filteredInvoices: [InvoiceRow] {
        guard !search.isEmpty else { return invoices }
        let q = search.lowercased()
        return invoices.filter { inv in
            let number = inv.number.lowercased()
            let client = (inv.client?.name ?? "").lowercased()
            return number.contains(q) || client.contains(q)
        }
    }

    @ViewBuilder
    private var statusPickerSection: some View {
        Section {
            Picker("Status", selection: $status) {
                ForEach(InvoiceStatus.allCases, id: \.self) { s in
                    Text(s == .all ? "All" : s.rawValue.capitalized).tag(s)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var invoicesSection: some View {
        Section("Invoices") {
            if isLoading && invoices.isEmpty {
                ProgressView("Loading…")
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else if filteredInvoices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass").font(.title2)
                    Text(search.isEmpty ? "No invoices" : "No results for \"\(search)\"")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            } else {
                ForEach(filteredInvoices) { inv in
                    Button {
                        pushInvoiceId = inv.id
                    } label: {
                        InvoiceRowCell(inv: inv)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            isSendingId = inv.id
                            Task { await send(inv) }
                        } label: {
                            Label("Send", systemImage: "paperplane")
                        }
                        .tint(.blue)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search invoices or clients", text: $search)
                            .textInputAutocapitalization(.words)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .listRowBackground(Color.clear)
                statusPickerSection
                invoicesSection
            }
            .navigationTitle("Invoices")
            .toolbar { addButton }
            .navigationDestination(item: $pushInvoiceId) { invoiceId in
                InvoiceDetailView(invoiceId: invoiceId)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showNew, content: {
                newInvoiceSheet
            })
            .sheet(item: $sharePayload, content: { payload in
                ActivitySheet(items: payload.items, onComplete: onShareCompleted)
            })
            .task { await load() }
            .onChange(of: status) { _, _ in
                Task { await load() }
            }
            .refreshable { await load() }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .scrollIndicators(.hidden)
            .animation(.easeInOut, value: search)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showNew = true } label: { Image(systemName: "plus") }
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private var newInvoiceSheet: some View {
        NavigationStack {
            NewInvoiceView(onSaved: { draft in
                Task { await createInvoice(from: draft) }
            })
        }
    }

    // MARK: - Actions

    private func createInvoice(from draft: InvoiceDraft) async {
        do {
            // 1) Create the invoice and get the new row
            let created = try await InvoiceService.createInvoice(from: draft)
            AnalyticsService.track(.invoiceCreated, metadata: ["source": "invoices_tab"])

            // 2) Refresh the list so the new invoice shows up
            await load()

            // 3) On the main thread, close the sheet + jump to detail
            await MainActor.run {
                // this controls the New Invoice sheet
                self.showNew = false

                // this triggers your existing navigationDestination:
                // .navigationDestination(item: $pushInvoiceId) { InvoiceDetailView(invoiceId: $0) }
                self.pushInvoiceId = created.id
            }

            // 4) If we already have a pay link, surface it immediately for sharing
            if let payURL = created.checkoutURL {
                await MainActor.run { self.sharePayload = nil }
                try? await Task.sleep(nanoseconds: 250_000_000) // brief pause for sheet dismissal animation
                await MainActor.run {
                    self.sharePayload = SharePayload(items: ["Pay this invoice", payURL])
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.friendlyMessage
            }
        }
    }

    private func onShareCompleted(_ completed: Bool, _ activityType: UIActivity.ActivityType?) {
        Task {
            guard completed, let id = isSendingId else {
                await MainActor.run {
                    self.isSendingId = nil
                    self.sharePayload = nil
                }
                return
            }
            let senders: Set<String> = [
                "com.apple.UIKit.activity.Message",
                "com.apple.UIKit.activity.Mail",
                "net.whatsapp.WhatsApp.ShareExtension"
            ]
            let raw = activityType?.rawValue ?? ""
            if senders.contains(raw) {
                try? await InvoiceService.markSent(id: id)
                await load()
                let channel: String
                switch raw {
                case "com.apple.UIKit.activity.Message": channel = "messages"
                case "com.apple.UIKit.activity.Mail": channel = "mail"
                case "net.whatsapp.WhatsApp.ShareExtension": channel = "whatsapp"
                default: channel = "share_sheet"
                }
                AnalyticsService.track(.invoiceSent, metadata: ["channel": channel])
            }
            await MainActor.run {
                self.isSendingId = nil
                self.sharePayload = nil
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let rows = try await InvoiceService.fetchInvoices(status: status)
            await MainActor.run {
                invoices = rows
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.friendlyMessage
                self.isLoading = false
            }
        }
    }

    private func send(_ inv: InvoiceRow) async {
        // don't clear isSendingId here; we clear it after share completes/cancels
        do {
            // 1) Ask for the pay link; if not ready, do a very short retry loop
            var payURL: URL?
            for _ in 0..<6 { // up to ~1.8s total
                if let u = try await InvoiceService.sendInvoice(id: inv.id) {
                    payURL = u
                    break
                }
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            }
            guard let payURL else {
                await MainActor.run { self.error = "Could not create payment link yet. Please try again." }
                return
            }

            // 2) Build the PDF (this is synchronous & writes a real file)
            let detail = try await InvoiceService.fetchInvoiceDetail(id: inv.id)
            let pdfURL = try await PDFGenerator.makeInvoicePDF(detail: detail)

            // 3) Verify the PDF actually exists and is non-zero size (prevents blank sheet)
            let path = pdfURL.path
            var fileOK = FileManager.default.fileExists(atPath: path)
            if fileOK {
                if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber {
                    fileOK = size.intValue > 0
                }
            }
            guard fileOK else {
                await MainActor.run { self.error = "PDF wasn’t ready. Please try again." }
                return
            }

            // 4) Set items first, then present the sheet after a tiny delay
            await MainActor.run {
                self.sharePayload = nil
            }
            try? await Task.sleep(nanoseconds: 350_000_000) // allow swipe animation & share extensions to warm up
            await MainActor.run {
                let items: [Any] = ["Invoice \(detail.number)", pdfURL, payURL]
                self.sharePayload = SharePayload(items: items)
            }
        } catch {
            await MainActor.run { self.error = error.friendlyMessage }
        }
    }
}

// MARK: - Row cell

private struct InvoiceRowCell: View {
    let inv: InvoiceRow

    var body: some View {
        HStack(spacing: 12) {
            // Avatar / initials bubble
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.red.opacity(0.30), Color.orange.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5)
                    )
                // Show initials; if not available, show a doc icon as fallback
                let text = initials(from: inv.client?.name ?? "—")
                if text == "—" || text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text(text)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

            // Title block
            VStack(alignment: .leading, spacing: 2) {
                // Client first (bold)
                Text(inv.client?.name ?? "—")
                    .font(.subheadline).bold()
                // Invoice number underneath, lighter
                Text(inv.number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Amount + status
            VStack(alignment: .trailing, spacing: 6) {
                Text(currency(inv.total))
                    .font(.subheadline)
                    .monospacedDigit()
                StatusChip(status: displayStatus(inv))
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func displayStatus(_ inv: InvoiceRow) -> String {
        if inv.status == "open", inv.sent_at != nil { return "sent" }
        return inv.status
    }

    private func currency(_ total: Double?) -> String {
        let n = NumberFormatter()
        n.numberStyle = .currency
        n.currencyCode = "USD"
        n.usesGroupingSeparator = true
        return n.string(from: NSNumber(value: total ?? 0)) ?? "$0.00"
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }
}

// Minimal status chip
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
        switch status {
        case "paid": return .green
        case "overdue": return .red
        case "sent": return .yellow
        case "open": return .blue
        default: return .gray
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
