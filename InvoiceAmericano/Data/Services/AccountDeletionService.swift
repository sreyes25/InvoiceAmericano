//
//  AccountDeletionService.swift
//  InvoiceAmericano
//
//  Created by Codex on 3/12/26.
//

import Foundation
import Supabase
import Auth

enum AccountDeletionService {
    private enum DeleteAccountError: LocalizedError {
        case invalidFunctionURL
        case backendNotConfigured
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .invalidFunctionURL:
                return "Account deletion is temporarily unavailable."
            case .backendNotConfigured:
                return "Account deletion isn't configured on the server yet. Contact support so we can finish deleting your account."
            case .failed(let message):
                return message
            }
        }
    }

    static func deleteCurrentAccount() async throws {
        let client = SupabaseManager.shared.client
        let session = try await client.auth.session
        let uid = session.user.id.uuidString

        try await callDeleteAccountFunction(accessToken: session.accessToken)
        clearLocalData(for: uid)

        do {
            try await client.auth.signOut()
        } catch {
            // Account may already be removed server-side; treat local sign-out failure as non-blocking.
        }

        NotificationCenter.default.post(name: .authDidChange, object: nil)
    }

    private static func callDeleteAccountFunction(accessToken: String) async throws {
        guard let functionURL = URL(string: "functions/v1/delete-account", relativeTo: Env.supabaseURL) else {
            throw DeleteAccountError.invalidFunctionURL
        }

        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeleteAccountError.failed("Could not reach the account deletion service.")
        }

        switch http.statusCode {
        case 200...299:
            return
        case 404:
            throw DeleteAccountError.backendNotConfigured
        default:
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw DeleteAccountError.failed(
                message?.isEmpty == false
                    ? "Account deletion failed: \(message!)"
                    : "Account deletion failed with status \(http.statusCode)."
            )
        }
    }

    private static func clearLocalData(for uid: String) {
        let defaults = UserDefaults.standard

        let removablePrefixes = [
            "offline_cache.\(uid).",
            "offline_queue.\(uid)."
        ]
        for key in defaults.dictionaryRepresentation().keys where removablePrefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }

        NotificationService.reset()
        BrandingService.invalidateCache()
    }
}
