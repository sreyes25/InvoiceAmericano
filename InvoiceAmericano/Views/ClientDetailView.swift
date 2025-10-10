//
//  ClientDetailView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//


import SwiftUI

struct ClientDetailView: View {
    let client: Client   // assumes you have a Client model with at least `name`, and maybe `email`, `phone`

    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var invoices: [InvoiceRow] = []

    var body: some View {
        List {
            // Loading
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            // Error
            if let e = errorMsg {
                Text(e).foregroundStyle(.red)
            }

            // Client section
            Section("Client") {
                Text(client.name).font(.headline)
                if let email = client.email, !email.isEmpty {
                    Text(email).font(.subheadline).foregroundStyle(.secondary)
                }
                if let phone = client.phone, !phone.isEmpty {
                    Text(phone).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            // Invoices for this client
            Section("Invoices") {
                if invoices.isEmpty, !isLoading, errorMsg == nil {
                    Text("No invoices yet").foregroundStyle(.secondary)
                } else {
                    ForEach(invoices) { inv in
                        NavigationLink {
                            // Adjust initializer to your actual detail view
                            InvoiceDetailView(invoiceId: inv.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(inv.number).bold()
                                    Text(inv.status.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                // Adjust currency code if you store it per-invoice
                                Text((inv.total ?? 0), format: .currency(code: "USD"))
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
        .navigationTitle(client.name)
        .task { await loadInvoices() }
    }

    // MARK: - Data

    private func loadInvoices() async {
        do {
            isLoading = true
            // If you have a specific API to fetch by client id, use that instead of .all + filter.
            let all = try await InvoiceService.fetchInvoices(status: .all)
            // Prefer matching by client id if available:
            let clientUUID = client.id
            invoices = all.filter { row in
                if let cid = row.clientId { return cid == clientUUID }
                return false
            }
            isLoading = false
        } catch {
            errorMsg = error.localizedDescription
            isLoading = false
        }
    }
}
