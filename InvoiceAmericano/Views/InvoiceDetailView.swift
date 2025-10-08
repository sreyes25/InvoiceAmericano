//
//  InvoiceDetailView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/7/25.
//

import SwiftUI
import PDFKit
import UIKit

struct InvoiceDetailView: View {
    let invoiceId: UUID

    @State private var detail: InvoiceDetail?
    @State private var isLoading = false
    @State private var error: String?

    // Share state (2-phase presentation to avoid first-time blank sheet)
    @State private var shareItems: [Any] = []
    @State private var isPresentingShare = false

    @State private var previewItem: PDFPreviewItem? = nil

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView("Loading…")
            } else if let error {
                VStack(spacing: 12) {
                    Text("Error").font(.headline)
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                }
            } else if let d = detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(d)

                        SectionBox(title: "Bill To") {
                            Text(d.client?.name ?? "—")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        SectionBox(title: "Items") {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Qty").font(.caption).frame(width: 40, alignment: .leading)
                                    Text("Description").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Amount").font(.caption).frame(width: 90, alignment: .trailing)
                                }
                                .foregroundStyle(.secondary)

                                ForEach(d.line_items) { it in
                                    HStack {
                                        Text("\(it.qty)").frame(width: 40, alignment: .leading)
                                        Text(it.description).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(currency(it.amount, d.currency)).frame(width: 90, alignment: .trailing)
                                    }
                                }
                            }
                        }

                        SectionBox(title: "Totals") {
                            TotalRow(label: "Subtotal", value: currency(d.subtotal ?? 0, d.currency))
                            if let t = d.tax, t != 0 {
                                TotalRow(label: "Tax", value: currency(t, d.currency))
                            }
                            TotalRow(label: "Total", value: currency(d.total ?? 0, d.currency), bold: true)
                        }

                        // ===== Actions (elongated card with centered, big buttons) =====
                        SectionBox(title: "Actions") {
                            VStack(spacing: 16) {
                                Button {
                                    Task { await openPDFPreview() }
                                } label: {
                                    Label("Open", systemImage: "doc.text")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)

                                Button {
                                    Task { await send() }
                                } label: {
                                    Label("Send Invoice", systemImage: "paperplane")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 360)
                    }
                    .padding()
                }
                .navigationTitle("Invoice \(d.number)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await openPDFPreview() }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .accessibilityLabel("Download PDF")
                    }
                }
            } else {
                EmptyView()
            }
        }
        .task { await load() }

        // 2-phase share presentation: show only after items are set and a tiny delay has passed
        .sheet(isPresented: $isPresentingShare, onDismiss: {
            // cleanup after sheet closes
            self.shareItems = []
        }) {
            ActivitySheet(items: shareItems) { completed, activityType in
                Task {
                    guard completed else { return }
                    // Mark sent only if a real sender was used
                    let senders: Set<String> = [
                        "com.apple.UIKit.activity.Message",
                        "com.apple.UIKit.activity.Mail",
                        "net.whatsapp.WhatsApp.ShareExtension"
                    ]
                    let raw = activityType?.rawValue ?? ""
                    if senders.contains(raw) {
                        try? await InvoiceService.markSent(id: invoiceId)
                        await load()
                    }
                }
            }
        }
        .sheet(item: $previewItem) { item in
            PDFPreviewSheet(url: item.url, invoiceId: invoiceId)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func header(_ d: InvoiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusChip(status: displayStatus(dStatus: d.status, sentAt: dSentAt(d)))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    // Prefer issued_at; fall back to created_at. Both shown as MM/dd/yy.
                    if let issuedOrCreated = (d.issued_at ?? d.created_at) {
                        RowKV(k: "Date", v: shortDate(issuedOrCreated))
                    }
                    if let due = d.dueDate {
                        RowKV(k: "Due", v: shortDate(due))
                    }
                }
            }
        }
    }

    private func RowKV(k: String, v: String) -> some View {
        HStack(spacing: 8) {
            Text(k + ":").foregroundStyle(.secondary)
            Text(v)
        }
        .font(.subheadline)
    }

    private func TotalRow(label: String, value: String, bold: Bool = false) -> some View {
        HStack {
            Spacer()
            Text(label)
                .font(bold ? .headline : .subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(bold ? .headline : .subheadline)
                .frame(width: 120, alignment: .trailing)
        }
    }

    private func SectionBox<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).bold()
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        error = nil
        do {
            let d = try await InvoiceService.fetchInvoiceDetail(id: invoiceId)
            await MainActor.run { detail = d; isLoading = false }
        } catch {
            await MainActor.run { self.error = error.localizedDescription; self.isLoading = false }
        }
    }

    private func openPDFPreview() async {
        guard let d = detail else { return }
        do {
            let url = try PDFGenerator.makeInvoicePDF(detail: d)
            await MainActor.run { self.previewItem = PDFPreviewItem(url: url) }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func send() async {
        do {
            // 1) Create/refresh checkout link
            let url = try await InvoiceService.sendInvoice(id: invoiceId)
            guard let payURL = url else {
                await MainActor.run { self.error = "Could not create payment link." }
                return
            }

            // 2) Fresh PDF
            guard let d = detail else { return }
            let pdfURL = try PDFGenerator.makeInvoicePDF(detail: d)

            // 3) Phase 1: set items (no presentation yet)
            await MainActor.run {
                self.shareItems = [pdfURL, payURL]
            }

            // 4) Phase 2: present after a tiny delay to avoid first-open blank sheet
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
            await MainActor.run {
                self.isPresentingShare = true
            }

        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    // MARK: - Helpers

    private func currency(_ amount: Double, _ code: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = (code ?? "USD").uppercased()
        return f.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    private func shortDate(_ s: String) -> String {
        // Try common formats (order matters)
        let fmts: [String] = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]

        let inDF = DateFormatter()
        inDF.locale = Locale(identifier: "en_US_POSIX")
        inDF.timeZone = TimeZone(secondsFromGMT: 0)

        var parsed: Date? = nil
        for f in fmts {
            inDF.dateFormat = f
            if let d = inDF.date(from: s) { parsed = d; break }
        }

        if parsed == nil {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            parsed = iso.date(from: s)
            if parsed == nil {
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                parsed = iso.date(from: s)
            }
        }

        guard let date = parsed else { return s }

        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = .current
        out.dateFormat = "MM/dd/yy"
        return out.string(from: date)
    }

    private func dSentAt(_ d: InvoiceDetail) -> String? {
        // If/when you add sent_at into InvoiceDetail, plug it here.
        return nil
    }

    private func displayStatus(dStatus: String, sentAt: String?) -> String {
        // If you later include sent_at: if dStatus == "open" && sentAt != nil → "sent"
        return dStatus
    }
}

// MARK: - Small helper views

private struct StatusChip: View {
    let status: String
    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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

private struct PDFPreviewSheet: View {
    let url: URL
    let invoiceId: UUID
    @State private var showShare = false
    @State private var shareItems: [Any]? = nil

    var body: some View {
        ZStack {
            PDFKitView(url: url)
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    // Share/Download the PDF itself
                    shareItems = [url]
                    showShare = true
                } label: {
                    Label("Download", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showShare) {
            ActivitySheet(items: shareItems ?? [])
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

private struct PDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
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
