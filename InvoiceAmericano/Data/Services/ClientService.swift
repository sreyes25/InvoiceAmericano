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
        let uid = try SupabaseManager.shared.requireCurrentUserIDString()
        do {
            let rows: [ClientRow] = try await client
                .from("clients")
                .select("id, name, email, phone, address, city, state, zip, created_at, color_hex")
                .eq("user_id", value: uid)
                .order("created_at", ascending: false)
                .execute()
                .value
            OfflineCacheService.saveClients(rows, uid: uid)
            return rows
        } catch {
            if let cached = OfflineCacheService.loadClients(uid: uid) {
                return cached
            }
            throw error
        }
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
        let userId = try SupabaseManager.shared.requireCurrentUserIDString()
        if !NetworkMonitorService.isConnectedNow() {
            await OfflineWriteQueueService.shared.enqueueClientCreate(
                uid: userId,
                name: name,
                email: email,
                phone: phone,
                address: address,
                city: city,
                state: state,
                zip: zip
            )
            return
        }

        do {
            _ = try await createClientOnline(
                name: name,
                email: email,
                phone: phone,
                address: address,
                city: city,
                state: state,
                zip: zip,
                uid: userId
            )
        } catch {
            if OfflineWriteQueueService.shouldQueueForOffline(error) {
                await OfflineWriteQueueService.shared.enqueueClientCreate(
                    uid: userId,
                    name: name,
                    email: email,
                    phone: phone,
                    address: address,
                    city: city,
                    state: state,
                    zip: zip
                )
                return
            }
            throw error
        }
    }

    static func createClientOnline(
        name: String,
        email: String?,
        phone: String?,
        address: String?,
        city: String?,
        state: String?,
        zip: String?,
        uid: String
    ) async throws -> ClientRow {
        let client = SupabaseManager.shared.client

        let payload = NewClientPayload(
            name: name,
            email: email,
            phone: phone,
            address: address,
            city: city,
            state: state,
            zip: zip,
            user_id: uid
        )

        let created: ClientRow = try await client
            .from("clients")
            .insert(payload)
            .select("id, name, email, phone, address, city, state, zip, created_at, color_hex")
            .single()
            .execute()
            .value

        if var cached = OfflineCacheService.loadClients(uid: uid) {
            cached.removeAll { $0.id == created.id }
            cached.insert(created, at: 0)
            OfflineCacheService.saveClients(cached, uid: uid)
        }

        return created
    }

    // Fetch a single client by id
    static func fetchClient(id: UUID) async throws -> ClientRow {
        let client = SupabaseManager.shared.client
        let uid = try SupabaseManager.shared.requireCurrentUserIDString()
        do {
            let row: ClientRow = try await client
                .from("clients")
                .select("id, name, email, phone, address, city, state, zip, created_at, color_hex")
                .eq("id", value: id.uuidString)
                .eq("user_id", value: uid)
                .single()
                .execute()
                .value
            if var cached = OfflineCacheService.loadClients(uid: uid) {
                if let existing = cached.firstIndex(where: { $0.id == row.id }) {
                    cached[existing] = row
                } else {
                    cached.insert(row, at: 0)
                }
                OfflineCacheService.saveClients(cached, uid: uid)
            } else {
                OfflineCacheService.saveClients([row], uid: uid)
            }
            return row
        } catch {
            if let cached = OfflineCacheService.loadClients(uid: uid),
               let row = cached.first(where: { $0.id == id }) {
                return row
            }
            throw error
        }
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
        let uid = try SupabaseManager.shared.requireCurrentUserIDString()
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
            .eq("user_id", value: uid)
            .execute()

        if var cached = OfflineCacheService.loadClients(uid: uid),
           let idx = cached.firstIndex(where: { $0.id == id }) {
            let current = cached[idx]
            cached[idx] = ClientRow(
                id: current.id,
                name: name ?? current.name,
                email: email ?? current.email,
                phone: phone ?? current.phone,
                address: address ?? current.address,
                city: city ?? current.city,
                state: state ?? current.state,
                zip: zip ?? current.zip,
                created_at: current.created_at,
                color_hex: current.color_hex
            )
            OfflineCacheService.saveClients(cached, uid: uid)
        }
    }

    // Fetch invoices that belong to a specific client
    // MARK: Invoices for a client (list)
    static func fetchInvoicesForClient(clientId: UUID) async throws -> [InvoiceRow] {
        let client = SupabaseManager.shared.client
        let uid = try SupabaseManager.shared.requireCurrentUserIDString()

        // NOTE: no .single() here — this returns an array
        do {
            let rows: [InvoiceRow] = try await client
                .from("invoices")
                .select("id, number, status, total, created_at, sent_at, due_date")
                .eq("client_id", value: clientId.uuidString)
                .eq("user_id", value: uid)
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            if let cached = OfflineCacheService.loadInvoices(uid: uid) {
                return cached.filter { $0.clientId == clientId }
            }
            throw error
        }
    }
}
