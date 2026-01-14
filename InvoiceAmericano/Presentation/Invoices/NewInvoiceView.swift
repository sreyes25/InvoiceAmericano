//
//  NewInvoiceView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/6/25.
//




import SwiftUI
import Foundation
import UIKit
import Combine

import PDFKit

// MARK: - Hex Color Helper
private extension Color {
    /// Supports: "#RRGGBB" or "RRGGBB" (case-insensitive)
    init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

private enum ClientAvatar {
    static func fillColor(hex: String?) -> Color {
        Color(hex: hex) ?? Color.gray.opacity(0.55)
    }
}

// Global UI spacers for consistent structure
private enum UI {
    static let rowH: CGFloat = 14      // horizontal insets for card rows
    static let rowV: CGFloat = 8       // vertical insets for card rows
}

// Simple PDFKit wrapper for in-memory draft preview
private struct DraftPDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Nothing to update for now
    }
}

// PreferenceKey to report Y position of a view (for sticky footer logic)
struct ViewYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

// Helper to round only specific corners
struct RoundedCorner: Shape {
    var radius: CGFloat = 10
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct InvoiceDraft {
    var number: String = ""
    var client: ClientRow?
    var dueDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
    var currency: String = "USD"
    var taxPercent: Double = 0
    var notes: String = ""
    var items: [LineItemDraft] = []

    var subTotal: Double {
        items.reduce(0) { $0 + ($1.unitPrice * Double(max(1, $1.quantity))) }
    }
    var taxAmount: Double { subTotal * (taxPercent / 100.0) }
    var total: Double { subTotal + taxAmount }
}

struct LineItemDraft: Identifiable, Hashable {
    let id = UUID()
    var title: String = ""
    var description: String = ""
    var quantity: Int = 1
    var unitPrice: Double = 0
}

// A tiny shell so New-Invoice looks identical wherever it's presented
struct NewInvoiceNavShell: View {
    let onSaved: (InvoiceDraft) -> Void
    let onClose: () -> Void
    var preselectedClient: ClientRow? = nil
    var lockClient: Bool = false

    var body: some View {
        NavigationStack {
            NewInvoiceView(
                preselectedClient: preselectedClient,
                lockClient: lockClient,
                onSaved: onSaved
            )
            // Prevent double-translucency re-blend on scroll
            .background(Color(.systemBackground).ignoresSafeArea())
            // Match the glassy, centered small title look
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
        // Keep the sheet chrome from fighting the nav bar
        .presentationBackground(.clear)
    }
}

struct NewInvoiceView: View {
    var preselectedClient: ClientRow? = nil
    var lockClient: Bool = false
    var onSaved: (InvoiceDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingPreview = false
    @State private var pdfData: Data? = nil
    @State private var isGeneratingPDF = false
    @State private var draft: InvoiceDraft
    @State private var clients: [ClientRow] = []
    @State private var isLoadingClients = true
    @State private var error: String?

    // Sheet picker state
    @State private var showClientPicker = false
    @State private var clientSearch = ""
    @State private var showNewClientSheet = false
    @State private var showDueDateSheet = false
    @State private var showItemPicker = false
    @State private var expandedItemIDs: Set<UUID> = []
    @StateObject private var itemVM = ItemDraftViewModel()
    @State private var themeColor: Color = .blue

    @State private var totalsOnScreen: Bool = false
    @State private var footerOpacity: Double = 1

    // Track if user manually changed due date, so defaults don't overwrite it later
    @State private var didUserChangeDueDate = false

    // Prevents saving 0-dollar invoices
    private var canSave: Bool {
        guard draft.client != nil else { return false }
        return draft.total > 0 && draft.items.contains { li in
            let hasContent = !li.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             !li.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasContent && li.unitPrice > 0 && li.quantity > 0
        }
    }

    init(preselectedClient: ClientRow? = nil,
         lockClient: Bool = false,
         onSaved: @escaping (InvoiceDraft) -> Void) {
        self.preselectedClient = preselectedClient
        self.lockClient = lockClient
        self.onSaved = onSaved

        let initial = InvoiceDraft(
            number: "",
            client: preselectedClient,
            dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Date())!,
            currency: "USD",
            taxPercent: 0,
            notes: "",
            items: []
        )
        _draft = State(initialValue: initial)
    }

