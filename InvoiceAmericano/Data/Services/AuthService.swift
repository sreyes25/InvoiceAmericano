//
//  AuthService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.

import Foundation
import Supabase

/// Centralized auth helper used by AuthViewModel and others.
/// Uses a single redirect URL across email sign-up links and OAuth
/// so that deep-link handling is consistent.
enum AuthService {
    // MARK: - Constants
    /// IMPORTANT: This must be whitelisted in Supabase Dashboard → Auth → URL Configuration → Redirect URLs
    private static let redirectURL = URL(string: "invoiceamericano://auth-callback")!

    // MARK: - Email/Password
    static func signUp(email: String, password: String) async throws {
        _ = try await SupabaseManager.shared.client.auth.signUp(
            email: email,
            password: password,
            redirectTo: redirectURL
        )
        // No active session until user confirms email OR you handle the magic link via handleOpenURL
    }

    static func signIn(email: String, password: String) async throws {
        _ = try await SupabaseManager.shared.client.auth.signIn(
            email: email,
            password: password
        )
        NotificationCenter.default.post(name: .authDidChange, object: nil)
    }

    static func signOut() async throws {
        try await SupabaseManager.shared.client.auth.signOut()
        NotificationCenter.default.post(name: .authDidChange, object: nil)
    }

    // MARK: - Sign in with Apple (via Supabase OAuth)
    /// Presents Apple's native sheet and returns via the app's custom URL scheme.
    static func signInWithApple() async throws {
        try await SupabaseManager.shared.client.auth.signInWithOAuth(
            provider: .apple,
            redirectTo: redirectURL
        )
    }

    // MARK: - Deep Link Handling (magic links / OAuth return)
    /// Call this from your SwiftUI `.onOpenURL` or SceneDelegate to finalize sessions.
    /// Example:
    ///   .onOpenURL { url in Task { await AuthService.handleOpenURL(url) } }
    @discardableResult
    static func handleOpenURL(_ url: URL) async -> Bool {
        do {
            try await SupabaseManager.shared.client.auth.session(from: url)
            NotificationCenter.default.post(name: .authDidChange, object: nil)
            return true
        } catch {
            return false
        }
    }

    /// Backwards-compat alias to avoid breaking existing callers.
    @discardableResult
    static func handleDeepLink(_ url: URL) async -> Bool {
        await handleOpenURL(url)
    }

    // MARK: - Session helpers
    /// Preferred: UUID typed user id if you need it.
    static func currentUserID() -> UUID? {
        SupabaseManager.shared.currentUserID
    }

    /// Legacy helper kept for compatibility with any existing call sites.
    static func currentUserIDFast() -> String? {
        SupabaseManager.shared.currentUserIDString()
    }

    /// Optional: Good to call on app launch to validate/refresh local session.
    static func refreshSession() async throws {
        try await SupabaseManager.shared.client.auth.refreshSession()
    }
}

// MARK: - Notification name used in your VM/UI
extension Notification.Name {
    static let authDidChange = Notification.Name("AuthDidChange")
}
