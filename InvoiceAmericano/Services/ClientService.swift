//
//  ClientService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/6/25.
//

import Foundation
import Supabase

// Payloads
private struct NewClientPayload: Encodable {
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let user_id: String?   // matches RLS if required
}

// Encodable patch that ONLY encodes non-nil fields (no nulls sent)
private struct UpdateClientPayload: Encodable {
    let name: String?
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?

    enum CodingKeys: String, CodingKey {
        case name, email, phone, address, city, state, zip
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let name { try c.encode(name, forKey: .name) }
        if let email { try c.encode(email, forKey: .email) }
        if let phone { try c.encode(phone, forKey: .phone) }
        if let address { try c.encode(address, forKey: .address) }
        if let city { try c.encode(city, forKey: .city) }
        if let state { try c.encode(state, forKey: .state) }
        if let zip { try c.encode(zip, forKey: .zip) }
    }

    var isEmpty: Bool {
        return name == nil &&
               email == nil &&
               phone == nil &&
               address == nil &&
               city == nil &&
               state == nil &&
               zip == nil
    }
}

enum ClientService {
    static func fetchClients() async throws -> [ClientRow] {
        let client = SupabaseManager.shared.client
        let rows: [ClientRow] = try await client
            .from("clients")
            .select("id, name, email, phone, address, city, state, zip, created_at")
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }

    static func createClient(
        name: String,
        email: String?,
        phone: String?,
        address: String?,
        city: String?,
        state: String?,
        zip: String?
    ) async throws {
        let client = SupabaseManager.shared.client
        let userId = AuthService.currentUserIDFast()

        let payload = NewClientPayload(
            name: name,
            email: email,
            phone: phone,
            address: address,
            city: city,
            state: state,
            zip: zip,
            user_id: userId
        )

        _ = try await client
            .from("clients")
            .insert(payload)
            .execute()
    }

    // Fetch a single client by id
    static func fetchClient(id: UUID) async throws -> ClientRow {
        let client = SupabaseManager.shared.client
        let row: ClientRow = try await client
            .from("clients")
            .select("id, name, email, phone, address, city, state, zip, created_at")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
        return row
    }

    // Update a client (only fields you pass will be changed; no nulls)
    static func updateClient(
        id: UUID,
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        address: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil
    ) async throws {
        let client = SupabaseManager.shared.client
        let patch = UpdateClientPayload(
            name: name,
            email: email,
            phone: phone,
            address: address,
            city: city,
            state: state,
            zip: zip
        )
        guard !patch.isEmpty else { return }  // nothing to update

        _ = try await client
            .from("clients")
            .update(patch)
            .match(["id": id.uuidString])
            .execute()
    }

    // Fetch invoices that belong to a specific client
    // MARK: Invoices for a client (list)
    static func fetchInvoicesForClient(clientId: UUID) async throws -> [InvoiceRow] {
        let client = SupabaseManager.shared.client

        // NOTE: no .single() here — this returns an array
        let rows: [InvoiceRow] = try await client
            .from("invoices")
            .select("id, number, status, total, created_at, sent_at, due_date")
            .eq("client_id", value: clientId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows
    }
}
