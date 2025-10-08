//
//  AuthService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
// 

import Foundation
import Supabase

enum AuthService {
    static func signUp(email: String, password: String) async throws {
        let redirect = URL(string: "invoiceamericano://auth-callback")!
        _ = try await SB.shared.client.auth.signUp(
            email: email,
            password: password,
            redirectTo: redirect
        )
        // No session yet until confirm + sign-in (or deep link restores)
    }

    static func signIn(email: String, password: String) async throws {
        _ = try await SB.shared.client.auth.signIn(
            email: email,
            password: password
        )
        NotificationCenter.default.post(name: .authDidChange, object: nil)
    }

    static func signOut() async throws {
        try await SB.shared.client.auth.signOut()
        NotificationCenter.default.post(name: .authDidChange, object: nil)
    }

    static func currentUserIDFast() -> String? {
        SB.shared.client.auth.currentSession?.user.id.uuidString
    }

    /// Called from your `.onOpenURL` deep-link handler
    static func handleDeepLink(_ url: URL) async throws {
        try await SB.shared.client.auth.session(from: url)
        NotificationCenter.default.post(name: .authDidChange, object: nil)
    }
}

extension Notification.Name {
    static let authDidChange = Notification.Name("AuthDidChange")
}
