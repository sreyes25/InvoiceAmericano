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

// Global UI spacers for consistent structure
private enum UI {
    static let rowH: CGFloat = 14      // horizontal insets for card rows
    static let rowV: CGFloat = 8       // vertical insets for card rows
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

struct NewInvoiceView: View {
    var preselectedClient: ClientRow? = nil
    var lockClient: Bool = false
    var onSaved: (InvoiceDraft) -> Void

    @Environment(\.dismiss) private var dismiss
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
        return draft.total > 0 && draft.items.contains {
            !$0.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty &&
            $0.unitPrice > 0 &&
            $0.quantity > 0
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
                // --- Client + Invoice Info ---
                Section("Invoice") {
                    // Client selector (opens half-sheet list)
                    if let selected = draft.client {
                        Button { showClientPicker = true } label: {
                            SelectedClientCard(client: selected)
                        }
                        .buttonStyle(.plain)
                        .disabled(lockClient || isLoadingClients)
                        .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                    } else {
                        Button { showClientPicker = true } label: {
                            PlaceholderClientCard()
                        }
                        .buttonStyle(.plain)
                        .disabled(lockClient || isLoadingClients)
                        .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                    }

                    InvoiceDetailsCard(
                        date: draft.dueDate,
                        invoiceNumber: draft.number,
                        taxPercent: draft.taxPercent,
                        taxAmount: draft.taxAmount,
                        onTapDetails: { showDueDateSheet = true }
                    )
                    .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                }

                // --- Line Items ---
                // MARK: - Items
                Section("Items") {
                    // If no items yet, show a friendly placeholder card that opens the picker
                    if draft.items.isEmpty {
                        PlaceholderItemCard {
                            itemVM.title = ""
                            itemVM.description = ""
                            itemVM.quantity = 1
                            itemVM.unitPrice = 0
                            showItemPicker = true
                        }
                        .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                    }

                    // Line items (compact summary by default). Tap to expand and edit.
                    ForEach(draft.items.indices, id: \.self) { i in
                        let item = draft.items[i]
                        if expandedItemIDs.contains(item.id) {
                            // Full editor
                            LineItemCard(
                                title: $draft.items[i].title,
                                description: $draft.items[i].description,
                                quantity: $draft.items[i].quantity,
                                unitPrice: $draft.items[i].unitPrice
                            )
                            .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                            .onTapGesture { expandedItemIDs.remove(item.id) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    draft.items.remove(at: i)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    let copy = LineItemDraft(title: item.title, description: item.description, quantity: item.quantity, unitPrice: item.unitPrice)
                                    draft.items.insert(copy, at: min(i + 1, draft.items.count))
                                } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                                .tint(.blue)
                            }
                        } else {
                            // Compact summary row showing index badge, wrapped text, and trailing total
                            LineItemSummaryCard(index: i + 1, item: $draft.items[i])
                                .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                                .onTapGesture { expandedItemIDs.insert(item.id) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { draft.items.remove(at: i) } label: { Label("Delete", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        let copy = LineItemDraft(title: item.title, description: item.description, quantity: item.quantity, unitPrice: item.unitPrice)
                                        draft.items.insert(copy, at: min(i + 1, draft.items.count))
                                    } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                                    .tint(.blue)
                                }
                        }
                    }
                    .onMove { from, to in draft.items.move(fromOffsets: from, toOffset: to) }
                    .onDelete { draft.items.remove(atOffsets: $0) }

                    // Add item button
                    AddItemCardButton {
                        itemVM.title = ""
                        itemVM.description = ""
                        itemVM.quantity = 1
                        itemVM.unitPrice = 0
                        showItemPicker = true
                    }
                    .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                }

                // Notes quick access (no title section) — styled row with preview
                Section {
                    NotesRow(noteText: draft.notes) {
                        showDueDateSheet = true
                    }
                    .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                }

                // --- Totals ---
                Section("Totals") {
                    Color.clear
                        .frame(height: 1)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: ViewYPreferenceKey.self,
                                                value: proxy.frame(in: .named("formScroll")).minY)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: 0, trailing: UI.rowH))
                    HStack { Text("Subtotal"); Spacer(); Text(currency(draft.subTotal, code: draft.currency)) }
                        .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                    HStack { Text("Tax"); Spacer(); Text(currency(draft.taxAmount, code: draft.currency)) }
                        .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                    HStack { Text("Total").bold(); Spacer(); Text(currency(draft.total, code: draft.currency)).bold() }
                        .listRowInsets(EdgeInsets(top: UI.rowV, leading: UI.rowH, bottom: UI.rowV, trailing: UI.rowH))
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSaved(draft)
                        dismiss()
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
            // Collapse any expanded item editors when the user starts dragging/scrolling
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        if !expandedItemIDs.isEmpty {
                            expandedItemIDs.removeAll()
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
                        draft.items.append(newItem)
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
                        if draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           let footer = d.footerNotes, !footer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft.notes = footer
                        }
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
    @Binding var title: String
    @Binding var description: String
    @Binding var quantity: Int
    @Binding var unitPrice: Double

