//
//  NewClientView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/6/25.
//

import SwiftUI

struct NewClientView: View {
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Client") {
                TextField("Name", text: $name)
                TextField("Email", text: $email).keyboardType(.emailAddress)
                TextField("Phone", text: $phone).keyboardType(.phonePad)
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("New Client")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true; error = nil
        do {
            try await ClientService.createClient(name: name.trimmingCharacters(in: .whitespaces),
                                                 email: email.isEmpty ? nil : email,
                                                 phone: phone.isEmpty ? nil : phone)
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
