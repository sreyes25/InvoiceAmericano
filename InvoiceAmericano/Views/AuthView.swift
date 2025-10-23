//
//  AuthView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//

// AuthView.swift
import SwiftUI

struct AuthView: View {
    @StateObject private var vm = AuthViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Email", text: $vm.email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $vm.password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)

                if let err = vm.error { Text(err).foregroundColor(.red).font(.footnote) }

                if vm.isLoading {
                    ProgressView()
                } else {
                    HStack {
                        Button("Sign Up") { Task { await vm.signUp() } }
                            .buttonStyle(.bordered)
                        Button("Log In") { Task { await vm.signIn() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(vm.email.isEmpty || vm.password.isEmpty)
                    }
                }

                if vm.isAuthed {
                    Divider().padding(.vertical, 8)
                    Button("Log Out") { Task { await vm.signOut() } }
                        .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Sign In")
            .task {
                await vm.refreshSession()
            }
        }
    }
}