    @FocusState private var focusedField: Field?
    enum Field { case title, desc, price }

    static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    private var lineTotal: Double { Double(quantity) * unitPrice }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Item name
            TextField("Item name (e.g. Service call)", text: $title)
                .font(.headline)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .title)
                .fixedSize(horizontal: false, vertical: true)

            // Description
            TextField("Describe the work (optional)", text: $description, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .desc)
                .fixedSize(horizontal: false, vertical: true)

            // Quantity and pricing layout
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
                        TextField("Unit price", value: $unitPrice, formatter: Self.currencyFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                            .focused($focusedField, equals: .price)
                            .toolbar { keyboardToolbar }
                    }
                } else {
                    HStack {
                        Spacer()
                        TextField("Price", value: $unitPrice, formatter: Self.currencyFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 180, alignment: .trailing)
                            .focused($focusedField, equals: .price)
                            .toolbar { keyboardToolbar }
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // Small “calculator-ish” keyboard toolbar
    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button("−10") { unitPrice = max(0, unitPrice - 10) }
            Button("−1")  { unitPrice = max(0, unitPrice - 1)  }
            Spacer()
            Button("+1")  { unitPrice += 1 }
            Button("+10") { unitPrice += 10 }
            Button("Done") { focusedField = nil }
                .font(.headline)
        }
    }
}

// Compact summary row: shows just index badge, title/description (wrapped), and trailing total.
private struct LineItemSummaryCard: View {
    let index: Int
    @Binding var item: LineItemDraft

    private var lineTotal: Double { Double(max(1, item.quantity)) * max(0, item.unitPrice) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(index)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 8)

            Text(lineTotal, format: .currency(code: "USD"))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// Placeholder card shown when no items exist yet
private struct PlaceholderItemCard: View {
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color.blue.opacity(0.22), Color.indigo.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "tag").foregroundStyle(.blue)
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
                    .strokeBorder(Color.black.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text("Add first item"))
    }
}


