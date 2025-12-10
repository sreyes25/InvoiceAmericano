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
    @State private var pushClient: ClientRow? = nil

    var filtered: [ClientRow] {
        guard !search.isEmpty else { return clients }
        return clients.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.email ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search clients", text: $search)
                            .textInputAutocapitalization(.words)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .listRowBackground(Color.clear)
                Section {
                    if isLoading && clients.isEmpty {
                        ProgressView("Loading…")
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                    } else if filtered.isEmpty {
                        Text("No clients").foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { c in
                            Button {
                                pushClient = c
                            } label: {
                                ClientRowCard(client: c)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                    }
                } header: {
                    Text("Clients")
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .scrollIndicators(.hidden)
            .navigationTitle("Clients")
            .toolbar {
                Button {
                    showNew = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
            .navigationDestination(item: $pushClient) { client in
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

private struct ClientRowCard: View {
    let client: ClientRow

    var body: some View {
        HStack(spacing: 12) {
            // Avatar / initials bubble
            ZStack {
                Circle().fill(LinearGradient(colors: [Color.blue.opacity(0.25), Color.indigo.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(initials(from: client.name))
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(client.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    if let email = client.email, !email.isEmpty {
                        Label(email, systemImage: "envelope")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
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
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
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
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }
}

private struct ClientDetailPlaceholder: View {
    let clientId: UUID
    var body: some View {
        Text("Client \(clientId.uuidString)").padding().navigationTitle("Client")
    }
}
