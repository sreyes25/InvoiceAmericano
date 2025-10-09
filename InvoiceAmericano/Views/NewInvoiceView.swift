//
//  NewInvoiceView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/6/25.
//

import SwiftUI

struct NewInvoiceView: View {
    @State private var draft = InvoiceDraft()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        Form {
            Section(header: Text("Client")) {
                // Your client selection UI...
            }

            Section(header: Text("Items")) {
                // Your item input UI...
            }

            Section(header: Text("Totals")) {
                // Your totals display...
                if draft.total <= 0 {
                    Text("⚠️ Total must be greater than $0 before saving.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Button("Save") {
                Task { await saveInvoice() }
            }
            .disabled(!canSave)
        }
    }

    private var canSave: Bool {
        guard draft.client != nil,
              !draft.number.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

        // Require at least one valid line item and total > 0
        let hasValidItem = draft.items.contains { item in
            !item.description.trimmingCharacters(in: .whitespaces).isEmpty &&
            item.quantity > 0 &&
            item.unitPrice > 0
        }

        return hasValidItem && draft.total > 0
    }

    private func saveInvoice() async {
        // Your existing save logic...
        presentationMode.wrappedValue.dismiss()
    }
}

// Placeholder structs for this example
struct InvoiceDraft {
    var client: String? = nil
    var number: String = ""
    var items: [InvoiceItem] = []
    var total: Double {
        items.reduce(0) { $0 + (Double($1.quantity) * $1.unitPrice) }
    }
}

struct InvoiceItem {
    var description: String
    var quantity: Int
    var unitPrice: Double
}
