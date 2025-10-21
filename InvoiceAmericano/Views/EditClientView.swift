//
//  EditClientView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import Foundation
import SwiftUI

struct EditClientView: View {
    let client: ClientRow
    var onSaved: (ClientRow) -> Void

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
    @FocusState private var focused: Field?
    private enum Field: Hashable {
        case name, email, phone, address, city, state, zip
    }

    init(client: ClientRow, onSaved: @escaping (ClientRow) -> Void) {
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
                Section("Name") {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                        .submitLabel(.next)
                        .focused($focused, equals: .name)
                        .onSubmit { focused = .email }
                }
                Section("Contact") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .submitLabel(.next)
                        .focused($focused, equals: .email)
                        .onSubmit { focused = .phone }

                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .submitLabel(.next)
                        .focused($focused, equals: .phone)
                        .onSubmit { focused = .address }
                }
                Section("Address") {
                    TextField("Street", text: $address)
                        .textContentType(.fullStreetAddress)
                        .submitLabel(.next)
                        .focused($focused, equals: .address)
                        .onSubmit { focused = .city }
                    HStack {
                        TextField("City", text: $city)
                            .textContentType(.addressCity)
                            .submitLabel(.next)
                            .focused($focused, equals: .city)
                            .onSubmit { focused = .state }
                        TextField("State", text: $state)
                            .frame(width: 80)
                            .textInputAutocapitalization(.characters)
                            .textContentType(.addressState)
                            .submitLabel(.next)
                            .focused($focused, equals: .state)
                            .onSubmit { focused = .zip }
                        TextField("ZIP", text: $zip)
                            .frame(width: 100)
                            .keyboardType(.numbersAndPunctuation)
                            .textContentType(.postalCode)
                            .submitLabel(.done)
                            .focused($focused, equals: .zip)
                            .onSubmit { focused = nil }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit Client")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func save() async {
        isSaving = true; error = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedState = state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let trimmedZip = zip.trimmingCharacters(in: .whitespacesAndNewlines)

        // very light email sanity check (optional)
        if !trimmedEmail.isEmpty, !trimmedEmail.contains("@") || !trimmedEmail.contains(".") {
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

            // Rebuild a local ClientRow to hand back (keeps UI snappy)
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