    var body: some View {
        return GeometryReader { geo in
            let containerHeight = geo.size.height
            Form {
                // --- Header (Client + Details + Notes) grouped in one card ---
                Section {
                    TopInvoiceCard(
                        selectedClient: draft.client,
                        lockClient: lockClient,
                        isLoading: isLoadingClients,
                        onTapClient: { showClientPicker = true },
                        date: draft.dueDate,
                        invoiceNumber: draft.number,
                        taxPercent: draft.taxPercent,
                        taxAmount: draft.taxAmount,
                        onTapDetails: { showDueDateSheet = true },
                        noteText: draft.notes,
                        onTapNotes: { showDueDateSheet = true }
                    )
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Invoice")
                }

                // --- Items grouped in one card (Add button inside) ---
                Section {
                    ItemsGroupCard(
                        items: $draft.items,
                        expandedItemIDs: $expandedItemIDs,
                        onAddTap: {
                            itemVM.title = ""
                            itemVM.description = ""
                            itemVM.quantity = 1
                            itemVM.unitPrice = 0
                            showItemPicker = true
                        }
                    )
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Items")
                }

                // --- Totals grouped in one card with bold divider before Total ---
                Section {
                    TotalsCard(
                        subTotal: draft.subTotal,
                        taxAmount: draft.taxAmount,
                        total: draft.total,
                        currencyCode: draft.currency
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: ViewYPreferenceKey.self,
                                            value: proxy.frame(in: .named("formScroll")).minY)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Totals")
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground).ignoresSafeArea())
            .listStyle(.plain)
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Preview") {
                        Task {
                            await generatePreviewPDF()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .tint(themeColor)
            .animation(.easeInOut(duration: 0.25), value: themeColor)
            .coordinateSpace(name: "formScroll")
            .listRowSpacing(UI.rowV) // keep vertical rhythm between rows
            // Sticky, translucent running-total bar (“Apple glass” look)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("Total")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(currency(draft.total, code: draft.currency))
                        .font(.headline.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.25))
                )
                .shadow(color: .black.opacity(0.15), radius: 12, y: 2)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .opacity(footerOpacity)
                .allowsHitTesting(footerOpacity > 0.05)
                .animation(.easeInOut(duration: 0.20), value: footerOpacity)
            }
            .onPreferenceChange(ViewYPreferenceKey.self) { totalsTopY in
                // Where the sticky footer lives on screen
                let footerHeight: CGFloat = 64
                let footerBottomPadding: CGFloat = 8
                let contactY = containerHeight - footerHeight - footerBottomPadding

                // Start the fade a bit BEFORE the totals card reaches the footer so it
                // feels like it melts away as the Totals section approaches.
                let fadeLead: CGFloat = 190   // how early the fade should begin
                let fadeRange: CGFloat = 160  // how long the fade lasts

                // Positive distance means we are still above the fade start.
                let distance = totalsTopY - (contactY + fadeLead)

                // Map distance into [0,1] for opacity where 1 = fully visible, 0 = gone.
                let clamped = max(0, min(1, distance / fadeRange))
                footerOpacity = Double(clamped)

                // Optional flag if you still want it
                totalsOnScreen = distance <= fadeRange
            }
            // Collapse any expanded item editors only after a deliberate drag end with threshold
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        if max(dx, dy) > 24 {
                            if !expandedItemIDs.isEmpty {
                                expandedItemIDs.removeAll()
                            }
                        }
                    }
            )
            // Load clients
            .sheet(isPresented: $showClientPicker) {
                ClientPickerSheet(
                    clients: clients,
                    isLoading: isLoadingClients,
                    searchText: $clientSearch,
                    onCancel: { showClientPicker = false },
                    onSelect: { selected in
                        draft.client = selected
                        showClientPicker = false
                        // After choosing a client, open the item picker to keep the flow fast
                        showItemPicker = true
                    },
                    onCreateNew: {
                        showNewClientSheet = true
                    }
                )
                .presentationDetents([.large])
                .presentationCornerRadius(28)
                .presentationBackground(.ultraThinMaterial)
                .presentationDragIndicator(.visible)
                .sheet(isPresented: $showNewClientSheet) {
                    NavigationStack {
                        NewClientView {
                            // After creating a client, refresh list so it appears
                            showNewClientSheet = false
                            Task { await loadClients() }
                        }
                    }
                }
            }
            // Item quick-pick / create sheet
            .sheet(isPresented: $showItemPicker) {
                ItemPickerSheet(
                    viewModel: itemVM,
                    currentItemIndex: draft.items.count + 1,
                    presets: ["Service call", "Labor hour", "Materials", "Cleanup"],
                    onAdd: { newItem in
                        var item = newItem
                        // If the user only filled the title (or used a quick pick), promote it
                        // into the description so the saved invoice has visible line text.
                        let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedDesc  = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedDesc.isEmpty, !trimmedTitle.isEmpty {
                            item.description = trimmedTitle
                        }

                        draft.items.append(item)
                        showItemPicker = false
                    },
                    onClose: { showItemPicker = false }
                )
                .presentationDetents([.large])
                .presentationCornerRadius(28)
                .presentationBackground(.ultraThinMaterial)
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showDueDateSheet) {
                NavigationStack {
                    Form {
                        Section {
                            DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                            TextField("Invoice #", text: $draft.number)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                            HStack {
                                Text("Tax %")
                                Spacer()
                                TextField("0", value: $draft.taxPercent, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                        }
                        Section {
                            TextField("Notes", text: $draft.notes, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }
                    .navigationTitle("Invoice details")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDueDateSheet = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showDueDateSheet = false } }
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .onChange(of: draft.dueDate) { _, _ in
                    didUserChangeDueDate = true
                }
            }
            .sheet(isPresented: $isShowingPreview) {
                NavigationStack {
                    VStack(spacing: 0) {
                        if let data = pdfData {
                            // Real PDF preview
                            DraftPDFKitView(data: data)
                                .ignoresSafeArea()
                        } else {
                            // Fallback while PDF is being generated or not available
                            VStack(spacing: 20) {
                                Text("Invoice Preview")
                                    .font(.title2.bold())
                                    .padding(.top)

                                if isGeneratingPDF {
                                    ProgressView("Generating PDF…")
                                        .padding()
                                }

                                // Textual fallback preview
                                List {
                                    Section("Client") {
                                        if let client = draft.client {
                                            Text(client.name)
                                            if let email = client.email, !email.isEmpty {
                                                Text(email).foregroundStyle(.secondary)
                                            }
                                        } else {
                                            Text("No client selected").foregroundStyle(.secondary)
                                        }
                                    }

                                    Section("Details") {
                                        Text("Invoice #: \(draft.number.isEmpty ? "—" : draft.number)")
                                        Text("Due: \(draft.dueDate.formatted(date: .abbreviated, time: .omitted))")
                                        Text("Tax: \(draft.taxPercent, format: .number)\u{202F}%")
                                    }

                                    Section("Items") {
                                        if draft.items.isEmpty {
                                            Text("No items").foregroundStyle(.secondary)
                                        } else {
                                            ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.title.isEmpty ? "Item \(index + 1)" : item.title)
                                                        .font(.headline)
                                                    if !item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                        Text(item.description)
                                                            .font(.subheadline)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    HStack {
                                                        Text("Qty: \(item.quantity)")
                                                        Spacer()
                                                        Text(item.unitPrice, format: .currency(code: draft.currency))
                                                    }
                                                    .font(.footnote)
                                                }
                                                .padding(.vertical, 4)
                                            }
                                        }
                                    }

                                    Section("Totals") {
                                        HStack {
                                            Text("Subtotal")
                                            Spacer()
                                            Text(draft.subTotal, format: .currency(code: draft.currency))
                                        }
                                        HStack {
                                            Text("Tax")
                                            Spacer()
                                            Text(draft.taxAmount, format: .currency(code: draft.currency))
                                        }
                                        HStack {
                                            Text("Total")
                                                .font(.headline)
                                            Spacer()
                                            Text(draft.total, format: .currency(code: draft.currency))
                                                .font(.headline)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Edit") {
                                isShowingPreview = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                onSaved(draft)
                                isShowingPreview = false
                                dismiss()
                            }
                        }
                    }
                }
            }
            .task { await loadClients() }
            .onAppear {
                if draft.client == nil { showClientPicker = true }
            }
            // Prefill from user defaults (terms not shown here; we map tax/dueDays/footerNotes)
            .task {
                if let d = try? await InvoiceDefaultsService.loadDefaults() {
                    await MainActor.run {
                        // Only apply if user hasn’t already changed them
                        if draft.taxPercent == 0 { draft.taxPercent = d.taxRate }
                        if !didUserChangeDueDate {
                            if let newDue = Calendar.current.date(byAdding: .day, value: d.dueDays, to: Date()) {
                                draft.dueDate = newDue
                            }
                        }
                    }
                }
            }
            // Prefill a friendly invoice number (editable)
            .task {
                if draft.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let next = try? await InvoiceService.nextInvoiceNumber() {
                        await MainActor.run { draft.number = next }
                    }
                }
            }
        }
    }
    // --- Inserted generatePreviewPDF below ---
    private func generatePreviewPDF() async {
        await MainActor.run {
            isGeneratingPDF = true
            pdfData = nil
            isShowingPreview = true
            error = nil
        }

        do {
            // Build a neutral snapshot from the in-progress draft
            let snapshot = InvoicePDFSnapshot(from: draft)

            // Ask the PDF generator for in-memory preview data
            let data = try await PDFGenerator.makeInvoicePreview(from: snapshot)

            await MainActor.run {
                self.pdfData = data
                self.isGeneratingPDF = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isGeneratingPDF = false
            }
        }
    }

