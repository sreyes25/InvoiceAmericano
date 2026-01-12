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
    @FocusState private var searchFocused: Bool
    @Namespace private var statusNS

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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InvoiceStatus.allCases, id: \.self) { s in
                    statusChip(s)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func statusChip(_ s: InvoiceStatus) -> some View {
        let isSelected = (s == status)
        let title = (s == .all ? "All" : s.rawValue.capitalized)
        let tint = statusTint(s)

        return Button {
            guard status != s else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy(duration: 0.22)) {
                status = s
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint.opacity(isSelected ? 0.85 : 0.35))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                ZStack {
                    // Selected pill highlight (animated)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(tint.opacity(0.14))
                            .matchedGeometryEffect(id: "status", in: statusNS)
                            .overlay(
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(
                                        LinearGradient(colors: [
                                            tint.opacity(0.18),
                                            tint.opacity(0.08)
                                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(tint.opacity(0.06)) // lower opacity when not selected
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .strokeBorder(
                        isSelected ? tint.opacity(0.35) : Color.black.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(isSelected ? 0.12 : 0.0), radius: 10, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusTint(_ s: InvoiceStatus) -> Color {
        switch s {
        case .all: return .gray
        //case .open: return .blue
        case .sent: return .orange
        case .overdue: return .red
        case .paid: return .green
        }
    }

    @ViewBuilder
    private var invoicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Invoices")
                    .font(.headline)
                Spacer()
                if !invoices.isEmpty {
                    Text("\(filteredInvoices.count) shown")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if isLoading && invoices.isEmpty {
                loadingCard
            } else if let error, invoices.isEmpty {
                errorCard(error)
            } else if filteredInvoices.isEmpty {
                emptyStateCard
            } else {
                VStack(spacing: 10) {
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
                                if isSendingId == inv.id {
                                    Label("Sending…", systemImage: "paperplane")
                                } else {
                                    Label("Send", systemImage: "paperplane")
                                }
                            }
                            .tint(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.black.opacity(0.05))
        )
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Fetching your latest invoices")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") {
                Task { await load() }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 6)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            Image(systemName: search.isEmpty ? "doc.text" : "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(search.isEmpty ? "No invoices yet" : "No results for \"\(search)\"")
                .font(.subheadline.weight(.semibold))

            Text(search.isEmpty ? "Create your first invoice to get paid faster." : "Try a different search or switch status.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if search.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showNew = true
                } label: {
                    Text("Create Invoice")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    searchBar
                    invoicesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background {
                AnimatedInvoicesBackground(status: status)
            }
            .navigationTitle("Invoices")
            .toolbar { addButton }
            .navigationDestination(item: $pushInvoiceId) { invoiceId in
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
            .scrollIndicators(.hidden)
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill((status == .all ? Color.gray : Color.blue).opacity(searchFocused ? 0.18 : 0.10))
                        .frame(width: 34, height: 34)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                TextField("Search by invoice # or client", text: $search)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .focused($searchFocused)

                if !search.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            search = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                if searchFocused {
                    Button("Cancel") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            searchFocused = false
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(searchFocused ? Color.blue.opacity(0.35) : Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(searchFocused ? 0.10 : 0.06), radius: 10, y: 5)
            .animation(.snappy(duration: 0.22), value: searchFocused)
            .animation(.easeInOut(duration: 0.15), value: search)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InvoiceStatus.allCases, id: \.self) { s in
                        statusChip(s)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showNew = true
            } label: {
                Label("New", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
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

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        // Some PostgREST/Supabase errors wrap cancellation; fall back to string match.
        let msg = (error as NSError).localizedDescription.lowercased()
        if msg.contains("cancelled") || msg.contains("canceled") { return true }
        return false
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            // Do NOT clear existing invoices or force an error card during pull-to-refresh.
            error = nil
        }

        do {
            let rows = try await InvoiceService.fetchInvoices(status: status)
            await MainActor.run {
                invoices = rows
                isLoading = false
            }
        } catch {
            // ✅ Pull-to-refresh can cancel the task; that's not a real error.
            if isCancellation(error) {
                await MainActor.run { isLoading = false }
                return
            }

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
                let base = clientColor(inv).opacity(0.32)
                let hi = clientColor(inv).opacity(0.18)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [base, hi],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)
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

    private func clientColor(_ inv: InvoiceRow) -> Color {
        // Prefer the per-client color coming from DB (clients.color_hex).
        if let hex = inv.client?.colorHex, let c = Color(hex: hex) {
            return c
        }
        // Fallback keeps the previous gray-ish look.
        return .gray
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

// MARK: - Animated background (subtle)

private struct AnimatedInvoicesBackground: View {
    let status: InvoiceStatus
    @State private var drift = false

    private func tint(for status: InvoiceStatus) -> Color {
        switch status {
        case .all: return .gray
        case .sent: return .orange
        case .overdue: return .red
        case .paid: return .green
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            Circle()
                .fill(tint(for: status).opacity(0.07))
                .frame(width: 560, height: 560)
                .blur(radius: 58)
                .offset(x: drift ? 140 : -120, y: drift ? -80 : -140)

            Circle()
                .fill(tint(for: status).opacity(0.11))
                .frame(width: 540, height: 540)
                .blur(radius: 58)
                .offset(x: drift ? -120 : 130, y: drift ? 220 : 160)

            Circle()
                .fill(tint(for: status).opacity(0.13))
                .frame(width: 600, height: 600)
                .blur(radius: 52)
                .offset(x: drift ? -40 : 60, y: drift ? -260 : -220)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
    }
}


//#Preview("Invoices – Light") {
//    InvoiceListView()
//        .preferredColorScheme(.light)
//}
//
//#Preview("Invoices – Dark") {
//    InvoiceListView()
//        .preferredColorScheme(.dark)
//}




private extension Color {
    /// Parses "#RRGGBB" or "RRGGBB" (and optionally "#AARRGGBB"). Returns nil if invalid.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&value) else { return nil }

        let a, r, g, b: Double
        if s.count == 8 {
            a = Double((value & 0xFF00_0000) >> 24) / 255.0
            r = Double((value & 0x00FF_0000) >> 16) / 255.0
            g = Double((value & 0x0000_FF00) >> 8) / 255.0
            b = Double(value & 0x0000_00FF) / 255.0
        } else {
            a = 1.0
            r = Double((value & 0xFF00_00) >> 16) / 255.0
            g = Double((value & 0x00FF_00) >> 8) / 255.0
            b = Double(value & 0x0000_FF) / 255.0
        }

        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
