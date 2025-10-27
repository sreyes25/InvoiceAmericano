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
                    NavigationLink(value: inv.id) {
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
                }
                .listRowSeparator(.hidden)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
    }

    var body: some View {
        NavigationStack {
            List {
                statusPickerSection
                invoicesSection
            }
            .navigationTitle("Invoices")
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search invoices or clients")
            .toolbar { addButton }
            .navigationDestination(for: UUID.self) { invoiceId in
                InvoiceDetailView(invoiceId: invoiceId)
            }
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
            .listStyle(.insetGrouped)
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
            _ = try await InvoiceService.createInvoice(from: draft)
            await load()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
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
                self.error = error.localizedDescription
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
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Row cell

private struct InvoiceRowCell: View {
    let inv: InvoiceRow

    var body: some View {
        HStack(spacing: 12) {
            // Leading badge
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            // Title block
            VStack(alignment: .leading, spacing: 4) {
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
        }
        .padding(12)
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