    // --- Load clients from DB ---
    private func loadClients() async {
        isLoadingClients = true; error = nil
        do {
            let rows = try await ClientService.fetchClients()
            await MainActor.run {
                clients = rows
                isLoadingClients = false
                if lockClient, draft.client == nil, let c = preselectedClient {
                    draft.client = c
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoadingClients = false
            }
        }
    }

    private func currency(_ value: Double, code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code.uppercased()
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}


// A friendlier card with item name, description, big qty buttons, currency field and per-line total
private struct LineItemCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var title: String
    @Binding var description: String
    @Binding var quantity: Int
    @Binding var unitPrice: Double
    var hideQuantityControls: Bool = false

    @FocusState private var focusedField: Field?
    enum Field { case title, desc, price }

    @State private var unitPriceText: String = ""

    private var lineTotal: Double { Double(quantity) * unitPrice }

    private func formattedString(from value: Double) -> String {
        let v = max(0, value)
        if v == 0 { return "" }
        if v.rounded(.towardZero) == v {
            return String(Int(v))
        } else {
            return String(format: "%.2f", v)
        }
    }

    private func parsePrice(_ s: String) -> Double {
        let cleaned = s.filter { ("0"..."9").contains($0) || $0 == "." }
        return Double(cleaned) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Item name
            TextField("Item name (e.g. Service call)", text: $title)
                .font(.headline)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .title)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            // Description
            TextField("Describe the work (optional)", text: $description, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .desc)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            // Quantity / price UI is shown only when not in "description-only" mode
            if !hideQuantityControls {
                VStack(alignment: .leading, spacing: 10) {
                    if quantity > 1 {
                        HStack(spacing: 0) {
                            Button { quantity = max(1, quantity - 1) } label: {
                                Image(systemName: "minus")
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.bordered)

                            Text("\(quantity)")
                                .font(.headline)
                                .frame(minWidth: 38)

                            Button { quantity = min(999, quantity + 1) } label: {
                                Image(systemName: "plus")
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.bordered)

                            Spacer(minLength: 8)

                            // Unit price editor (compact, trailing aligned)
                            TextField("Unit price", text: $unitPriceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                                .focused($focusedField, equals: .price)
                                .onChange(of: unitPriceText) { _, newVal in
                                    unitPrice = parsePrice(newVal)
                                }
                        }
                    } else {
                        HStack {
                            Spacer()
                            TextField("Price", text: $unitPriceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 180, alignment: .trailing)
                                .focused($focusedField, equals: .price)
                                .onChange(of: unitPriceText) { _, newVal in
                                    unitPrice = parsePrice(newVal)
                                }
                        }
                        Button("Add quantity") { quantity = 2 }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                            .padding(.leading, 2)
                    }
                    // Line total on a separate trailing row
                    HStack {
                        Spacer()
                        Text(lineTotal, format: .currency(code: "USD"))
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(minWidth: 96, alignment: .trailing)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0.35))
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if unitPriceText.isEmpty {
                unitPriceText = formattedString(from: unitPrice)
            }
        }
    }

    // Keyboard toolbar removed
}

// Compact summary row: shows just index badge, title/description (wrapped), and trailing total.
private struct LineItemSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let index: Int
    @Binding var item: LineItemDraft
    var onTapTextArea: (() -> Void)? = nil
    var onTapPriceArea: (() -> Void)? = nil

    private var lineTotal: Double { Double(max(1, item.quantity)) * max(0, item.unitPrice) }

    // Treat a very short description (<= 3 words and <= 24 chars) as a "title-like" label
    private var isShortDescription: Bool {
        let trimmed = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("\n") { return false }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("*") { return false }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        return words.count <= 3 && trimmed.count <= 24
    }

    // Unified display decision:
    // 1) If title exists -> use it (and show description only if not "short")
    // 2) If no title and short description -> promote description into title slot
    // 3) Else -> show description as normal body
    private var promotedTitle: String? {
        let t = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if isShortDescription { return item.description.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    private var shouldShowBodyDescription: Bool {
        let d = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.isEmpty else { return false }
        // If we promoted the description to title, don't render it again as body text.
        return !(promotedTitle != nil && d == promotedTitle)
    }

    // --- List parsing helpers for bullet lists in description ---
    private var listLines: [String]? {
        let trimmed = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Parse into bullet items if the description looks like a list.
        let items = parseListItems(from: trimmed)
        // Treat as list only if it’s clearly multiple items.
        return items.count >= 2 ? items : nil
    }

    private func parseListItems(from text: String) -> [String] {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }

        let cleaned: [String] = lines.compactMap { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }

            if t.hasPrefix("- ") { return String(t.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }
            if t.hasPrefix("• ") { return String(t.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }
            if t.hasPrefix("*") {
                let trimmed = t.drop(while: { $0 == "*" || $0 == " " })
                let s = String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }

            // If plain multi-line text (no markers), still allow it to become bullets.
            return t
        }

        return cleaned
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(index)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 6) {
                if let headline = promotedTitle {
                    Text(headline)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if shouldShowBodyDescription {
                    if let bullets = listLines {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(bullets.prefix(3)).indices, id: \.self) { idx in
                                let b = bullets[idx]
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 10, alignment: .leading)

                                    Text(b)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } else {
                        Text(item.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapTextArea?() }

            Spacer(minLength: 8)

            Text(lineTotal, format: .currency(code: "USD"))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 96, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture { onTapPriceArea?() }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0.35))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// Placeholder card shown when no items exist yet
private struct PlaceholderItemCard: View {
    @Environment(\.colorScheme) private var colorScheme
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color.blue.opacity(0.22), Color.indigo.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "tag").foregroundStyle(.green)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Item")
                        .font(.headline)
                    Text("Add your first item")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0.35))
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text("Add first item"))
    }
}


