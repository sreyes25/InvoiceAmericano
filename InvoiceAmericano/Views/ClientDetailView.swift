//
//  ClientDetailView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//


import SwiftUI

private struct InvoiceNav: Hashable {
    let id: UUID
}

struct ClientDetailView: View {
    let clientId: UUID

    @State private var client: ClientRow?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showEdit = false
    @State private var clientInvoices: [InvoiceRow] = []
    @State private var isLoadingInvoices = false

    var body: some View {
        Group {
            if isLoading && client == nil {
                ProgressView("Loading…")
            } else if let error {
                VStack(spacing: 12) {
                    Text("Error").font(.headline)
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                }
            } else if let c = client {
                ScrollView {
                    VStack(spacing: 16) {

                        // Header
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.name)
                                .font(.title2).bold()
                            if let created = c.created_at {
                                Text("Since \(formatDate(created))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Contact
                        SectionBox(title: "Contact") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let email = c.email, !email.isEmpty {
                                    LinkRow(system: "envelope", title: email, url: URL(string: "mailto:\(email)"))
                                } else {
                                    PlaceholderRow(system: "envelope", title: "No email")
                                }
                                if let phone = c.phone, !phone.isEmpty {
                                    LinkRow(system: "phone", title: phone, url: URL(string: "tel:\(phone.filter { !$0.isWhitespace })"))
                                } else {
                                    PlaceholderRow(system: "phone", title: "No phone")
                                }
                            }
                        }

                        // Address
                        SectionBox(title: "Address") {
                            if (c.address?.isEmpty == false) || c.city != nil || c.state != nil || c.zip != nil {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let address = c.address, !address.isEmpty { Text(address) }
                                    HStack(spacing: 4) {
                                        Text(c.city ?? "").opacity(c.city == nil ? 0.4 : 1)
                                        if c.city != nil && (c.state != nil || c.zip != nil) { Text(",") }
                                        Text(c.state ?? "").opacity(c.state == nil ? 0.4 : 1)
                                        Text(c.zip ?? "").opacity(c.zip == nil ? 0.4 : 1)
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("No address on file")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Quick actions
                        SectionBox(title: "Actions") {
                            VStack(spacing: 12) {
                                NavigationLink {
                                    // Pass the selected client and lock it so the user can’t change it
                                    NewInvoiceView(
                                        preselectedClient: c,
                                        lockClient: true
                                    ) { draft in
                                        Task {
                                            do {
                                                _ = try await InvoiceService.createInvoice(from: draft)
                                            } catch {
                                                await MainActor.run { self.error = error.localizedDescription }
                                            }
                                        }
                                    }
                                } label: {
                                    Label("New Invoice", systemImage: "doc.badge.plus")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }
                        }
                        
                        // >>> BEGIN: Invoices section for this client
                        SectionBox(title: "Invoices") {
                            if isLoadingInvoices && clientInvoices.isEmpty {
                                ProgressView("Loading…")
                            } else if clientInvoices.isEmpty {
                                Text("No invoices for this client").foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(clientInvoices, id: \.id) { inv in
                                        NavigationLink(value: InvoiceNav(id: inv.id)) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(inv.number).bold()
                                                    HStack(spacing: 6) {
                                                        Text(shortDate(inv.created_at))
                                                        Text("·")
                                                        Text(statusLabel(inv))
                                                    }
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text(currency(inv.total))
                                                    .font(.subheadline)
                                            }
                                            .padding(.vertical, 6)
                                        }
                                    }
                                }
                            }
                        }
                        // <<< END: Invoices section for this client
                    
                    }
                    .padding()
                }
                .navigationTitle("Client")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") { showEdit = true }
                    }
                }
                .navigationDestination(for: InvoiceNav.self) { nav in
                    InvoiceDetailView(invoiceId: nav.id)
                }
                .sheet(isPresented: $showEdit) {
                    EditClientSheet(client: c) {
                        showEdit = false
                        Task { await load() }
                    }
                }
            } else {
                EmptyView()
            }
        }
        .task { await load() }
    }

    // MARK: - Helpers

    private func load() async {
        isLoading = true
        isLoadingInvoices = true
        error = nil
        do {
            let c = try await ClientService.fetchClient(id: clientId)
            let invs = try await ClientService.fetchInvoicesForClient(clientId: clientId)

            await MainActor.run {
                client = c
                clientInvoices = invs
                isLoading = false
                isLoadingInvoices = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
                self.isLoadingInvoices = false
            }
        }
    }
    
    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    private func shortDate(_ s: String?) -> String {
        guard let s else { return "—" }

        // Try common server formats
        let fmts = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        let inDF = DateFormatter()
        inDF.locale = .init(identifier: "en_US_POSIX")
        inDF.timeZone = .init(secondsFromGMT: 0)

        var parsed: Date? = nil
        for f in fmts { inDF.dateFormat = f; if let d = inDF.date(from: s) { parsed = d; break } }
        if parsed == nil {
            let iso = ISO8601DateFormatter()
            parsed = iso.date(from: s) ?? { iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return iso.date(from: s) }()
        }
        guard let date = parsed else { return s }

        let out = DateFormatter()
        out.locale = .init(identifier: "en_US_POSIX")
        out.timeZone = .current
        out.dateFormat = "MM/dd/yy"
        return out.string(from: date)
    }

    private func statusLabel(_ inv: InvoiceRow) -> String {
        // If your model includes sent_at, show Sent while status is still open
        if inv.status == "open", let sent = (inv.sent_at), !sent.isEmpty {
            return "Sent"
        }
        return inv.status.capitalized
    }

    private func currency(_ total: Double?) -> String {
        let n = NumberFormatter()
        n.numberStyle = .currency
        n.currencyCode = "USD"
        return n.string(from: NSNumber(value: total ?? 0)) ?? "$0.00"
    }
}

