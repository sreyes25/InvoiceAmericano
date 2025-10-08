//
//  ClientService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/6/25.
//

import Foundation
import Supabase

private struct NewClientPayload: Encodable {
    let name: String
    let email: String?
    let phone: String?
    let user_id: String?   // matches RLS if required
}

enum ClientService {
    static func fetchClients() async throws -> [ClientRow] {
        let client = SupabaseManager.shared.client
        let query = client
            .from("clients")
            .select("id, name, email, phone, address, city, state, zip, created_at")
            .order("created_at", ascending: false)

        let rows: [ClientRow] = try await query.execute().value
        return rows
    }

    static func createClient(name: String, email: String?, phone: String?) async throws {
        let client = SupabaseManager.shared.client

        let userId = AuthService.currentUserIDFast() // likely a String? in your project
        let payload = NewClientPayload(
            name: name,
            email: email,
            phone: phone,
            user_id: userId    // pass through as-is; DB column is uuid, PostgREST will coerce from string
        )

        _ = try await client
            .from("clients")
            .insert(payload)
            .execute()
    }
}
