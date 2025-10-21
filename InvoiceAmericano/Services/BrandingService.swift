//
//  BrandingService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.
//

import Foundation
import Supabase

struct BrandingSettings: Codable {
    let businessName: String
    let tagline: String?
    let accentHex: String
    let logoPublicURL: String?
}

enum BrandingService {
    // Table: settings (per user)
    // Columns (suggested):
    // user_id uuid (pk/fk auth.users.id)
    // business_name text
    // tagline text
    // accent_hex text
    // logo_public_url text
    //
    // RLS: user_id = auth.uid()
    // Policy: SELECT/UPSERT by owner

    static func loadBranding() async throws -> BrandingSettings? {
        let client = SupabaseManager.shared.client
        let session = try? await client.auth.session
        guard let uid = session?.user.id.uuidString else { return nil }

        struct Row: Decodable {
            let business_name: String?
            let tagline: String?
            let accent_hex: String?
            let logo_public_url: String?
        }

        let rows: [Row] = try await client
            .from("settings")
            .select()
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value

        guard let r = rows.first else { return nil }

        return BrandingSettings(
            businessName: r.business_name ?? "",
            tagline: r.tagline,
            accentHex: r.accent_hex ?? "#1E90FF",
            logoPublicURL: r.logo_public_url
        )
    }

    static func upsertBranding(
        businessName: String,
        tagline: String?,
        accentHex: String,
        logoPublicURL: String?
    ) async throws {
        let client = SupabaseManager.shared.client
        let session = try? await client.auth.session
        guard let uid = session?.user.id.uuidString else { throw NSError(domain: "auth", code: 401) }

        struct UpsertRow: Encodable {
            let user_id: String
            let business_name: String
            let tagline: String?
            let accent_hex: String
            let logo_public_url: String?
        }

        let payload = UpsertRow(
            user_id: uid,
            business_name: businessName,
            tagline: tagline?.nilIfBlank,
            accent_hex: accentHex,
            logo_public_url: logoPublicURL?.nilIfBlank
        )

        _ = try await client
            .from("settings")
            .upsert(payload, onConflict: "user_id")
            .execute()
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