// Compact selected client card (used in New Invoice header)
private struct SelectedClientCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let client: ClientRow
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ClientAvatar.fillColor(hex: client.color_hex))

                Text(initials(from: client.name))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(client.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let email = client.email, !email.isEmpty {
                        Image(systemName: "envelope").foregroundStyle(.secondary).font(.caption)
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if (client.city?.isEmpty == false) || (client.state?.isEmpty == false) {
                    Text("\(client.city ?? "")\(client.city != nil && client.state != nil ? ", " : "")\(client.state ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0.35))
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .light ? 0.10 : 0.38),
            radius: colorScheme == .light ? 8 : 10,
            y: colorScheme == .light ? 4 : 6
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Client \(client.name)"))
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }
}

// Placeholder card when no client selected
// Placeholder card when no client selected — shows a default client preview
private struct PlaceholderClientCard: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 12) {
            // Avatar / initials bubble (CL for Client)
            ZStack {
                Circle().fill(Color.gray.opacity(0.35))
                Text("CL")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Client")
                    .font(.headline)
                HStack(spacing: 6) {
                    Image(systemName: "envelope")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("client@email.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Client address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0.35))
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .light ? 0.10 : 0.38),
            radius: colorScheme == .light ? 8 : 10,
            y: colorScheme == .light ? 4 : 6
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Default client placeholder. Tap to select a client."))
    }
}

// Styled due date row card
private struct DueDateRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let date: Date
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.15))
                Image(systemName: "calendar").foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Due date").font(.subheadline).foregroundStyle(.secondary)
                Text(date, style: .date).font(.headline)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0.35))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text("Due date \(date.formatted(date: .abbreviated, time: .omitted))"))
    }
}


// Combined card: Due date (left) + Invoice number (right)
private struct InvoiceDetailsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let date: Date
    let invoiceNumber: String
    let taxPercent: Double
    let taxAmount: Double
    var onTapDetails: () -> Void

    private static let abbrevFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMM d") // e.g., Dec 6
        return f
    }()

    private var formattedDue: String {
        Self.abbrevFormatter.string(from: date)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    var body: some View {
        Button(action: onTapDetails) {
            VStack(spacing: 0) {
                // Top row: two columns (Due date | Invoice #)
                HStack(spacing: 0) {
                    // LEFT: Due date label and value
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.9))
                            Image(systemName: "calendar").foregroundStyle(.white)
                        }
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Due date").font(.subheadline).foregroundStyle(.secondary)
                            Text(formattedDue).font(.headline)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    // Divider between columns
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 1)
                        .padding(.vertical, 10)

                    // RIGHT: Invoice number
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Invoice #").font(.subheadline).foregroundStyle(.secondary)
                            Text(invoiceNumber.isEmpty ? "—" : invoiceNumber)
                                .font(.headline)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                // Bottom row: Tax summary (only if there is tax)
                if taxPercent > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 1)

                    HStack {
                        Text("Tax")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f%%", taxPercent))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(currency(taxAmount))
                            .font(.headline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0.35))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Due date \(formattedDue). Invoice number \(invoiceNumber.isEmpty ? "unknown" : invoiceNumber).\(taxPercent > 0 ? " Tax \(String(format: "%.2f", taxPercent)) percent amount \(currency(taxAmount))." : "")"))
    }
}

// Compact, pretty "Notes" row that matches card styling and shows a preview
private struct NotesRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let noteText: String
    var onTap: () -> Void

    private var preview: String {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Add a note" }
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return firstLine.count > 40 ? String(firstLine.prefix(40)) + "…" : firstLine
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.85))
                    Image(systemName: "note.text").foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(preview)
                        .font(.headline)
                        .foregroundStyle(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .tertiary : .primary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0.35))
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Notes. Add a note." : "Notes. \(preview)"))
    }
}


// MARK: - Client Picker (half-sheet)
private struct ClientPickerSheet: View {
    let clients: [ClientRow]
    let isLoading: Bool
    @Binding var searchText: String
    var onCancel: () -> Void
    var onSelect: (ClientRow) -> Void
    var onCreateNew: () -> Void