// Compact selected client card (used in New Invoice header)
private struct SelectedClientCard: View {
    let client: ClientRow
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color.blue.opacity(0.22), Color.indigo.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(initials(from: client.name))
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(client.name).font(.headline)
                HStack(spacing: 6) {
                    if let email = client.email, !email.isEmpty {
                        Image(systemName: "envelope").foregroundStyle(.secondary).font(.caption)
                        Text(email).font(.caption).foregroundStyle(.secondary)
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
                .strokeBorder(Color.black.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
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
    var body: some View {
        HStack(spacing: 12) {
            // Avatar / initials bubble (CL for Client)
            ZStack {
                Circle().fill(LinearGradient(colors: [Color.blue.opacity(0.22), Color.indigo.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("CL")
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
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
                .strokeBorder(Color.black.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Default client placeholder. Tap to select a client."))
    }
}

// Styled due date row card
private struct DueDateRow: View {
    let date: Date
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.15))
                Image(systemName: "calendar").foregroundStyle(.blue)
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
                .strokeBorder(Color.black.opacity(0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text("Due date \(date.formatted(date: .abbreviated, time: .omitted))"))
    }
}


// Combined card: Due date (left) + Invoice number (right)
private struct InvoiceDetailsCard: View {
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
                            RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.15))
                            Image(systemName: "calendar").foregroundStyle(.blue)
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
                .strokeBorder(Color.black.opacity(0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Due date \(formattedDue). Invoice number \(invoiceNumber.isEmpty ? "unknown" : invoiceNumber).\(taxPercent > 0 ? " Tax \(String(format: "%.2f", taxPercent)) percent amount \(currency(taxAmount))." : "")"))
    }
}

// Compact, pretty "Notes" row that matches card styling and shows a preview
private struct NotesRow: View {
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
                    RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.15))
                    Image(systemName: "note.text").foregroundStyle(.blue)
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
                    .strokeBorder(Color.black.opacity(0.05))
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
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.blue.opacity(0.22), Color.indigo.opacity(0.18)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                        Text(initials(from: c.name))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.blue)
                                    }
                                    .frame(width: 36, height: 36)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name).font(.headline)
                                        if let email = c.email, !email.isEmpty {
                                            Text(email).font(.caption).foregroundStyle(.secondary)
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
    @ObservedObject var viewModel: ItemDraftViewModel
    var currentItemIndex: Int
    var presets: [String]
    var onAdd: (LineItemDraft) -> Void
    var onClose: () -> Void

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    private var lineTotal: Double {
        Double(max(1, viewModel.quantity)) * max(0, viewModel.unitPrice)
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
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    if viewModel.quantity > 1 {
                        // Read-only total when using quantity
                        HStack {
                            Text("Line total")
                            Spacer()
                            Text(lineTotal, format: .currency(code: "USD"))
                            .font(.headline)
                        }
                    } else {
                        // Editable price when there is no quantity
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Price")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Spacer()
                                TextField("0.00", value: $viewModel.unitPrice, formatter: ItemPickerSheet.currencyFormatter)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 180, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.2))
                                    .background(
                                        RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground))
                                    )
                            )
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
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        var toAdd = LineItemDraft(
                            title: viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: viewModel.description,
                            quantity: viewModel.quantity,
                            unitPrice: viewModel.unitPrice
                        )
                        guard !toAdd.title.isEmpty else { return }
                        guard toAdd.unitPrice > 0 else { return }
                        onAdd(toAdd)
                    }
                    .disabled(viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.unitPrice <= 0)
                }
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
    let index: Int   // kept for API compatibility, not rendered
    @Binding var title: String
    @Binding var description: String
    @Binding var quantity: Int
    @Binding var unitPrice: Double

    @FocusState private var focusedField: Field?
    enum Field { case title, desc, price }

    @State private var showDescEditor = false
    @State private var descDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ITEM NAME — floating label field
            FloatingField(title: "Item", placeholder: "Title", text: $title)

            // DESCRIPTION — open a modal editor from a full-width button
            Button {
                descDraft = description
                showDescEditor = true
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add description" : String(description.prefix(60)))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.tint)
                        .animation(.easeInOut(duration: 0.25), value: UUID())
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDescEditor) {
                NavigationStack {
                    VStack {
                        TextEditor(text: $descDraft)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                    }
                    .navigationTitle("Description")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDescEditor = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { description = descDraft; showDescEditor = false } }
                    }
                }
            }

            // PRICE — only show when quantity > 1 (per-unit editor lives inside the card)
            if quantity > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unit price")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Spacer()
                        TextField("0.00", value: $unitPrice, formatter: LineItemCard.currencyFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 180, alignment: .trailing)
                            .focused($focusedField, equals: .price)
                            .toolbar { keyboardToolbar }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2))
                            .background(
                                RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground))
                            )
                    )
                }
            }

            // QUANTITY — single pill button or unified stepper
            if quantity <= 1 {
                Button {
                    quantity = 2
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Add Quantity")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.tint)
                            .animation(.easeInOut(duration: 0.25), value: UUID())
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add quantity")
            } else {
                HStack(spacing: 8) {
                    Button {
                        quantity = max(1, quantity - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    Text("\(quantity)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 32)

                    Button {
                        quantity = min(999, quantity + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.tint)
                        .animation(.easeInOut(duration: 0.25), value: UUID())
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Quantity \(quantity)")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // Small “calculator-ish” keyboard toolbar
    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button("−10") { unitPrice = max(0, unitPrice - 10) }
            Button("−1")  { unitPrice = max(0, unitPrice - 1)  }
            Spacer()
            Button("+1")  { unitPrice += 1 }
            Button("+10") { unitPrice += 10 }
            Button("Done") { focusedField = nil }
                .font(.headline)
        }
    }
}

// Card-styled Add button for the Items section
private struct AddItemCardButton: View {
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(
                        colors: [Color.blue.opacity(0.22), Color.indigo.opacity(0.18)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "plus").foregroundStyle(.blue)
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
                    .strokeBorder(Color.black.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text("Add item"))
    }
}
