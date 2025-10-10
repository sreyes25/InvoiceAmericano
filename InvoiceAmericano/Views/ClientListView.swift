//
//  ClientListView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/6/25.
//

import SwiftUI

struct ClientListView: View {
    @State private var clients: [ClientRow] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showNew = false
    @State private var search = ""

    var filtered: [ClientRow] {
        guard !search.isEmpty else { return clients }
        return clients.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.email ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if #available(iOS 15.0, *) {
                    Section {
                        TextField("Search clients", text: $search)
                    }
                }
                Section {
                    if isLoading && clients.isEmpty {
                        ProgressView("Loading…")
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                    } else if filtered.isEmpty {
                        Text("No clients").foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { c in
                            NavigationLink(value: c) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).bold()
                                    HStack(spacing: 6) {
                                        if let email = c.email, !email.isEmpty {
                                            Text(email)
                                        }
                                        if (c.city?.isEmpty == false) || (c.state?.isEmpty == false) {
                                            Text("·")
                                            Text("\(c.city ?? "")\(c.city != nil && c.state != nil ? ", " : "")\(c.state ?? "")")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Clients")
                }
            }
            .navigationTitle("Clients")
            .toolbar {
                Button {
                    showNew = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
            .navigationDestination(for: ClientRow.self) { client in
                ClientDetailView(client: client)
            }
            .sheet(isPresented: $showNew) {
                NavigationStack {
                    NewClientView {
                        showNew = false
                        Task { await load() }
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let rows = try await ClientService.fetchClients()
            await MainActor.run {
                clients = rows
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

private struct ClientDetailPlaceholder: View {
    let clientId: UUID
    var body: some View {
        Text("Client \(clientId.uuidString)").padding().navigationTitle("Client")
    }
}
