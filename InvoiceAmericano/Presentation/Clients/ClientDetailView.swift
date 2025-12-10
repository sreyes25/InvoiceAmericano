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
        ScrollView {
            VStack(spacing: 16) {
                // Header card
                ClientHeaderCard(client: client) {
                    showEdit = true
                }

                // Address (shown only if at least one field is present)
                if hasAnyAddress(client) {
                    AddressCard(client: client)
                }

                // Error (if any)
                if let e = errorMsg {
                    Text(e)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                // Invoices list
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Invoices", systemImage: "doc.plaintext")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal)

                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if invoices.isEmpty && errorMsg == nil {
                        Text("No invoices yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(invoices) { inv in
                                NavigationLink {
                                    InvoiceDetailView(invoiceId: inv.id)
                                } label: {
                                    InvoiceRowCard(inv: inv)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.top, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.inline)
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
    }

    // MARK: - Data

    private func loadInvoices() async {
        do {
            isLoading = true
            errorMsg = nil
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

    // MARK: - Helpers

    private func hasAnyAddress(_ c: Client) -> Bool {
        !(c.address?.isEmpty ?? true)
        || !(c.city?.isEmpty ?? true)
        || !(c.state?.isEmpty ?? true)
        || !(c.zip?.isEmpty ?? true)
    }
}

// MARK: - Header Card

private struct ClientHeaderCard: View {
    let client: Client
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                InitialsAvatar(name: client.name)
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    VStack(alignment: .leading, spacing: 6) {
                        if let email = client.email, !email.isEmpty {
                            InfoChip(text: email, systemImage: "envelope")
                        }
                        if let phone = client.phone, !phone.isEmpty {
                            InfoChip(text: phone, systemImage: "phone")
                        }
                    }
                }
                Spacer()
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.black.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        .padding(.horizontal)
    }
}

private struct InitialsAvatar: View {
    let name: String

    var body: some View {
        let initials = initialsFromName(name)
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.indigo.opacity(0.9), .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
            Text(initials)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(Text("Client avatar: \(initials)"))
    }

    private func initialsFromName(_ s: String) -> String {
        let parts = s.split(separator: " ")
        let first = parts.first?.prefix(1) ?? "?"
        let last = parts.dropFirst().first?.prefix(1) ?? ""
        return String(first + last)
    }
}

private struct InfoChip: View {
    let text: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.caption)
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            Capsule().fill(Color(.tertiarySystemFill))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Address Card

private struct AddressCard: View {
    let client: Client
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Address", systemImage: "mappin.and.ellipse").font(.headline)
            if let a = client.address, !a.isEmpty {
                Text(a)
            }
            HStack(spacing: 6) {
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.black.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        .padding(.horizontal)
    }
}

// MARK: - Invoice Row Card

private struct InvoiceRowCard: View {
    let inv: InvoiceRow
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                // Match list-style change you applied elsewhere: client name above, invoice below
                Text(inv.client?.name ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(inv.number).font(.subheadline).bold()
                    StatusChip(status: displayStatus(inv))
                }
            }
            Spacer()
            Text(currency(inv.total))
                .font(.subheadline)
                .monospacedDigit()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.black.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func currency(_ total: Double?) -> String {
        let n = NumberFormatter()
        n.numberStyle = .currency
        n.currencyCode = "USD"
        return n.string(from: NSNumber(value: total ?? 0)) ?? "$0.00"
    }
    private func displayStatus(_ inv: InvoiceRow) -> String {
        if inv.status == "open", inv.sent_at != nil { return "sent" }
        return inv.status
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