// Reusable section box
private struct SectionBox<Content: View>: View {
    let title: String
    let content: () -> Content
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).bold()
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// Row that opens URL (mailto/tel)
private struct LinkRow: View {
    let system: String
    let title: String
    let url: URL?
    var body: some View {
        HStack {
            Image(systemName: system)
                .foregroundStyle(.blue)
            if let url {
                Link(title, destination: url)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(title)
            }
            Spacer()
        }
    }
}

private struct PlaceholderRow: View {
    let system: String
    let title: String
    var body: some View {
        HStack {
            Image(systemName: system).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// Sheet to edit client info
private struct EditClientSheet: View {
    let client: ClientRow
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var email: String
    @State private var phone: String
    @State private var address: String
    @State private var city: String
    @State private var state: String
    @State private var zip: String

    @State private var isSaving = false
    @State private var error: String?

    init(client: ClientRow, onSaved: @escaping () -> Void) {
        self.client = client
        self.onSaved = onSaved
        _name = State(initialValue: client.name)
        _email = State(initialValue: client.email ?? "")
        _phone = State(initialValue: client.phone ?? "")
        _address = State(initialValue: client.address ?? "")
        _city = State(initialValue: client.city ?? "")
        _state = State(initialValue: client.state ?? "")
        _zip = State(initialValue: client.zip ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Client") {
                    TextField("Name", text: $name)
                    TextField("Email", text: $email).keyboardType(.emailAddress)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                }
                Section("Address") {
                    TextField("Street", text: $address)
                    HStack {
                        TextField("City", text: $city)
                        TextField("State", text: $state).frame(width: 80)
                        TextField("ZIP", text: $zip).frame(width: 100)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit Client")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        error = nil

        // Trim inputs to avoid false "changes"
        let tName    = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tEmail   = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let tPhone   = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let tAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let tCity    = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let tState   = state.trimmingCharacters(in: .whitespacesAndNewlines)
        let tZip     = zip.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only send fields that actually changed; unchanged -> nil so they won't be updated
        let namePatch  : String? = (tName    != client.name)            ? tName                              : nil
        let emailPatch : String? = (tEmail   != (client.email   ?? "")) ? (tEmail.isEmpty  ? nil : tEmail)   : nil
        let phonePatch : String? = (tPhone   != (client.phone   ?? "")) ? (tPhone.isEmpty  ? nil : tPhone)   : nil
        let addrPatch  : String? = (tAddress != (client.address ?? "")) ? (tAddress.isEmpty ? nil : tAddress) : nil
        let cityPatch  : String? = (tCity    != (client.city    ?? "")) ? (tCity.isEmpty   ? nil : tCity)    : nil
        let statePatch : String? = (tState   != (client.state   ?? "")) ? (tState.isEmpty  ? nil : tState)   : nil
        let zipPatch   : String? = (tZip     != (client.zip     ?? "")) ? (tZip.isEmpty    ? nil : tZip)     : nil

        // If nothing changed, just dismiss
        if namePatch == nil && emailPatch == nil && phonePatch == nil &&
           addrPatch == nil && cityPatch == nil && statePatch == nil && zipPatch == nil {
            await MainActor.run {
                isSaving = false
                onSaved()
                dismiss()
            }
            return
        }

        do {
            try await ClientService.updateClient(
                id: client.id,
                name: namePatch,
                email: emailPatch,
                phone: phonePatch,
                address: addrPatch,
                city: cityPatch,
                state: statePatch,
                zip: zipPatch
            )
            await MainActor.run {
                isSaving = false
                onSaved()
                dismiss()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isSaving = false
            }
        }
    }
}

// Lightweight “new invoice for client” screen.
// Pushes NewInvoiceView and actually SAVES the invoice on completion.
private struct NewInvoiceViewForClient: View {
    let client: ClientRow

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            NewInvoiceView(
                preselectedClient: client,
                lockClient: true
            ) { draft in
                // Ensure we actually persist the invoice
                Task {
                    isSaving = true; error = nil
                    do {
                        let _ = try await InvoiceService.createInvoice(from: draft)
                        await MainActor.run {
                            isSaving = false
                            dismiss()   // go back to client details
                        }
                    } catch {
                        await MainActor.run {
                            self.error = error.localizedDescription
                            self.isSaving = false
                        }
                    }
                }
            }
        }
        .navigationTitle("New Invoice")
        .overlay(alignment: .bottom) {
            if isSaving {
                ProgressView("Saving…")
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 16)
            }
        }
        .alert("Couldn’t save invoice", isPresented: .constant(error != nil), presenting: error) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(err)
        }
    }
}
