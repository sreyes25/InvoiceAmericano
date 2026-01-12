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
    @FocusState private var searchFocused: Bool
    @State private var pushClient: ClientRow? = nil
    
    let previewMode: Bool
    init(previewMode: Bool = false) { self.previewMode = previewMode }

    var filtered: [ClientRow] {
        guard !search.isEmpty else { return clients }
        return clients.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.email ?? "").localizedCaseInsensitiveContains(search) }
    }

    private var searchBar: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(searchFocused ? 0.18 : 0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("Search clients", text: $search)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused($searchFocused)

            if !search.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        search = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            if searchFocused {
                Button("Cancel") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        searchFocused = false
                    }
                }
                .font(.subheadline.weight(.semibold))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(searchFocused ? Color.gray.opacity(0.40) : Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(searchFocused ? 0.10 : 0.06), radius: 10, y: 5)
        .animation(.snappy(duration: 0.22), value: searchFocused)
        .animation(.easeInOut(duration: 0.15), value: search)
    }

    private var clientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Clients")
                    .font(.headline)
                Spacer()
                if !clients.isEmpty {
                    Text("\(filtered.count) shown")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if isLoading && clients.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading clients…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else if let error, clients.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Couldn’t load clients")
                        .font(.headline)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    Button("Retry") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(.vertical, 12)
            } else if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(search.isEmpty ? "No clients yet" : "No matches")
                        .font(.headline)
                    Text(search.isEmpty ? "Add your first client to start creating invoices." : "Try a different name or email.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if search.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showNew = true
                        } label: {
                            Label("Add Client", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(filtered) { c in
                        Button {
                            pushClient = c
                        } label: {
                            ClientRowCard(client: c)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error, !clients.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
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

    // MARK: - Preview helpers
    private static func previewClients() -> [ClientRow] {
        // Decode from JSON so we don't rely on a specific initializer.
        // If the model changes, previews will safely fall back to an empty list.
        let json = """
        [
          {"id":"3B4A4A3E-9C5F-4B9D-9C4E-7A7E0A0A0001","name":"Acme Construction","email":"billing@acme.com","city":"Brooklyn","state":"NY"},
          {"id":"3B4A4A3E-9C5F-4B9D-9C4E-7A7E0A0A0002","name":"Maria Lopez","email":"maria@example.com","city":"Queens","state":"NY"},
          {"id":"3B4A4A3E-9C5F-4B9D-9C4E-7A7E0A0A0003","name":"Park Slope Dermatology","email":"frontdesk@parkslopedermatology.com","city":"Brooklyn","state":"NY"}
        ]
        """

        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ClientRow].self, from: data)) ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    searchBar
                    clientsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background {
                AnimatedClientsBackground()
            }
            .navigationTitle("Clients")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showNew = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
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
            .scrollIndicators(.hidden)
        }
    }

    private func load() async {
        // Xcode Previews don't run the full auth flow; use mocked data.
        if previewMode {
            await MainActor.run {
                error = nil
                isLoading = false
                clients = Self.previewClients()
            }
            return
        }

        await MainActor.run {
            isLoading = true
            // Don’t clear existing content while refreshing
            error = nil
        }

        do {
            let rows = try await ClientService.fetchClients()
            await MainActor.run {
                clients = rows
                isLoading = false
            }
        } catch {
            // SwiftUI refresh/task cancellations are normal; don’t surface as an error.
            if error is CancellationError {
                await MainActor.run { isLoading = false }
                return
            }

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
                Circle()
                    .fill(Color.blue.opacity(0.85))
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.25),
                                        Color.black.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5)
                    )
                Text(initials(from: client.name))
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
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

private struct AnimatedClientsBackground: View {
    @State private var drift = false

    private var tint: Color { .gray }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            Circle()
                .fill(tint.opacity(0.07))
                .frame(width: 560, height: 560)
                .blur(radius: 58)
                .offset(x: drift ? 140 : -120, y: drift ? -80 : -140)

            Circle()
                .fill(tint.opacity(0.11))
                .frame(width: 540, height: 540)
                .blur(radius: 58)
                .offset(x: drift ? -120 : 130, y: drift ? 220 : 160)

            Circle()
                .fill(tint.opacity(0.13))
                .frame(width: 600, height: 600)
                .blur(radius: 52)
                .offset(x: drift ? -40 : 60, y: drift ? -260 : -220)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                drift.toggle()
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



#Preview("Clients – Light") {
    ClientListView(previewMode: true)
        .preferredColorScheme(.light)
}

#Preview("Clients – Dark") {
    ClientListView(previewMode: true)
        .preferredColorScheme(.dark)
}
