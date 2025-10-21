//
//  ClientDetailView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//


import SwiftUI

struct ClientDetailView: View {
    // Use @State so edits reflect immediately in this screen
    @State private var client: Client   // assumes you have a Client model with id/name/email/phone

    // Allow presenting the edit sheet
    @State private var showEdit = false

    // Custom init to seed the @State value from the incoming client
    init(client: Client) {
        _client = State(initialValue: client)
    }

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
            // Address (shown only if at least one field is present)
            Section("Address") {
                if let a = client.address, !a.isEmpty {
                    Text(a)
                }
                HStack {
                    if let city = client.city, !city.isEmpty { Text(city) }
                    if let st = client.state, !st.isEmpty {
                        if (client.city?.isEmpty == false) { Text(",") }
                        Text(st)
                    }
                    if let zip = client.zip, !zip.isEmpty {
                        if (client.city?.isEmpty == false) || (client.state?.isEmpty == false) { Text("·") }
                        Text(zip)
                    }
                }
                .foregroundStyle(.secondary)

                // Placeholder if no address fields are provided
                if (client.address?.isEmpty ?? true) && (client.city?.isEmpty ?? true) && (client.state?.isEmpty ?? true) && (client.zip?.isEmpty ?? true) {
                    Text("No address provided")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }

            // Invoices for this client
            Section("Invoices") {
                if invoices.isEmpty, !isLoading, errorMsg == nil {
                    Text("No invoices yet").foregroundStyle(.secondary)
                } else {
                    ForEach(invoices) { inv in
                        NavigationLink(value: inv.id) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(inv.number).font(.subheadline).bold()
                                        StatusChip(status: inv.status)
                                    }
                                }
                                Spacer()
                                Text((inv.total ?? 0), format: .currency(code: "USD"))
                                    .font(.subheadline)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
        .navigationTitle(client.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            // Present an editor; when it returns an updated client, refresh local state and invoices
            NavigationStack {
                EditClientView(client: client) { updated in
                    client = updated
                    Task { await loadInvoices() }
                    showEdit = false
                }
            }
        }
        .task { await loadInvoices() }
        .navigationDestination(for: UUID.self) { invoiceId in
            InvoiceDetailView(invoiceId: invoiceId)
        }
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

// Minimal status chip (same palette as InvoiceListView)
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
        switch status.lowercased() {
        case "paid": return .green
        case "overdue": return .red
        case "sent": return .yellow
        case "open": return .blue
        default: return .gray
        }
    }
}
