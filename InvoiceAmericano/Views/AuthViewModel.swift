//
//  AuthViewModel.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//


import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var isAuthed = false

    func refreshSession() async {
        // Non-throwing, no await
        let uid = AuthService.currentUserIDFast()
        isAuthed = (uid != nil)
        if let uid {
            print("DEBUG: session userID =", uid)
        } else {
            print("DEBUG: no session")
        }
    }

    func signUp() async {
        await run("Sign up failed") {
            try await AuthService.signUp(email: self.email, password: self.password)
            self.error = "If email confirmation is enabled, check your inbox to verify, then Log In."
        }
    }

    func signIn() async {
        await run("Log in failed") {
            try await AuthService.signIn(email: self.email, password: self.password)
            // After sign-in, check quickly for a session
            let uid = AuthService.currentUserIDFast()
            self.isAuthed = (uid != nil)
            NotificationCenter.default.post(name: .authDidChange, object: nil)
            print("DEBUG: post-login userID =", uid ?? "nil")
            if uid == nil {
                self.error = "Logged in, but no session found. Check Supabase email confirmation setting."
            }
        }
    }

    func signOut() async {
        await run("Log out failed") {
            try await AuthService.signOut()
            self.isAuthed = false
            self.email = ""; self.password = ""
            NotificationCenter.default.post(name: .authDidChange, object: nil)
            print("DEBUG: signed out")
        }
    }

    private func run(_ defaultMessage: String, _ work: @escaping () async throws -> Void) async {
        isLoading = true; error = nil
        do { try await work() }
        catch {
            let msg = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
            self.error = msg ?? defaultMessage
            print("DEBUG:", defaultMessage, "→", error)
        }
        isLoading = false
    }
}
