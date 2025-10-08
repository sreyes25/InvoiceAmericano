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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(InvoiceStatus.allCases, id: \.self) { s in
                            Text(s == .all ? "All" : s.rawValue.capitalized).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Invoices") {
                    if isLoading && invoices.isEmpty {
                        ProgressView("Loading…")
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                    } else if invoices.isEmpty {
                        Text("No invoices").foregroundStyle(.secondary)
                    } else {
                        ForEach(invoices, id: \.id) { inv in
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
                    }
                }
            }
            .navigationTitle("Invoices")
            .toolbar {
                Button {
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .navigationDestination(for: UUID.self) { invoiceId in
                InvoiceDetailView(invoiceId: invoiceId)
            }
            .sheet(isPresented: $showNew) {
                NavigationStack {
                    NewInvoiceView { draft in
                        Task {
                            do {
                                let _ = try await InvoiceService.createInvoice(from: draft)
                                await load()        // refresh list after save
                            } catch {
                                await MainActor.run { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            .sheet(item: $sharePayload) { payload in
                ActivitySheet(items: payload.items) { completed, activityType in
                    Task {
                        guard completed, let id = isSendingId else {
                            await MainActor.run { self.isSendingId = nil }
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
            }
            .task { await load() }
            .onChange(of: status) { _, _ in
                Task { await load() }
            }
            .refreshable { await load() }
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
            let pdfURL = try PDFGenerator.makeInvoicePDF(detail: detail)

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
    
    private func displayStatus(_ inv: InvoiceRow) -> String {
        if inv.status == "open", inv.sent_at != nil { return "sent" }
        return inv.status
    }

    private func currency(_ total: Double?) -> String {
        let n = NumberFormatter()
        n.numberStyle = .currency
        n.currencyCode = "USD"
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
