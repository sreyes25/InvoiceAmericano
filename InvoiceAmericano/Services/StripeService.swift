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

struct StripeStatus: Decodable {
    let connected: Bool
    let details_submitted: Bool?
    let charges_enabled: Bool?
    let payouts_enabled: Bool?
}

@MainActor
func IA_fetchStripeStatus() async -> StripeStatus? {
    let client = SupabaseManager.shared.client
    // Get the current session and access token
    guard
        let session = try? await client.auth.session,
        let url = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co/functions/v1/connect_status")
    else { return nil }

    var req = URLRequest(url: url)
    req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

    if let (data, resp) = try? await URLSession.shared.data(for: req),
       let http = resp as? HTTPURLResponse, http.statusCode == 200 {
        return try? JSONDecoder().decode(StripeStatus.self, from: data)
    } else {
        return nil
    }
}

@MainActor
func IA_openStripeManage() async {
    let client = SupabaseManager.shared.client
    guard
        let session = try? await client.auth.session,
        let url = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co/functions/v1/connect_manage_link")
    else { return }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

    if let (data, resp) = try? await URLSession.shared.data(for: req),
       let http = resp as? HTTPURLResponse, http.statusCode == 200,
       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
       let link = dict["url"],
       let linkURL = URL(string: link) {
        await UIApplication.shared.open(linkURL)
    }
}
