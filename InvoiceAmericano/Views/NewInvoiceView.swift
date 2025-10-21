//
//  NewInvoiceView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/6/25.
//

import SwiftUI
import Foundation

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
        Form {
            // --- Client + Invoice Info ---
            Section("Invoice") {
                Picker("Client", selection: Binding<ClientRow?>(
                    get: { draft.client },
                    set: { draft.client = $0 }
                )) {
                    if isLoadingClients {
                        Text("Loading…").tag(Optional<ClientRow>.none)
                    } else {
                        ForEach(clients, id: \.self) { c in
                            Text(c.name).tag(Optional(c))
                        }
                    }
                }
                .disabled(lockClient || isLoadingClients)

                TextField("Invoice # (e.g. INV-0001)", text: $draft.number)
                    .textInputAutocapitalization(.characters)

                DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                    .onChange(of: draft.dueDate) { _, _ in
                        didUserChangeDueDate = true
                    }

                HStack {
                    Text("Currency")
                    Spacer()
                    TextField("USD", text: $draft.currency)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textInputAutocapitalization(.characters)
                }
            }

            // --- Line Items ---
            Section("Items") {
                if draft.items.isEmpty {
                    Text("Add at least one line item").foregroundStyle(.secondary)
                }
                ForEach($draft.items) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Description", text: $item.description)
                        HStack {
                            Stepper("Qty: \(item.quantity)", value: $item.quantity, in: 1...999)
                            Spacer()
                            HStack {
                                Text("Unit")
                                TextField("0.00", value: $item.unitPrice, format: .number)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 100)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                .onDelete { idx in draft.items.remove(atOffsets: idx) }

                Button {
                    draft.items.append(LineItemDraft())
                } label: {
                    Label("Add item", systemImage: "plus.circle")
                }
            }

            // --- Totals ---
            Section("Totals") {
                HStack { Text("Subtotal"); Spacer(); Text(currency(draft.subTotal, code: draft.currency)) }
                HStack {
                    Text("Tax %")
                    Spacer()
                    TextField("0", value: $draft.taxPercent, format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                HStack { Text("Tax"); Spacer(); Text(currency(draft.taxAmount, code: draft.currency)) }
                HStack { Text("Total").bold(); Spacer(); Text(currency(draft.total, code: draft.currency)).bold() }
            }

            // --- Notes ---
            Section("Notes") {
                TextField("Optional notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("New Invoice")
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
        // Load clients
        .task { await loadClients() }
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
