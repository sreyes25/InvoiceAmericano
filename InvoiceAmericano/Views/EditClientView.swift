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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Title card
                    HeaderCard(icon: "person.crop.circle", title: "Edit Client", subtitle: client.name)

                    // Client card
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

                    // Address card
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
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 70)
                                    .submitLabel(.next)
                                    .focused($focused, equals: .state)
                                    .onSubmit { focused = .zip }
                            }
                            LabeledField("ZIP") {
                                TextField("90210", text: $zip)
                                    .keyboardType(.numbersAndPunctuation)
                                    .textContentType(.postalCode)
                                    .frame(maxWidth: 100)
                                    .submitLabel(.done)
                                    .focused($focused, equals: .zip)
                                    .onSubmit { focused = nil }
                            }
                        }
                    }

                    if let error {
                        InlineError(text: error)
                    }

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            Task { await save() }
                        } label: {
                            PrimaryButtonLabel(text: isSaving ? "Saving…" : "Save Changes", icon: "checkmark.circle.fill")
                        }
                        .disabled(!canSave)

                        Button(role: .cancel) { dismiss() } label: {
                            SecondaryButtonLabel(text: "Cancel", icon: "xmark.circle")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .padding(.top, 12)
                .padding(.horizontal)
            }
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
                // Keyboard accessory
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
                created_at: client.created_at
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
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.blue.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 40, height: 40)

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

private struct PrimaryButtonLabel: View {
    let text: String
    let icon: String
    var body: some View {
        HStack {
            Spacer()
            Image(systemName: icon)
            Text(text).bold()
            Spacer()
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
        .foregroundStyle(.white)
    }
}

private struct SecondaryButtonLabel: View {
    let text: String
    let icon: String
    var body: some View {
        HStack {
            Spacer()
            Image(systemName: icon)
            Text(text).bold()
            Spacer()
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
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