    private var filtered: [ClientRow] {
        guard !searchText.isEmpty else { return clients }
        return clients.filter { c in
            c.name.localizedCaseInsensitiveContains(searchText) ||
            (c.email ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Clients
                Section {
                    if isLoading && clients.isEmpty {
                        ProgressView("Loading…")
                    } else if filtered.isEmpty {
                        Text("No clients found").foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { c in
                            Button {
                                onSelect(c)
                            } label: {
                                HStack(spacing: 12) {
                                    // Initials bubble
                                    ZStack {
                                        Circle()
                                            .fill(ClientAvatar.fillColor(hex: c.color_hex))

                                        Text(initials(from: c.name))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 36, height: 36)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if let email = c.email, !email.isEmpty {
                                            Text(email)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if (c.city?.isEmpty == false) || (c.state?.isEmpty == false) {
                                            Text("\(c.city ?? "")\(c.city != nil && c.state != nil ? ", " : "")\(c.state ?? "")")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("All clients")
                }
            }
            .navigationTitle("Client")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search clients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreateNew() }
                }
            }
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }
}



// View model to keep the item draft stable across view reloads
final class ItemDraftViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var quantity: Int = 1
    @Published var unitPrice: Double = 0
}

// MARK: - Item Picker (half-sheet) with live preview
private struct ItemPickerSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: ItemDraftViewModel
    var currentItemIndex: Int
    var presets: [String]
    var onAdd: (LineItemDraft) -> Void
    var onClose: () -> Void

    @State private var unitPriceText: String = ""

    private var lineTotal: Double {
        Double(max(1, viewModel.quantity)) * max(0, viewModel.unitPrice)
    }

    private func formattedString(from value: Double) -> String {
        let v = max(0, value)
        if v == 0 { return "" }
        if v.rounded(.towardZero) == v {
            return String(Int(v))
        } else {
            return String(format: "%.2f", v)
        }
    }

    private func parsePrice(_ s: String) -> Double {
        let cleaned = s.filter { ("0"..."9").contains($0) || $0 == "." }
        return Double(cleaned) ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                // Live item preview / editor
                Section {
                    ItemPreviewCard(
                        index: currentItemIndex,
                        title: $viewModel.title,
                        description: $viewModel.description,
                        quantity: $viewModel.quantity,
                        unitPrice: $viewModel.unitPrice
                    )
                    .listRowBackground(Color(.systemBackground))

                    if viewModel.quantity > 1 {
                        HStack {
                            Text("Line total")
                            Spacer()
                            Text(lineTotal, format: .currency(code: "USD"))
                                .font(.headline)
                        }
                    }
                } header: {
                    Text("New item")
                } footer: {
                    Text("Give the item a name. Description is optional. Adjust quantity and price, then tap Add.")
                }

                // Quick picks that prefill the preview
                Section("Quick picks") {
                    ForEach(presets, id: \.self) { p in
                        Button {
                            applyPreset(p)
                        } label: {
                            HStack {
                                Image(systemName: "tag.fill").foregroundStyle(.blue)
                                Text(p).font(.headline)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let toAdd = LineItemDraft(
                            title: viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: viewModel.description,
                            quantity: viewModel.quantity,
                            unitPrice: viewModel.unitPrice
                        )
                        let hasContent = !toAdd.title.isEmpty ||
                                         !toAdd.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        guard hasContent else { return }
                        guard toAdd.unitPrice > 0 else { return }
                        onAdd(toAdd)
                    }
                    .disabled(
                        (viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                         viewModel.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || viewModel.unitPrice <= 0
                    )
                }
            }
            .onAppear {
                unitPriceText = formattedString(from: viewModel.unitPrice)
            }
        }
    }

    private func applyPreset(_ p: String) {
        viewModel.title = p
    }
}

// Floating label single-line field
private struct FloatingField: View {
    let title: String, placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .stroke(focused ? Color.accentColor : .secondary.opacity(0.2))
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))

            TextField(placeholder, text: $text)
                .padding(.top, 14)
                .padding(.horizontal, 12)
                .focused($focused)
                .textSelection(.enabled)

            if focused || !text.isEmpty {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .background(Color(.systemBackground))
                    .offset(y: -12)
            }
        }
        .frame(height: 50)
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

// Floating label multi-line field
private struct FloatingMultilineField: View {
    let title: String, placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if focused || !text.isEmpty {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focused ? Color.accentColor : .secondary.opacity(0.2))
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))

                TextEditor(text: $text)
                    .focused($focused)
                    .frame(minHeight: minHeight)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .textSelection(.enabled)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

