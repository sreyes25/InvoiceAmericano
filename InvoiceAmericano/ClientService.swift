//
//  ClientService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import Foundation
@preconcurrency import Supabase   // relax Sendable checks coming from the package

enum ClientService {
    static func list() async throws -> [DBClient] {
        let res = try await SB.shared.client
            .from("clients")
            .select()
            .order("created_at", ascending: false)
            .execute()

        // Decode from raw Data to avoid the Decodable & Sendable generic on `.value`
        return try JSONDecoder().decode([DBClient].self, from: res.data)
    }

    static func create(name: String, email: String?) async throws {
        guard let uid = AuthService.userID else {
            throw NSError(domain: "auth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let payload = NewClientPayload(
            id: UUID().uuidString,
            user_id: uid,
            name: name,
            email: email
        )

        // IMPORTANT: wrap at call-site so the generic sees Encodable & Sendable.
        _ = try await SB.shared.client
            .from("clients")
            .insert(AnyEncodable(payload))
            .execute()
    }
}
