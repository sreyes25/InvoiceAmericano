//
//  EditClientView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import SwiftUI
import Foundation

struct EditClientView: View {
    let client: ClientRow
    var onSaved: (ClientRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?

    // Editable fields
    @State private var name: String
    @State private var email: String
    @State private var phone: String
    @State private var address: String
    @State private var city: String
    @State private var state: String
    @State private var zip: String

    // UI state
    @State private var isSaving = false
    @State private var error: String?

    private enum Field: Hashable {
        case name, email, phone, address, city, state, zip
    }

    // Track initial snapshot for change detection
    private let initial: Snapshot
    private struct Snapshot: Equatable {
        var name: String
        var email: String?
        var phone: String?
        var address: String?
        var city: String?
        var state: String?
        var zip: String?
    }

    init(client: ClientRow, onSaved: @escaping (ClientRow) -> Void) {
        self.client = client
        self.onSaved = onSaved

        let snap = Snapshot(
            name: client.name,
            email: client.email,
            phone: client.phone,
            address: client.address,
            city: client.city,
            state: client.state,
            zip: client.zip
        )
        self.initial = snap

        _name = State(initialValue: client.name)
        _email = State(initialValue: client.email ?? "")
        _phone = State(initialValue: client.phone ?? "")
        _address = State(initialValue: client.address ?? "")
        _city = State(initialValue: client.city ?? "")
        _state = State(initialValue: client.state ?? "")
        _zip = State(initialValue: client.zip ?? "")
    }

    // Has changes?
    private var currentSnapshot: Snapshot {
        Snapshot(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : address.trimmingCharacters(in: .whitespacesAndNewlines),
            city: city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : city.trimmingCharacters(in: .whitespacesAndNewlines),
            state: state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            zip: zip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : zip.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    private var hasChanges: Bool { currentSnapshot != initial }
    private var canSave: Bool {
        !isSaving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasChanges
    }

    private var clientTint: Color {
        Color(hex: client.color_hex) ?? .gray
    }

    private var clientInitials: String {
        initials(from: client.name)
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HeaderCard(tint: clientTint, initials: clientInitials, title: "Edit Client", subtitle: client.name)

                    SectionCard(title: "Client") {
                        LabeledField("Full Name") {
                            TextField("Required", text: $name)
                                .textContentType(.name)
                                .submitLabel(.next)
                                .focused($focused, equals: .name)
                                .onSubmit { focused = .email }
                        }
                        LabeledField("Email") {
                            TextField("name@example.com", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.emailAddress)
                                .submitLabel(.next)
                                .focused($focused, equals: .email)
                                .onSubmit { focused = .phone }
                        }
                        LabeledField("Phone") {
                            TextField("(555) 123‑4567", text: $phone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .submitLabel(.next)
                                .focused($focused, equals: .phone)
                                .onSubmit { focused = .address }
                        }
                    }

                    SectionCard(title: "Address") {
                        LabeledField("Street") {
                            TextField("Street address", text: $address)
                                .textContentType(.fullStreetAddress)
                                .submitLabel(.next)
                                .focused($focused, equals: .address)
                                .onSubmit { focused = .city }
                        }
                        HStack(spacing: 12) {
                            LabeledField("City") {
                                TextField("City", text: $city)
                                    .textContentType(.addressCity)
                                    .submitLabel(.next)
                                    .focused($focused, equals: .city)
                                    .onSubmit { focused = .state }
                            }
                            LabeledField("State") {
                                TextField("CA", text: $state)
                                    .textInputAutocapitalization(.characters)
                                    .frame(maxWidth: 72)
                                    .submitLabel(.next)
                                    .focused($focused, equals: .state)
                                    .onSubmit { focused = .zip }
                            }
                            LabeledField("ZIP") {
                                TextField("90210", text: $zip)
                                    .keyboardType(.numbersAndPunctuation)
                                    .textContentType(.postalCode)
                                    .frame(maxWidth: 104)
                                    .submitLabel(.done)
                                    .focused($focused, equals: .zip)
                                    .onSubmit { focused = nil }
                            }
                        }
                    }

                    if let error {
                        InlineError(text: error)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background {
                AnimatedClientEditBackground(tint: clientTint)
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Actions

    private func save() async {
        isSaving = true; error = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedState = state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let trimmedZip = zip.trimmingCharacters(in: .whitespacesAndNewlines)

        // minimal email sanity check
        if !trimmedEmail.isEmpty, !(trimmedEmail.contains("@") && trimmedEmail.contains(".")) {
            await MainActor.run {
                self.error = "Please enter a valid email."
                self.isSaving = false
                self.focused = .email
            }
            return
        }

        do {
            try await ClientService.updateClient(
                id: client.id,
                name: trimmedName,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                city: trimmedCity.isEmpty ? nil : trimmedCity,
                state: trimmedState.isEmpty ? nil : trimmedState,
                zip: trimmedZip.isEmpty ? nil : trimmedZip
            )

            // Construct updated local row (snappy UI)
            let updated = ClientRow(
                id: client.id,
                name: trimmedName,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                city: trimmedCity.isEmpty ? nil : trimmedCity,
                state: trimmedState.isEmpty ? nil : trimmedState,
                zip: trimmedZip.isEmpty ? nil : trimmedZip,
                created_at: client.created_at,
                color_hex: client.color_hex
            )

            await MainActor.run {
                onSaved(updated)
                isSaving = false
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

// MARK: - Reusable UI bits

private struct HeaderCard: View {
    let tint: Color
    let initials: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.6)
                    )

                if initials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || initials == "?" {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    Text(initials)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            .shadow(color: tint.opacity(0.18), radius: 10, y: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                .strokeBorder(.black.opacity(0.05))
        )
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline).bold()
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.black.opacity(0.04))
        )
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Subtle animated background

private struct AnimatedClientEditBackground: View {
    let tint: Color
    @State private var drift = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            Circle()
                .fill(Color.gray.opacity(0.08))
                .frame(width: 560, height: 560)
                .blur(radius: 58)
                .offset(x: drift ? 140 : -120, y: drift ? -80 : -140)

            Circle()
                .fill(Color.gray.opacity(0.10))
                .frame(width: 540, height: 540)
                .blur(radius: 58)
                .offset(x: drift ? -120 : 130, y: drift ? 220 : 160)

            Circle()
                .fill(tint.opacity(0.12))
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

private struct InlineError: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text).foregroundStyle(.red)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(.red.opacity(0.2))
        )
        .padding(.horizontal)
    }
}

// MARK: - Hex color helper

private extension Color {
    /// Supports: "#RRGGBB" or "RRGGBB" (optionally "#AARRGGBB"). Returns nil if invalid.
    init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }
        if hex.hasPrefix("#") { hex.removeFirst() }

        // Allow AARRGGBB or RRGGBB
        let value = UInt64(hex, radix: 16)
        guard let value else { return nil }

        switch hex.count {
        case 6:
            let r = Double((value & 0xFF0000) >> 16) / 255.0
            let g = Double((value & 0x00FF00) >> 8) / 255.0
            let b = Double(value & 0x0000FF) / 255.0
            self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
        case 8:
            let a = Double((value & 0xFF000000) >> 24) / 255.0
            let r = Double((value & 0x00FF0000) >> 16) / 255.0
            let g = Double((value & 0x0000FF00) >> 8) / 255.0
            let b = Double(value & 0x000000FF) / 255.0
            self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
        default:
            return nil
        }
    }
}
