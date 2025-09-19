//
//  AuthViewModel.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//

// AuthViewModel.swift
import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var isAuthed = (AuthService.userID != nil)

    func signUp() async { await run { try await AuthService.signUp(email: email, password: password) } }

    func signIn() async {
        await run {
            try await AuthService.signIn(email: email, password: password)
            self.isAuthed = (AuthService.userID != nil)
        }
    }

    func signOut() async {
        await run {
            try await AuthService.signOut()
            self.isAuthed = false
            self.email = ""; self.password = ""
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isLoading = true; error = nil
        do { try await work() } catch { error = error.localizedDescription }
        isLoading = false
    }
}
