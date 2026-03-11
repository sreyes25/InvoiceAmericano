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
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .fixedSize(horizontal: true, vertical: false)
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
    
    // Persist PDF-saved indicator per invoice (local fallback).
    // If you later add a DB column (recommended), replace this with `detail.pdf_saved_at != nil`.
    private var pdfSavedKey: String { "invoice_pdf_saved_\(invoiceId.uuidString)" }
    private var didPersistPDFSaved: Bool { UserDefaults.standard.bool(forKey: pdfSavedKey) }
    private func persistPDFSavedLocally() {
        UserDefaults.standard.set(true, forKey: pdfSavedKey)
    }

    // Persist PDF-saved indicator both locally (immediate UI) and remotely (so list view shows it).
    private func persistPDFSaved() async {
        // local
        persistPDFSavedLocally()
        // remote (best-effort)
        try? await InvoiceService.markPDFSaved(id: invoiceId)
    }
    
    @State private var didCreatePaymentLinkThisSession: Bool = false

    // PDF download (from the PDF preview sheet download button) + “mark as sent” prompt
    @State private var didDownloadPDF: Bool = false
    // Controls whether the “Mark as sent?” footer has been dismissed for this invoice session.
    @State private var dismissedMarkSentPrompt: Bool = false
    @State private var markSentConfirm: Bool = false
    
    @State private var stripeConnected: Bool = false

    @State private var detail: InvoiceDetail?
    @State private var isLoading = false
    @State private var error: String?

    // Two-phase share state (prevents first-open blank sheet)
    @State private var sharePayload: SharePayload? = nil

    @State private var previewItem: PDFPreviewItem? = nil
    // Secondary indicators (session-only for now)
    @State private var didExportPDF = false
    @State private var didCreatePayLink = false

    // Returns true if this invoice has a payment link (from DB or created this session)
    private var hasCheckoutURL: Bool {
        let dbHas = !((detail?.checkout_url ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return dbHas || didCreatePaymentLinkThisSession || didCreatePayLink
    }

    // Manual workflow means we cannot reliably track payment in-app.
    // - Stripe NOT connected: always manual
    // - Stripe connected BUT user exported the PDF (they may send without link)
    private var isManualPaymentWorkflow: Bool {
        // If Stripe isn't connected → always manual.
        // If Stripe is connected → manual only if user exported/downloaded PDF and may send without link.
        // (This allows “Mark Paid” as a fallback after marking Sent.)
        (!stripeConnected) || (stripeConnected && (didDownloadPDF || didExportPDF))
    }

    // For the “Mark as sent?” banner:
    // Show whenever the PDF indicator would be present (user has exported/downloaded/saved the PDF at least once).
    private var shouldShowMarkSentPrompt: Bool {
        guard let d = detail else { return false }
        guard d.status.lowercased() == "open" else { return false }
        guard !dismissedMarkSentPrompt else { return false }

        // Show this banner whenever the PDF indicator would be present.
        // (i.e., the user has exported/downloaded the PDF at least once)
        let pdfSaved = (didPersistPDFSaved || didDownloadPDF || didExportPDF)
        return pdfSaved
    }
    // Processing fee disclaimer
    @AppStorage("hide_processing_fee_disclaimer") private var hideProcessingFeeDisclaimer: Bool = false
    @State private var showProcessingFeeDisclaimer: Bool = false

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
                                    Text("Item").font(.caption).frame(width: 40, alignment: .leading)
                                    Text("Description").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Amount").font(.caption).frame(width: 90, alignment: .trailing)
                                }
                                .foregroundStyle(.secondary)

                                ForEach(Array(d.line_items.enumerated()), id: \.element.id) { idx, it in
                                    let parsed = splitTitleAndBody(title: it.title, description: it.description)
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(idx + 1)")
                                            .frame(width: 40, alignment: .leading)
                                            .padding(.top, 2)

                                        VStack(alignment: .leading, spacing: 2) {
                                            if let title = parsed.title, !title.isEmpty {
                                                Text(title)
                                                    .font(.subheadline.weight(.semibold))
                                            }
                                            if let body = parsed.body, !body.isEmpty {
                                                Text(body)
                                                    .font(.footnote)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if it.qty > 1 {
                                                Text("\(it.qty) × \(currency(it.unit_price, d.currency)) each")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        Text(currency(it.amount, d.currency))
                                            .frame(width: 90, alignment: .trailing)
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
                       
                        // Manual Paid flow (fallback) when invoice was sent without us tracking Stripe payment.
                        // - non-Stripe users, OR
                        // - Stripe users who exported/downloaded PDF (may have sent without link)
                        if isManualPaymentWorkflow && (d.status.lowercased() == "sent" || d.status.lowercased() == "paid") {
                            SectionBox(title: "Payment") {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(d.status.lowercased() == "paid" ? "Marked as paid" : "Was this invoice paid?")
                                            .font(.subheadline.weight(.semibold))
                                        Text("Only mark paid after you’ve sent the invoice.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()

                                    Button {
                                        Task {
                                            try? await InvoiceService.markPaid(id: invoiceId)
                                            await load()
                                        }
                                    } label: {
                                        Label("Mark Paid", systemImage: "checkmark.seal.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(d.status.lowercased() != "sent") // ✅ only when sent
                                }
                            }
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
                        VStack(spacing: 10) {

                            // Prompt ONLY if: user downloaded/exported AND invoice still open AND prompt not dismissed
                            if shouldShowMarkSentPrompt {
                                MarkSentPromptCard(
                                    isOn: $markSentConfirm,
                                    onClose: {
                                        dismissedMarkSentPrompt = true
                                        markSentConfirm = false
                                    },
                                    onMarkSent: {
                                        Task {
                                            try? await InvoiceService.markSent(id: invoiceId)
                                            await load()
                                            await MainActor.run {
                                                dismissedMarkSentPrompt = true
                                                markSentConfirm = false
                                            }
                                        }
                                    }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            BottomActionBar(
                                total: d.total ?? 0,
                                onOpen: { Task { await openPDFPreview() } },
                                onSend: { sendTapped() }
                            )
                        }
                        .padding(.bottom, 6)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("No invoice loaded")
                        .font(.headline)
                    Text("ID: \(invoiceId.uuidString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Retry") {
                        Task { await load() }
                    }
                }
                .padding()
            }
        }
        .task(id: invoiceId) {
            await load()
        }
        .onAppear {
            if detail == nil && !isLoading {
                Task { await load() }
            }
        }
        .onChange(of: didDownloadPDF) { _, newValue in
            guard newValue else { return }
            Task { @MainActor in
                maybeShowMarkSentPrompt()
            }
        }
        .onChange(of: didExportPDF) { _, newValue in
            guard newValue else { return }
            Task { @MainActor in
                maybeShowMarkSentPrompt()
            }
        }
        // Present after payload is ready; this avoids the first-time blank sheet.
        .sheet(item: $sharePayload) { payload in
            ActivitySheet(items: payload.items) { completed, activityType in
                Task {
                    guard completed else { return }

                    // Treat any completed share/save/export as a PDF export signal
                    await MainActor.run {
                        self.didExportPDF = true
                        self.didDownloadPDF = true
                        self.persistPDFSavedLocally() // immediate UI
                    }
                    // Persist remotely so InvoiceListView can show the PDF icon.
                    await persistPDFSaved()

                    // Detect true "send" actions (vs. Save/Files/Print/Copy).
                    // We auto-mark Sent only for obvious sender channels.
                    let isAppleSender: Bool = {
                        guard let type = activityType else { return false }
                        return type == .message || type == .mail
                    }()

                    // Some common third-party sender extensions expose only raw identifiers.
                    let senderRawIDs: Set<String> = [
                        // WhatsApp
                        "net.whatsapp.WhatsApp.ShareExtension",
                        // Gmail / Outlook / Telegram / Signal often vary; keep this list conservative.
                        // Add more here if you confirm exact raw values in logs.
                    ]

                    let raw = activityType?.rawValue ?? ""
                    let isSender = isAppleSender || senderRawIDs.contains(raw)

                    if isSender {
                        // True send → mark as sent automatically
                        try? await InvoiceService.markSent(id: invoiceId)
                        await load()

                        await MainActor.run {
                            self.dismissedMarkSentPrompt = true
                            self.markSentConfirm = false
                        }
                    } else {
                        // Save/Copy/Print/etc → prompt manual “Mark Sent?” when allowed.
                        await MainActor.run {
                            maybeShowMarkSentPrompt()
                        }
                    }
                }
            }
        }
        .iaStandardSheetPresentation(detents: [.medium, .large], background: .system)
        .sheet(item: $previewItem) { item in
            PDFPreviewSheet(
                url: item.url,
                invoiceId: invoiceId,
                onDidDownload: {
                    Task { @MainActor in
                        didDownloadPDF = true
                        didExportPDF = true
                        persistPDFSavedLocally() // immediate UI
                        maybeShowMarkSentPrompt()
                    }
                    Task {
                        await persistPDFSaved()
                    }
                }
            )
        }
        .iaStandardSheetPresentation(detents: [.large])
        .sheet(isPresented: $showProcessingFeeDisclaimer) {
            ProcessingFeeDisclaimerSheet(
                invoiceNumber: detail?.number,
                onCancel: {
                    showProcessingFeeDisclaimer = false
                },
                onContinue: {
                    showProcessingFeeDisclaimer = false
                    Task { await send() }
                },
                onDontShowAgain: {
                    hideProcessingFeeDisclaimer = true
                    showProcessingFeeDisclaimer = false
                    Task { await send() }
                }
            )
            .iaStandardSheetPresentation(detents: [.medium], background: .glass)
        }
    }

    // Ensures the “Mark as sent?” footer appears after any real PDF export/save when we can’t reliably detect sending (non-Stripe, or Stripe connected with no payment link).
    @MainActor
    private func maybeShowMarkSentPrompt() {
        guard let d = detail else { return }
        guard d.status.lowercased() == "open" else { return }
        let pdfSaved = (didPersistPDFSaved || didDownloadPDF || didExportPDF)
        guard pdfSaved else { return }

        withAnimation(.spring()) {
            dismissedMarkSentPrompt = false
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
                        .font(.headline.weight(.semibold)) // slightly smaller so long names fit better
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)           // allow the name to shrink instead of clipping
                    Text("Invoice \(d.number)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)

                AmountPill(currency(d.total ?? 0, d.currency))
            }

            VStack(alignment: .leading, spacing: 10) {
                // Dates row
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
                }

                // Status + indicators + description row (below dates)
                let shown = displayStatus(dStatus: d.status, sentAt: dSentAt(d))

                HStack(spacing: 10) {
                    StatusChip(status: shown)
                    indicatorIcons(
                        status: shown,
                        hasCheckoutURL: hasCheckoutURL,
                        pdfSaved: (didPersistPDFSaved || didDownloadPDF || didExportPDF)
                    )
                    Text(statusDescription(for: shown))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func sendTapped() {
        // Only offer Stripe disclaimer when this invoice will actually attach a Stripe payment link.
        Task {
            let status = await IA_fetchStripeStatus()
            let connected = (status?.connected == true)
            let payment = InvoiceNotesCodec.extract(from: detail?.notes).payment
            let shouldCreateStripeLink = connected && (payment == nil || payment?.method == .stripe)

            if !shouldCreateStripeLink || hideProcessingFeeDisclaimer {
                await send()
                return
            }

            if shouldCreateStripeLink {
                await MainActor.run { showProcessingFeeDisclaimer = true }
            } else {
                await send()
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        error = nil
        do {
            let d = try await InvoiceService.fetchInvoiceDetail(id: invoiceId)

            // fetch stripe status (global per-user)
            let status = await IA_fetchStripeStatus()
            let connected = (status?.connected == true)
            
            await MainActor.run {
                detail = d
                stripeConnected = connected
                isLoading = false

                // If a PDF was previously exported (indicator present) and invoice is still open,
                // keep the “Mark as sent?” banner available.
                if didPersistPDFSaved {
                    maybeShowMarkSentPrompt()
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func openPDFPreview() async {
        guard let d = detail else { return }
        do {
            let url = try await PDFGenerator.makeInvoicePDF(detail: d)
            await MainActor.run {
                self.previewItem = PDFPreviewItem(url: url)
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func send() async {
        do {
            // 1) Decide whether this invoice should use Stripe checkout when sending.
            guard let d = detail else { return }
            let payment = InvoiceNotesCodec.extract(from: d.notes).payment
            let shouldCreateStripeLink = stripeConnected && (payment == nil || payment?.method == .stripe)

            // Legacy invoices (no payment metadata) keep existing behavior when Stripe is connected.
            let payURL = shouldCreateStripeLink
                ? (try await InvoiceService.sendInvoice(id: invoiceId))
                : nil
            await MainActor.run {
                if payURL != nil { self.didCreatePayLink = true }
            }
            await MainActor.run {
                didCreatePaymentLinkThisSession = (payURL != nil)
            }

            // 2) Fresh PDF
            let pdfURL = try await PDFGenerator.makeInvoicePDF(detail: d)

            // 3) Verify PDF exists and has size > 0
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

            // 4) Prepare share text (professional default message)
            let clientName = d.client?.name ?? "there"
            let message: String
            if payURL != nil {
                message = """
            Hi \(clientName),

            Please find your invoice #\(d.number) attached.

            A secure payment link is attached to this message.

            Thank you.
            """
                        } else {
                            message = """
            Hi \(clientName),

            Please find your invoice #\(d.number) attached.

            Let me know if you have any questions.

            Thank you.
            """
            }

            // 5) Two-phase share payload
            await MainActor.run { self.sharePayload = nil }
            try? await Task.sleep(nanoseconds: 350_000_000)

            await MainActor.run {
                var items: [Any] = [message, pdfURL]
                if let payURL { items.append(payURL) }
                self.sharePayload = SharePayload(items: items)
            }

        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    // MARK: - Helpers

    private func splitTitleAndBody(title: String?, description: String) -> (title: String?, body: String?) {
        let rawTitle = (title ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let rawDescription = description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // New world: explicit title + description coming from the database
        if !rawTitle.isEmpty {
            // If description is empty or literally the same as the title,
            // treat this as a "title-only" line item.
            if rawDescription.isEmpty || rawDescription == rawTitle {
                return (rawTitle, nil)
            }

            // Otherwise, show a real title + description pair.
            return (rawTitle, rawDescription)
        }

        // Legacy invoices where we only stored a single description string.
        // Fall back to the old parsing heuristics so existing data still renders nicely.
        if !rawDescription.isEmpty {
            return parseTitleAndBody(rawDescription)
        }

        return (nil, nil)
    }

    private func parseTitleAndBody(_ raw: String) -> (title: String?, body: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (nil, nil) }

        // First, try to split on a clear title/body separator we use when saving
        let separators = [" – ", " - "]
        for sep in separators {
            if let range = trimmed.range(of: sep) {
                let left = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

                if !left.isEmpty && !right.isEmpty {
                    return (left, right)
                } else if !left.isEmpty {
                    // Only a title was effectively provided
                    return (left, nil)
                } else if !right.isEmpty {
                    // Only a body/description
                    return (nil, right)
                }
            }
        }

        // No explicit separator. If it's reasonably short, treat it as a title; otherwise as description.
        if trimmed.count <= 40 {
            return (trimmed, nil)
        } else {
            return (nil, trimmed)
        }
    }

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

    private func parseInvoiceDate(_ s: String) -> Date? {
        let fmts: [String] = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        let inDF = DateFormatter()
        inDF.locale = Locale(identifier: "en_US_POSIX")
        inDF.timeZone = TimeZone(secondsFromGMT: 0)
        for f in fmts {
            inDF.dateFormat = f
            if let d = inDF.date(from: s) { return d }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }

    private func dSentAt(_ d: InvoiceDetail) -> String? {
        // If/when you include sent_at in InvoiceDetail, you can surface it here
        return nil
    }

    private func displayStatus(dStatus: String, sentAt: String?) -> String {
        // Frontend-derived status so Detail view matches the list logic.
        // Only invoices that were actually sent (or already marked overdue) can be considered overdue.
        let s = dStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // If backend already says paid/overdue, respect it.
        if s == "paid" || s == "overdue" { return s }

        // Only sent invoices can become overdue.
        if s != "sent" { return s }

        // If due date is in the past (and not paid), show overdue.
        guard let d = detail, let dueStr = d.dueDate, let dueDate = parseInvoiceDate(dueStr) else {
            return s
        }

        let todayStart = Calendar.current.startOfDay(for: Date())
        let dueStart = Calendar.current.startOfDay(for: dueDate)

        if dueStart < todayStart {
            return "overdue"
        }

        return s
    }

    private func statusDescription(for status: String) -> String {
        switch status.lowercased() {
        case "open": return "Invoice created"
        case "sent": return "Invoice link sent to client"
        case "paid": return "Client paid invoice in full"
        case "overdue": return "Due date passed and invoice is unpaid"
        default: return ""
        }
    }

    @ViewBuilder
    private func indicatorIcons(status: String, hasCheckoutURL: Bool, pdfSaved: Bool) -> some View {
        HStack(spacing: 8) {
            let s = status.lowercased()
            let isSentLike = (s == "sent" || s == "paid" || s == "overdue")

            // PDF indicator: ONLY after the user exported/downloaded a PDF (persisted per invoice).
            if pdfSaved {
                Image(systemName: "doc")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("PDF saved")
            }

            // Link indicator: ONLY when invoice is sent-like AND link exists AND Stripe is connected.
            if stripeConnected && hasCheckoutURL && isSentLike {
                Image(systemName: "link")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Payment link sent")
            }
        }
    }
}

// MARK: - Processing Fee Disclaimer (Apple glass style)
private struct ProcessingFeeDisclaimerSheet: View {
    let invoiceNumber: String?
    
    let onCancel: () -> Void
    let onContinue: () -> Void
    let onDontShowAgain: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 44, height: 5)
                .padding(.top, 10)

            VStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Processing fee notice")
                    .font(.title3.weight(.semibold))

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            VStack(spacing: 10) {
                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onDontShowAgain()
                } label: {
                    Text("Don’t show again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                // Apple-glass look
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10))
            }
            .ignoresSafeArea()
        )
    }

    private var message: String {
        let num = invoiceNumber ?? ""
        if num.isEmpty {
            return "When you include a payment link, your client will pay the invoice total plus a $1 processing fee."
        }
        return "When you include a payment link, your client will pay invoice #\(num) plus a $1 processing fee."
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
    let onDidDownload: () -> Void

    // two-phase share payload (prevents first-open blank sheet)
    private struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    @State private var payload: SharePayload? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DetailPDFKitView(url: url)
                .ignoresSafeArea()

            Button {
                Task { await presentDownload() }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.title2)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        // present AFTER payload is ready (prevents blank sheet on first try)
        .sheet(item: $payload) { p in
            ActivitySheet(items: p.items) { completed, _ in
                guard completed else { return }
                onDidDownload()
                dismiss() // ✅ return to invoice detail view immediately after export
            }
        }
        .iaStandardSheetPresentation(detents: [.medium, .large], background: .system)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
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

private struct DetailPDFKitView: UIViewRepresentable {
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

private struct MarkSentPromptCard: View {
    @Binding var isOn: Bool
    let onClose: () -> Void
    let onMarkSent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.yellow.opacity(0.18))
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.yellow)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mark as sent?")
                        .font(.subheadline.weight(.semibold))
                    Text("If you exported the PDF and sent it to your client, you can mark this invoice as sent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                }
            }

            HStack {
                Text("I sent this invoice")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }

            Button(action: onMarkSent) {
                Text("Mark Sent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isOn)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
        .padding(.horizontal, 12)
    }
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
