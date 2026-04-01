//
//  ResetPasswordView.swift
//  InvoiceAmericano
//
//  Created by OpenAI on 2/24/26.
//

import SwiftUI

struct ResetPasswordView: View {
    @ObservedObject var vm: AuthViewModel

    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var showSuccess = false
    @State private var attemptedSubmit = false

    private var validationMessage: String? {
        if newPassword.isEmpty || confirmPassword.isEmpty {
            return attemptedSubmit ? I18n.tr("auth.reset.both_required") : nil
        }
        if newPassword.count < 8 {
            return I18n.tr("auth.reset.min_length")
        }
        if newPassword != confirmPassword {
            return I18n.tr("auth.reset.no_match")
        }
        return nil
    }

    private var canSubmit: Bool {
        validationMessage == nil && !vm.isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reset your password")
                        .font(.title2.bold())
                    Text("Set a new password for your account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showSuccess {
                    Text("Password updated. Redirecting to sign in...")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    attemptedSubmit = true
                    guard canSubmit else { return }

                    Task {
                        await vm.updatePassword(newPassword: newPassword)
                        guard vm.error == nil else { return }

                        await MainActor.run {
                            showSuccess = true
                            newPassword = ""
                            confirmPassword = ""
                        }

                        try? await Task.sleep(nanoseconds: 1_300_000_000)
                        await vm.completeRecoveryFlow()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(vm.isLoading ? "Updating..." : "Update Password")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Password Recovery")
            .toolbarTitleDisplayMode(.inline)
            .alert("Error", isPresented: Binding(
                get: { vm.error != nil },
                set: { newValue in if !newValue { vm.error = nil } }
            )) {
                Button("OK") { vm.error = nil }
            } message: {
                Text(vm.error ?? "Something went wrong.")
            }
        }
    }
}