// Compact editor used in the item picker to preview the item before adding (refined design)
private struct ItemPreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let index: Int   // kept for API compatibility, not rendered
    @Binding var title: String
    @Binding var description: String
    @Binding var quantity: Int
    @Binding var unitPrice: Double

    // MARK: - Styling (light/dark safe)
    private var fieldFill: Color { Color(.systemBackground) }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }

    private var subtleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    private var accentFill: Color {
        colorScheme == .dark ? Color.accentColor.opacity(0.28) : Color.accentColor.opacity(0.16)
    }

    @FocusState private var focusedField: Field?
    enum Field { case title, desc, price }

    @State private var isTitleOpen = false
    @State private var isDescOpen  = false
    @State private var unitPriceText: String = ""
    @State private var isListOpen  = false
    @State private var listItems: [String] = []
    @State private var newListItemText: String = ""

    private func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func formattedString(from value: Double) -> String {
        let v = max(0, value)
        if v == 0 { return "" }
        if v.rounded(.towardZero) == v {
            return String(Int(v))
        } else {
            return String(format: "%.2f", v)
        }
    }

    private func parsePrice(_ s: String) -> Double {
        let cleaned = s.filter { ("0"..."9").contains($0) || $0 == "." }
        return Double(cleaned) ?? 0
    }

    private func parseListItems(from description: String) -> [String] {
        let lines = description
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
        let cleaned = lines.compactMap { line -> String? in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            if t.hasPrefix("- ") { return String(t.dropFirst(2)) }
            if t.hasPrefix("• ") { return String(t.dropFirst(2)) }
            if t.hasPrefix("*") {
                let trimmed = t.drop(while: { $0 == "*" || $0 == " " })
                return trimmed.isEmpty ? nil : String(trimmed)
            }
            // If the user typed plain lines, treat them as list items.
            return t
        }
        return cleaned.isEmpty ? [""] : cleaned
    }

    private func formattedListDescription(from items: [String]) -> String {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        return cleaned.map { "- \($0)" }.joined(separator: "\n")
    }

    private func syncListItemsFromDescription() {
        listItems = parseListItems(from: description)

        // If it's basically empty, start with no visible items.
        if listItems.count == 1,
           listItems.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            listItems = []
        }
    }

    private func syncDescriptionFromListItems() {
        // Behind the scenes, store list items into `description` as "- item" lines.
        // The UI never shows this raw formatting.
        description = formattedListDescription(from: listItems)
    }

    private func addListItem() {
        let t = newListItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            listItems.append(t)
            newListItemText = ""
        }

        // Keep backend description updated without exposing formatting to the user.
        syncDescriptionFromListItems()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // TITLE — collapsible button → field
            if isTitleOpen {
                FloatingField(title: "Item", placeholder: "Title (optional)", text: $title)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isTitleOpen = true }
                } label: {
                    HStack {
                        Image(systemName: "text.cursor")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add title" : String(title.prefix(60)))
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(subtleFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(strokeColor)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // DESCRIPTION — collapsible button → multiline editor (no sheet)
            if isDescOpen {
                FloatingMultilineField(
                    title: "Description",
                    placeholder: "Describe the work (optional)",
                    text: $description,
                    minHeight: 120
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isDescOpen = true }
                } label: {
                    HStack {
                        Image(systemName: "square.and.pencil")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Text(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add description" : String(description.prefix(60)))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accentFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(strokeColor)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // LIST — optional bullet list builder (stores into `description` behind the scenes)
            if isListOpen {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("List")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Done") {
                            // Persist list → description on close (behind the scenes)
                            syncDescriptionFromListItems()
                            withAnimation(.easeInOut(duration: 0.18)) { isListOpen = false }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 10) {
                        // Existing items (styled)
                        ForEach(listItems.indices, id: \.self) { idx in
                            HStack(spacing: 12) {
                                // Accent badge
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.18),
                                                    Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.10)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )

                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .frame(width: 32, height: 32)

                                Text(listItems[idx])
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer()

                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        listItems.remove(at: idx)
                                    }
                                    syncDescriptionFromListItems()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .padding(8)
                                        .background(
                                            Circle()
                                                .fill(Color.black.opacity(colorScheme == .dark ? 0.28 : 0.06))
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Remove list item"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.06),
                                                        Color.clear
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(strokeColor)
                                    )
                            )
                            .shadow(
                                color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06),
                                radius: colorScheme == .dark ? 10 : 6,
                                y: colorScheme == .dark ? 6 : 3
                            )
                        }

                        // One input field (type here) + quick add button
                        HStack(spacing: 12) {
                            TextField("List item", text: $newListItemText)
                                .textInputAutocapitalization(.sentences)
                                .textSelection(.enabled)
                                .submitLabel(.done)
                                .onSubmit { addListItem() }

                            Button { addListItem() } label: {
                                ZStack {
                                    Circle().fill(
                                        LinearGradient(
                                            colors: [Color.green.opacity(0.70), Color.indigo.opacity(0.18)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    Image(systemName: "plus")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Add list item"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(fieldFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(strokeColor)
                                )
                        )

                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    // Initialize from current description so the list reflects existing content.
                    syncListItemsFromDescription()
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isListOpen = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Text("Add list")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(subtleFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(strokeColor)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // PRICE — always inside the card so it visually belongs to the item
            VStack(alignment: .leading, spacing: 8) {
                Text(quantity > 1 ? "Unit price" : "Price")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Spacer()
                    TextField("0.00", text: $unitPriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 180, alignment: .trailing)
                        .focused($focusedField, equals: .price)
                        .onChange(of: unitPriceText) { _, newVal in
                            unitPrice = parsePrice(newVal)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(strokeColor)
                        )
                )
            }
            .onChange(of: unitPrice) { _, newVal in
                // Keep the text field in sync when unitPrice changes via keyboard toolbar buttons
                if focusedField != .price {
                    unitPriceText = formattedString(from: newVal)
                }
            }

            // QUANTITY — keep footprint stable (no swapping views that change row height)
            ZStack {
                // Add Quantity button (shown when quantity == 1)
                Button {
                    withAnimation(.snappy(duration: 0.22)) { quantity = 2 }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.headline).foregroundStyle(Color.accentColor)
                        Text("Add Quantity").font(.headline).foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accentFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(strokeColor)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(quantity <= 1 ? 1 : 0)
                .allowsHitTesting(quantity <= 1)

                // Quantity pill (shown when quantity > 1)
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            quantity = max(1, quantity - 1)
                        }
                    } label: {
                        HStack {
                            Spacer(minLength: 0)
                            Image(systemName: "minus")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 64, height: 44)          // BIG tap target
                        .contentShape(Rectangle())              // makes the whole area tappable
                    }
                    .buttonStyle(.plain)

                    Text("\(quantity)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(minWidth: 32)
                        .contentTransition(.numericText()) // smooth number change

                    Button {
                        withAnimation(.snappy(duration: 0.10)) {
                            quantity = min(999, quantity + 1)
                        }
                    } label: {
                        HStack {
                            Spacer(minLength: 0)
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 64, height: 44)          // BIG tap target
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(subtleFill)
                        .overlay(
                            Capsule().strokeBorder(strokeColor)
                        )
                )
                .opacity(quantity > 1 ? 1 : 0)
                .allowsHitTesting(quantity > 1)
            }
            .frame(height: 52) // <- forces stable row height, kills the jitter
            .animation(.snappy(duration: 0.22), value: quantity)
        }
        .padding(.vertical, 4)
        .padding(.vertical, 8)
        .highPriorityGesture(
            DragGesture(minimumDistance: 16).onEnded { _ in
                if isBlank(title) { withAnimation(.easeInOut(duration: 0.2)) { isTitleOpen = false } }
                if isBlank(description) { withAnimation(.easeInOut(duration: 0.2)) { isDescOpen  = false } }
                if isListOpen, formattedListDescription(from: listItems).isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) { isListOpen = false }
                }
            }
        )
        .onAppear {
            if unitPriceText.isEmpty {
                unitPriceText = formattedString(from: unitPrice)
            }
            // Keep list editor consistent with whatever description currently contains.
            syncListItemsFromDescription()
        }
    }

    // Keyboard toolbar removed
}

// Card-styled Add button for the Items section
private struct AddItemCardButton: View {
    @Environment(\.colorScheme) private var colorScheme
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(
                        colors: [Color.green.opacity(0.70), Color.indigo.opacity(0.18)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "plus").foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                Text("Add")
                    .font(.headline)
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0.35))
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text("Add item"))
    }
}

// Groups Client + Invoice Details + Notes into a single white card container
private struct TopInvoiceCard: View {
    let selectedClient: ClientRow?
    let lockClient: Bool
    let isLoading: Bool
    var onTapClient: () -> Void

    let date: Date
    let invoiceNumber: String
    let taxPercent: Double
    let taxAmount: Double
    var onTapDetails: () -> Void

    let noteText: String
    var onTapNotes: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onTapClient) {
                if let selected = selectedClient {
                    SelectedClientCard(client: selected)
                } else {
                    PlaceholderClientCard()
                }
            }
            .buttonStyle(.plain)
            .disabled(lockClient || isLoading)

            InvoiceDetailsCard(
                date: date,
                invoiceNumber: invoiceNumber,
                taxPercent: taxPercent,
                taxAmount: taxAmount,
                onTapDetails: onTapDetails
            )

            // Notes preview row (tapping opens details sheet to edit notes)
            NotesRow(noteText: noteText, onTap: onTapNotes)
        }
    }
}

