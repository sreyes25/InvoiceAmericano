//
//  AuthViewModel.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//

import Foundation
import Combine
import Supabase

enum PasswordStrength: String { case weak, ok, strong }

// Lightweight email check (good enough for UI)
extension String {
    var isPlausibleEmail: Bool {
        let parts = self.split(separator: "@")
        guard parts.count == 2, parts[0].count > 0 else { return false }
        let host = parts[1].split(separator: ".")
        return host.count >= 2 && host.last!.count >= 2
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    // MARK: - Mode
    enum Mode { case chooser, signIn, signUp }

    @Published var mode: Mode = .chooser

    // MARK: - Form state
    @Published var email: String = ""          { didSet { if !email.isEmpty { hasEditedEmail = true } } }
    @Published var password: String = ""       { didSet { if !password.isEmpty { hasEditedPassword = true } } }

    // Hints shown only when appropriate (see rules below)
    @Published var emailHint: String?
    @Published var passwordHint: String?
    @Published var strength: PasswordStrength = .weak

    // UX flags
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var banner: String?
    @Published var isAuthed: Bool = false

    private var hasEditedEmail = false
    private var hasEditedPassword = false
    private var attemptedSubmit = false

    // Tap throttle
    private var lastActionAt: Date = .distantPast
    private let minActionInterval: TimeInterval = 0.9

    // MARK: - Derived
    var canSubmitSignUp: Bool {
        email.isPlausibleEmail && strength != .weak && !isLoading
    }
    var canSubmitSignIn: Bool {
        email.isPlausibleEmail && !password.isEmpty && !isLoading
    }

    // MARK: - Public API
    func goChooser() {
        mode = .chooser
        clearInlineState()
    }
    func goSignUp() {
        mode = .signUp
        clearInlineState()
    }
    func goSignIn() {
        mode = .signIn
        clearInlineState()
    }

    func signUp() async {
        guard gateAction() else { return }
        attemptedSubmit = true
        validateFields(forSignUp: true)
        guard canSubmitSignUp else { return }

        await run("Sign up failed") { [self] in
            try await AuthService.signUp(email: self.email, password: self.password)
            self.banner = "Check your email to confirm your account."
            NotificationCenter.default.post(name: .authDidChange, object: nil)
        }
    }

    func signIn() async {
        guard gateAction() else { return }
        attemptedSubmit = true
        validateFields(forSignUp: false)
        guard canSubmitSignIn else { return }

        await run("Sign in failed") { [self] in
            try await AuthService.signIn(email: self.email, password: self.password)
            // Broadcast and refresh local auth state
            NotificationCenter.default.post(name: .authDidChange, object: nil)
            self.refreshAuthNow()
        }
    }

    /// Sign in with Apple (Supabase OAuth flow).
    /// UI calls this from the "Continue with Apple" button.
    func signInWithApple() async {
        guard gateAction() else { return }
        await run("Apple sign-in failed") { [self] in
            try await AuthService.signInWithApple()
            // Broadcast and refresh local auth state
            NotificationCenter.default.post(name: .authDidChange, object: nil)
            self.refreshAuthNow()
        }
    }

    func signOut() async {
        guard gateAction() else { return }
        await run("Sign out failed") { [self] in
            try await AuthService.signOut()
            self.isAuthed = false
        }
    }

    func refreshSession() async {
        await run("Session refresh failed", swallowError: true) { [self] in
            self.isAuthed = (AuthService.currentUserIDFast() != nil)
        }
    }

    // Refresh auth state without showing a spinner
    private func refreshAuthNow() {
        self.isAuthed = (AuthService.currentUserIDFast() != nil)
    }

    // MARK: - Validation
    func validateFields(forSignUp: Bool) {
        // Score strength always; we’ll decide visibility below.
        strength = score(password)

        switch mode {
        case .signUp:
            // Show inline hints only when user has interacted or tried to submit
            let show = attemptedSubmit || hasEditedEmail
            emailHint = email.isEmpty
                ? (show ? "Email required" : nil)
                : (email.isPlausibleEmail ? nil : (show ? "Enter a valid email" : nil))

            let showPwd = attemptedSubmit || hasEditedPassword
            passwordHint = password.isEmpty
                ? (showPwd ? "Password required" : nil)
                : (forSignUp && strength == .weak ? "Make password stronger" : nil)

        case .signIn:
            // Keep it simple; only surface hints if fields are empty on submit
            let show = attemptedSubmit
            emailHint = email.isEmpty ? (show ? "Email required" : nil) : nil
            passwordHint = password.isEmpty ? (show ? "Password required" : nil) : nil

        case .chooser:
            emailHint = nil
            passwordHint = nil
        }
    }

    private func score(_ pwd: String) -> PasswordStrength {
        var s = 0
        if pwd.count >= 8 { s += 1 }
        if pwd.rangeOfCharacter(from: .decimalDigits) != nil { s += 1 }
        if pwd.rangeOfCharacter(from: .uppercaseLetters) != nil { s += 1 }
        if pwd.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()-_=+[]{};:,<.>/?`~")) != nil { s += 1 }
        switch s {
        case 0...1: return .weak
        case 2...3: return .ok
        default: return .strong
        }
    }

    // MARK: - Helpers
    private func clearInlineState() {
        error = nil
        banner = nil
        emailHint = nil
        passwordHint = nil
        attemptedSubmit = false
        hasEditedEmail = false
        hasEditedPassword = false
    }

    private func gateAction() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastActionAt) >= minActionInterval else { return false }
        lastActionAt = now
        return true
    }

    private func run(
        _ failMessage: String,
        swallowError: Bool = false,
        _ op: @escaping () async throws -> Void
    ) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await op()
        } catch {
            if !swallowError {
                self.error = mapErrorMessage(default: failMessage, error)
            }
        }
    }

    private func mapErrorMessage(default msg: String, _ err: Error) -> String {
        let t = (err as NSError).localizedDescription.lowercased()
        if t.contains("invalid login") || t.contains("invalid credentials") { return "Email or password is incorrect." }
        if t.contains("email rate limit") || t.contains("too many") { return "Too many attempts — try again in a minute." }
        if t.contains("user already registered") || t.contains("already exists") { return "That email is already registered." }
        if t.contains("password") && t.contains("weak") { return "Password is too weak. Try a longer one with numbers & symbols." }
        if t.contains("email not confirmed") { return "Please confirm your email, then sign in." }
        return "\(msg): \(err.localizedDescription)"
    }
}
