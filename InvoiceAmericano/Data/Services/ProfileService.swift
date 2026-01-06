//
//  ProfileService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.
//

import Foundation
import Supabase

enum ProfileService {
    static func fetchMe() async throws -> Profile {
        let client = SupabaseManager.shared.client
        // current user id from your existing auth helper
        guard let uid = AuthService.currentUserIDFast() else {
            throw NSError(domain: "ProfileService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let row: Profile = try await client
            .from("profiles")
            .select("id, email, full_name")
            .eq("id", value: uid)
            .single()
            .execute()
            .value

        return row
    }
    
    static func loadNotificationsEnabled() async -> Bool {
            let client = SupabaseManager.shared.client
            let session = try? await client.auth.session
            guard let uid = session?.user.id.uuidString else { return true }

        do {
            let rows: [ProfileSettingsRow] = try await client
                .from("settings")
                .select("notifications_enabled")
                .eq("user_id", value: uid)
                .limit(1)
                .execute()
                .value
            return resolveNotificationsEnabled(from: rows)
        } catch { return true }
    }

        static func updateNotifications(enabled: Bool) async {
            let client = SupabaseManager.shared.client
            let session = try? await client.auth.session
            guard let uid = session?.user.id.uuidString else { return }

            struct Upsert: Encodable { let user_id: String; let notifications_enabled: Bool }
            _ = try? await client
                .from("settings")
                .upsert(Upsert(user_id: uid, notifications_enabled: enabled), onConflict: "user_id")
                .execute()
        }

    static func updateFullName(_ name: String) async throws {
        let client = SupabaseManager.shared.client
        guard let uid = AuthService.currentUserIDFast() else { return }

        struct Patch: Encodable { let full_name: String }
        _ = try await client
            .from("profiles")
            .update(Patch(full_name: name))
            .eq("id", value: uid)
            .execute()
    }
}

struct ProfileSettingsRow: Decodable { let notifications_enabled: Bool? }

extension ProfileService {
    /// Extracts the notifications toggle value, defaulting to true when rows are missing or null.
    static func resolveNotificationsEnabled(from rows: [ProfileSettingsRow]) -> Bool {
        rows.first?.notifications_enabled ?? true
    }
}