// A reusable swipe-to-delete row that works inside VStacks (not only List rows).
private struct SwipeableItemRow<Content: View>: View {
    @State private var offsetX: CGFloat = 0          // current drag offset of the row
    @State private var isHorizontalDrag: Bool = false
    let revealWidth: CGFloat                         // how far the row moves to reveal the button
    let swipeToEndThreshold: CGFloat                 // threshold distance for full swipe-to-delete

    let isEnabled: Bool
    let highlight: Bool
    let onDeleteTap: () -> Void                      // called when the red Delete button is tapped
    let onSwipeToEnd: (() -> Void)?                  // called when user swipes far enough left to auto-delete
    @ViewBuilder var content: () -> Content

    init(
        isEnabled: Bool = true,
        highlight: Bool = false,
        revealWidth: CGFloat = 96,
        onDeleteTap: @escaping () -> Void,
        onSwipeToEnd: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isEnabled = isEnabled
        self.highlight = highlight
        self.revealWidth = revealWidth
        self.swipeToEndThreshold = revealWidth * 2.5   // ~2.5x reveal width ≈ strong full-swipe gesture
        self.onDeleteTap = onDeleteTap
        self.onSwipeToEnd = onSwipeToEnd
        self.content = content
    }

    var body: some View {
        ZStack {
            // Highlight background (underlying highlight layer)
            if highlight {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.red.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.red.opacity(0.75), lineWidth: 1)
                    )
            }
            // Red destructive pill behind the row
            HStack {
                Spacer()
                Button(role: .destructive, action: onDeleteTap) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 80) // larger tap target
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.red))
                .foregroundStyle(.white)
                .padding(.trailing, 8)
                .contentShape(Rectangle()) // make the whole capsule area tappable
            }
            .opacity(isEnabled ? 1 : 0)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if isEnabled {
                        onDeleteTap()
                    }
                }
            )
            // Foreground content that slides
            content()
                .offset(x: offsetX)
                .gesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            guard isEnabled else { return }

                            let dx = value.translation.width
                            let dy = value.translation.height

                            // Decide if this drag should be treated as a horizontal swipe.
                            if !isHorizontalDrag {
                                if abs(dx) > abs(dy), abs(dx) > 6 {
                                    // Lock into horizontal mode once we are clearly moving sideways.
                                    isHorizontalDrag = true
                                } else {
                                    // Mostly vertical so far: let the parent scroll view handle it.
                                    return
                                }
                            }

                            // Only handle the drag if we locked into horizontal mode.
                            guard isHorizontalDrag else { return }

                            if dx < 0 {
                                // Swiping left: allow dragging past the reveal width so the user can swipe it off-screen
                                offsetX = dx
                            } else {
                                // Swiping right: do not allow positive offset
                                offsetX = 0
                            }
                        }
                        .onEnded { value in
                            guard isEnabled else { return }

                            defer {
                                // Always reset for the next gesture
                                isHorizontalDrag = false
                            }

                            // If this drag never became a horizontal swipe, treat it as a scroll gesture.
                            guard isHorizontalDrag else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                    offsetX = 0
                                }
                                return
                            }

                            // First, if the row was dragged far enough, treat it as a full swipe-to-delete.
                            if let swipeToEnd = onSwipeToEnd, offsetX < -swipeToEndThreshold {
                                swipeToEnd()
                                return
                            }

                            // Otherwise, snap to either the revealed state or back closed.
                            let shouldOpen = offsetX < -revealWidth * 0.5
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                offsetX = shouldOpen ? -revealWidth : 0
                            }
                        }
                )
                .onTapGesture {
                    // If open and tapped, close it (when hit-testing is enabled)
                    if offsetX != 0 {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { offsetX = 0 }
                    }
                }
                .onChange(of: isEnabled) { _, enabled in
                    if !enabled {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { offsetX = 0 }
                    }
                }
        }
    }
}

// Groups all item rows in a single white card and keeps the Add button inside
private struct ItemsGroupCard: View {
    @Binding var items: [LineItemDraft]
    @Binding var expandedItemIDs: Set<UUID>
    var onAddTap: () -> Void

    @State private var actionItemID: UUID? = nil
    @State private var descriptionOnlyIDs: Set<UUID> = []
    private enum ActionMode { case descQty, priceQty }
    @State private var actionMode: ActionMode = .descQty
    @State private var priceDraft: [UUID: String] = [:]
    @State private var rowVersion: [UUID: Int] = [:]

