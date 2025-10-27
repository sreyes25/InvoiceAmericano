//
//  InvoiceDetailView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/7/25.
//


import SwiftUI
import PDFKit
import UIKit

// MARK: - Lightweight Style
private enum BrandStyle {
    static let radius: CGFloat = 16
    static let cardStroke = Color.black.opacity(0.08)
    static let cardShadow = Color.black.opacity(0.06)
    static let cardFill = Color(.secondarySystemBackground)
    static let surface = Color(.systemBackground)

    static let gradIris = LinearGradient(
        colors: [Color(hex: "#5C6EFF"), Color(hex: "#8A6CFF")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

private struct CardBackground: ViewModifier {
    var radius: CGFloat = BrandStyle.radius
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(BrandStyle.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(BrandStyle.cardStroke)
            )
            .shadow(color: BrandStyle.cardShadow, radius: 8, y: 3)
    }
}
private extension View {
    func cardStyle(radius: CGFloat = BrandStyle.radius) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

private extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var rgb: UInt64 = 0; Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

private func AmountPill(_ value: String) -> some View {
    Text(value)
        .font(.title3.weight(.bold))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(BrandStyle.gradIris)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct InvoiceDetailView: View {
    let invoiceId: UUID

    @State private var detail: InvoiceDetail?
    @State private var isLoading = false
    @State private var error: String?

    // Two-phase share state (prevents first-open blank sheet)
    @State private var sharePayload: SharePayload? = nil

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

                                ForEach(Array(d.line_items.enumerated()), id: \.element.id) { idx, it in
                                    HStack {
                                        Text("\(it.qty)").frame(width: 40, alignment: .leading)
                                        Text(it.description).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(currency(it.amount, d.currency)).frame(width: 90, alignment: .trailing)
                                    }
                                    .padding(.vertical, 6)
                                    .background(idx.isMultiple(of: 2) ? Color.primary.opacity(0.03) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
                .background(BrandStyle.surface)
                .contentMargins(.bottom, 76)
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
                .safeAreaInset(edge: .bottom) {
                    if let d = detail {
                        BottomActionBar(
                            total: d.total ?? 0,
                            onOpen: { Task { await openPDFPreview() } },
                            onSend: { Task { await send() } }
                        )
                    }
                }
            } else {
                EmptyView()
            }
        }
        .task { await load() }

        // Present after payload is ready; this avoids the first-time blank sheet.
        .sheet(item: $sharePayload) { payload in
            ActivitySheet(items: payload.items) { completed, activityType in
                Task {
                    guard completed else { return }
                    // Mark sent only for real “sending” activities
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                // Leading badge
                ZStack {
                    Circle().fill(Color.blue.opacity(0.12))
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(d.client?.name ?? "—")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text("Invoice \(d.number)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)

                AmountPill(currency(d.total ?? 0, d.currency))
            }

            HStack(spacing: 14) {
                if let issuedOrCreated = (d.issued_at ?? d.created_at) {
                    Label(shortDate(issuedOrCreated), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let due = d.dueDate {
                    Label(shortDate(due), systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusChip(status: displayStatus(dStatus: d.status, sentAt: dSentAt(d)))
            }
        }
        .padding()
        .cardStyle()
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
                .monospacedDigit()
                .frame(width: 120, alignment: .trailing)
        }
    }

    private func SectionBox<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding()
        .cardStyle()
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
            let url = try await PDFGenerator.makeInvoicePDF(detail: d)
            await MainActor.run { self.previewItem = PDFPreviewItem(url: url) }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func send() async {
        do {
            // 1) Create/refresh checkout link (require it to exist to proceed)
            guard let payURL = try await InvoiceService.sendInvoice(id: invoiceId) else {
                await MainActor.run { self.error = "Could not create payment link." }
                return
            }

            // 2) Fresh PDF
            guard let d = detail else { return }
            let pdfURL = try await PDFGenerator.makeInvoicePDF(detail: d)

            // 3) Verify the PDF really exists and has size > 0 (prevents blank sheet)
            let path = pdfURL.path
            var fileOK = FileManager.default.fileExists(atPath: path)
            if fileOK {
                if let sz = try? FileManager.default
                    .attributesOfItem(atPath: path)[.size] as? NSNumber {
                    fileOK = sz.intValue > 0
                }
            }
            guard fileOK else {
                await MainActor.run { self.error = "PDF wasn’t ready. Please try again." }
                return
            }

            // 4) Phase A: clear any previous payload, then wait a tick
            await MainActor.run { self.sharePayload = nil }
            try? await Task.sleep(nanoseconds: 350_000_000) // ~0.35s warms extensions

            // 5) Phase B: set payload which triggers the sheet
            await MainActor.run {
                let items: [Any] = ["Invoice \(d.number)", pdfURL, payURL]
                self.sharePayload = SharePayload(items: items)
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
        for f in fmts { inDF.dateFormat = f; if let d = inDF.date(from: s) { parsed = d; break } }
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
        // If/when you include sent_at in InvoiceDetail, you can surface it here
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

    // two-phase share payload (prevents first-open blank sheet)
    private struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    @State private var payload: SharePayload? = nil

    var body: some View {
        ZStack {
            PDFKitView(url: url)
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    Task { await presentDownload() }
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
        // present AFTER payload is ready (prevents blank sheet on first try)
        .sheet(item: $payload) { p in
            ActivitySheet(items: p.items)
        }
    }

    // MARK: - Helpers

    private func presentDownload() async {
        // 1) Make sure the file exists and has non-zero size
        let path = url.path
        var ok = FileManager.default.fileExists(atPath: path)
        if ok, let size = try? FileManager.default
            .attributesOfItem(atPath: path)[.size] as? NSNumber {
            ok = size.intValue > 0
        }
        guard ok else { return }

        // 2) Phase A: clear any previous payload, then wait a tick so
        //    UIActivityViewController can initialize extensions cleanly.
        await MainActor.run { self.payload = nil }
        try? await Task.sleep(nanoseconds: 350_000_000) // ~0.35s

        // 3) Phase B: set payload which triggers the sheet
        await MainActor.run { self.payload = SharePayload(items: [url]) }
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

// Bottom action bar for invoice actions
private struct BottomActionBar: View {
    let total: Double
    let onOpen: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                Label("Open PDF", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(action: onSend) {
                Label("Send", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(total <= 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(.black.opacity(0.06))
                .frame(height: 0.5),
            alignment: .top
        )
    }
}
