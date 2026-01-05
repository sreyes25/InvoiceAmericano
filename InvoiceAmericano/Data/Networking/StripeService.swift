//
//  StripeServices.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/30/25.
//

import Foundation
import SwiftUI
import Supabase
import Auth

struct StripeStatus: Codable {
    let connected: Bool
    let details_submitted: Bool?
    let charges_enabled: Bool?
    let payouts_enabled: Bool?
}

// MARK: - Networking helpers (timeouts + consistent authorized requests)
// Provides a small wrapper to avoid stalled requests and to ensure we always attach
// the Supabase access token. Centralizes logging and timeout handling.
private let IA_REQUEST_TIMEOUT: TimeInterval = 15

private func iaAuthorizedRequest(url: URL, method: String = "GET") async throws -> URLRequest {
    let client = SupabaseManager.shared.client
    let session = try await client.auth.session
    let uid = try SupabaseManager.shared.requireCurrentUserIDString()
    var req = URLRequest(url: url, timeoutInterval: IA_REQUEST_TIMEOUT)
    req.httpMethod = method
    // Ensures all Edge Function calls include Supabase JWT for auth verification (required when JWT is ON)
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    req.setValue(uid, forHTTPHeaderField: "x-user-id")
    return req
}

// MARK: - Fetch Stripe connect status (production-hardened)
// Change: adds timeout, structured logging, and consistent authorized request creation.
// Behavior is unchanged; this only improves resilience and debuggability.
@MainActor
func IA_fetchStripeStatus() async -> StripeStatus? {
    guard let url = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co/functions/v1/connect_status") else {
        print("❌ IA_fetchStripeStatus: bad URL")
        return nil
    }

    do {
        let req = try await iaAuthorizedRequest(url: url)
        // No body for status
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            print("❌ IA_fetchStripeStatus: non-HTTP response")
            return nil
        }
        if http.statusCode == 200 {
            if let status = try? JSONDecoder().decode(StripeStatus.self, from: data) {
                return status
            } else {
                print("❌ IA_fetchStripeStatus: decode failed")
                return nil
            }
        } else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            print("❌ IA_fetchStripeStatus: HTTP \(http.statusCode) – \(snippet)")
            return nil
        }
    } catch {
        print("❌ IA_fetchStripeStatus: \(error)")
        return nil
    }
}

// MARK: - Open Stripe Express dashboard/manage link
// Change: adds timeout, structured logging, and uses the authorized request helper.
// Behavior unchanged; opens the returned `url` if the edge function succeeds.
@MainActor
func IA_openStripeManage() async {
    guard let url = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co/functions/v1/connect_manage_link") else {
        print("❌ IA_openStripeManage: bad URL")
        return
    }

    do {
        let req = try await iaAuthorizedRequest(url: url, method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            print("❌ IA_openStripeManage: non-HTTP response")
            return
        }
        if http.statusCode == 200 {
            // Expecting a JSON object like { "url": "https://dashboard.stripe.com/..." }
            if
                let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                let link = dict["url"],
                let linkURL = URL(string: link)
            {
                await UIApplication.shared.open(linkURL)
            } else {
                print("❌ IA_openStripeManage: missing url in JSON")
            }
        } else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            print("❌ IA_openStripeManage: HTTP \(http.statusCode) – \(snippet)")
        }
    } catch {
        print("❌ IA_openStripeManage: \(error)")
    }
}