    private func unformattedString(from value: Double) -> String {
        let v = max(0, value)
        if v.rounded(.towardZero) == v {
            return String(Int(v))
        } else {
            return String(format: "%.2f", v)
        }
    }
    private func parsePrice(_ s: String) -> Double? {
        let cleaned = s.filter { ("0"..."9").contains($0) || $0 == "." }
        return Double(cleaned)
    }
    private func openAction(for id: UUID, mode: ActionMode) {
        withAnimation(.easeInOut(duration: 0.2)) {
            actionItemID = id
            actionMode = mode
            expandedItemIDs.removeAll()
            descriptionOnlyIDs.removeAll()
        }
    }
    private func closeAction(commit: Bool) {
        guard let id = actionItemID else { return }
        if commit, actionMode == .priceQty, let s = priceDraft[id], let v = parsePrice(s),
           let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].unitPrice = v
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            actionItemID = nil
        }
    }
    private func resetSwipe(for id: UUID) {
        rowVersion[id, default: 0] += 1
    }
    private func deleteItem(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }

        _ = withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            items.remove(at: idx)
        }

        if actionItemID == id {
            actionItemID = nil
        }
        expandedItemIDs.remove(id)
        descriptionOnlyIDs.remove(id)
    }

    var body: some View {
        let content = VStack(spacing: 10) {
            if items.isEmpty {
                PlaceholderItemCard { onAddTap() }
            } else {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    let isEditingThis = (actionItemID == item.id) || expandedItemIDs.contains(item.id)
                    let highlightThis = false

                    ZStack {
                        SwipeableItemRow(
                            isEnabled: !isEditingThis,
                            highlight: highlightThis,
                            onDeleteTap: {
                                deleteItem(id: item.id)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            },
                            onSwipeToEnd: {
                                deleteItem(id: item.id)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                        ) {
                            VStack(spacing: 6) {
                                // Summary row
                                LineItemSummaryCard(
                                    index: i + 1,
                                    item: $items[i],
                                    onTapTextArea: {
                                        if actionItemID == item.id && actionMode == .descQty {
                                            closeAction(commit: true)
                                        } else {
                                            openAction(for: item.id, mode: .descQty)
                                        }
                                    },
                                    onTapPriceArea: {
                                        if actionItemID == item.id && actionMode == .priceQty {
                                            closeAction(commit: true)
                                        } else {
                                            priceDraft[item.id] = priceDraft[item.id] ?? unformattedString(from: items[i].unitPrice)
                                            openAction(for: item.id, mode: .priceQty)
                                        }
                                    }
                                )

                                // Inline action strip
                                if actionItemID == item.id {
                                    switch actionMode {
                                    case .descQty:
                                        HStack(spacing: 10) {
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    actionItemID = nil
                                                    expandedItemIDs = [item.id]
                                                    descriptionOnlyIDs = [item.id]
                                                }
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "square.and.pencil")
                                                        .font(.body.weight(.semibold))
                                                    Text("Description")
                                                        .font(.subheadline.weight(.semibold))
                                                    Spacer(minLength: 0)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(.thinMaterial)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .frame(maxWidth: .infinity)

                                            HStack(spacing: 12) {
                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        items[i].quantity = max(1, items[i].quantity - 1)
                                                    }
                                                } label: { Image(systemName: "minus").font(.body.weight(.semibold)) }
                                                .buttonStyle(.plain)

                                                Text("\(max(1, items[i].quantity))×")
                                                    .font(.subheadline.weight(.semibold))
                                                    .monospacedDigit()

                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        items[i].quantity = min(999, items[i].quantity + 1)
                                                    }
                                                } label: { Image(systemName: "plus").font(.body.weight(.semibold)) }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(Color.blue.opacity(0.12))
                                            )
                                            .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .transition(.move(edge: .top).combined(with: .opacity))

                                    case .priceQty:
                                        HStack(spacing: 10) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "dollarsign")
                                                    .font(.body.weight(.semibold))
                                                TextField("0.00", text: Binding(
                                                    get: { priceDraft[item.id] ?? unformattedString(from: items[i].unitPrice) },
                                                    set: { newVal in
                                                        priceDraft[item.id] = newVal
                                                    }
                                                ))
                                                .keyboardType(.decimalPad)
                                                .multilineTextAlignment(.trailing)
                                                .onAppear {
                                                    priceDraft[item.id] = unformattedString(from: items[i].unitPrice)
                                                }
                                                .onSubmit {
                                                    if let s = priceDraft[item.id], let v = parsePrice(s) {
                                                        items[i].unitPrice = v
                                                    }
                                                    closeAction(commit: false)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(.thinMaterial)
                                            )
                                            .frame(maxWidth: .infinity)
                                            .contentShape(Rectangle())
                                            .onTapGesture { } // keep taps local so the container tap-to-close doesn't fire

                                            HStack(spacing: 12) {
                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        items[i].quantity = max(1, items[i].quantity - 1)
                                                    }
                                                } label: { Image(systemName: "minus").font(.body.weight(.semibold)) }
                                                .buttonStyle(.plain)

                                                Text("\(max(1, items[i].quantity))×")
                                                    .font(.subheadline.weight(.semibold))
                                                    .monospacedDigit()

                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        items[i].quantity = min(999, items[i].quantity + 1)
                                                    }
                                                } label: { Image(systemName: "plus").font(.body.weight(.semibold)) }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(Color.blue.opacity(0.12))
                                            )
                                            .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                }

                                // Full inline editor (when expanded explicitly)
                                if expandedItemIDs.contains(item.id) {
                                    LineItemCard(
                                        title: $items[i].title,
                                        description: $items[i].description,
                                        quantity: $items[i].quantity,
                                        unitPrice: $items[i].unitPrice,
                                        hideQuantityControls: descriptionOnlyIDs.contains(item.id)
                                    )
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }
                        .id("\(item.id.uuidString)-\(rowVersion[item.id, default: 0])")
                    }
                }
            }

            // Add button
            AddItemCardButton(onTap: onAddTap)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)

                    // Treat primarily vertical drags as "scroll" gestures:
                    if dy > dx && dy > 24 {
                        // Close any inline editors
                        if actionItemID != nil {
                            closeAction(commit: true)
                        }
                        descriptionOnlyIDs.removeAll()

                        // Also reset any swipe offsets so half‑swiped rows snap back
                        for id in items.map(\.id) {
                            resetSwipe(for: id)
                        }
                    }
                }
        )
        .padding(.vertical, 4)

        return content
            .contentShape(Rectangle())
    }
}

private struct TotalsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let subTotal: Double
    let taxAmount: Double
    let total: Double
    let currencyCode: String

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode.uppercased()
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    var body: some View {
        VStack(spacing: 0) {
            row("Subtotal", currency(subTotal))
            Divider().padding(.horizontal, 14)
            row("Tax", currency(taxAmount))
            // Bold divider before Total
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 2)
                .padding(.top, 8)
                .padding(.horizontal, 14)
            row("Total", currency(total), isBold: true)
                .padding(.bottom, 6)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    Color.black.opacity(colorScheme == .light ? 0.22 : 0.40)
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .light ? 0.10 : 0.32),
            radius: colorScheme == .light ? 8 : 10,
            y: colorScheme == .light ? 4 : 6
        )
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String, isBold: Bool = false) -> some View {
        HStack {
            Text(title).font(isBold ? .headline.weight(.semibold) : .body)
            Spacer()
            Text(value).font(isBold ? .headline.weight(.semibold) : .body)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}


struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(data: data)
    }
}

#Preview("Item Picker – Dark") {
    let vm = ItemDraftViewModel()

    return ItemPickerSheet(
        viewModel: vm,
        currentItemIndex: 1,
        presets: ["Service call", "Labor hour", "Materials", "Cleanup"],
        onAdd: { _ in },
        onClose: { }
    )
    .preferredColorScheme(.dark)
}

#Preview("Item Picker – Light") {
    let vm = ItemDraftViewModel()

    return ItemPickerSheet(
        viewModel: vm,
        currentItemIndex: 1,
        presets: ["Service call", "Labor hour", "Materials", "Cleanup"],
        onAdd: { _ in },
        onClose: { }
    )
    .preferredColorScheme(.light)
}


private extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
