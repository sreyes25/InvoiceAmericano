//
//  SupabaseManager.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/5/25.
//
// SupabaseManager.swift
import Foundation
import Supabase
import Auth
import UIKit // if you open URLs anywhere from here later

enum Env {
    static let urlKey  = "SUPABASE_URL"
    static let anonKey = "SUPABASE_ANON_KEY"
    
    static var supabaseURL: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: urlString) else {
            fatalError("❌ Missing or invalid SUPABASE_URL in Info.plist")
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
            fatalError("❌ Missing SUPABASE_ANON_KEY in Info.plist")
        }
        return key
    }
}

final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient
    /// Centralized helper to read the currently authenticated user id (tenant key).
    ///
    /// Use this accessor everywhere instead of reaching into `auth` directly so we
    /// have a single place to adjust behavior (lowercasing, fallbacks, etc.).
    var currentUserID: UUID? { client.auth.currentSession?.user.id }

    /// String helper for convenience (optionally lowercased for storage paths).
    func currentUserIDString(lowercased: Bool = false) -> String? {
        let raw = currentUserID?.uuidString
        return lowercased ? raw?.lowercased() : raw
    }

    /// Throws a 401-style error when no user is present. Useful for guards.
    func requireCurrentUserIDString(lowercased: Bool = false) throws -> String {
        if let id = currentUserIDString(lowercased: lowercased) {
            return id
        }
        throw NSError(domain: "auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
    }

    private init() {
        // Read from Info.plist (populated by your .xcconfig)
        let rawURL  = Bundle.main.object(forInfoDictionaryKey: Env.urlKey) as? String
        let rawAnon = Bundle.main.object(forInfoDictionaryKey: Env.anonKey) as? String

        var supabaseURLString = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var anon = rawAnon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Remove accidental quotes if present
        supabaseURLString = supabaseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        anon = anon.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        // DEBUG: Show what we actually have at runtime
        print("🔎 SUPABASE_URL (runtime): '\(supabaseURLString)'")
        print("🔎 SUPABASE_ANON_KEY present: \(anon.isEmpty ? "NO" : "YES")")

        // Validate URL: must start with http(s) and have a host
        guard
            supabaseURLString.hasPrefix("http"),
            let parsedURL = URL(string: supabaseURLString),
            let host = parsedURL.host, !host.isEmpty
        else {
            preconditionFailure("""
            ❌ Invalid SUPABASE_URL. Make sure it looks like:
            https://pbhlynmgmgrzhynnrmna.supabase.co
            Current value: '\(supabaseURLString)'
            """)
        }

        precondition(!anon.isEmpty, "❌ Missing SUPABASE_ANON_KEY.")

        // Create client (no force unwraps later)
        client = SupabaseClient(
            supabaseURL: parsedURL,
            supabaseKey: anon,
            options: SupabaseClientOptions(
                auth: .init(flowType: .pkce) // keep your chosen flow
            )
        )
    }
}

extension SupabaseManager {
    /// Async convenience to get the current auth session if available.
    func currentSession() async -> Session? {
        do {
            return try await client.auth.session
        } catch {
            print("⚠️ Failed to fetch session: \(error)")
            return nil
        }
    }

    /// Returns a "Bearer <token>" header if the user is logged in.
    func bearerAuthorization() async -> String? {
        guard let s = await currentSession() else { return nil }
        return "Bearer \(s.accessToken)"
    }

    /// Builds a GET URLRequest with Authorization prefilled when possible.
    func makeAuthorizedGET(_ urlString: String) async -> URLRequest? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let auth = await bearerAuthorization() {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        return req
    }
}
