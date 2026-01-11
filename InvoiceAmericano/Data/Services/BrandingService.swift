//
//  BrandingService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/29/25.
//

import Foundation
import Supabase
import PostgREST

enum BrandingService {
    // Simple in-memory cache
    private static var cached: Branding?

    struct Branding: Decodable {
        let businessName: String
        let tagline: String?
        let accentHex: String?
        let logoPublicURL: String?
    }

    static func invalidateCache() { cached = nil }

    /// Update the in-memory cache with a fully resolved Branding object.
    /// Useful after saving branding settings so callers immediately see changes.
    static func setCachedBranding(_ branding: Branding) {
        cached = branding
    }

    static var cachedBusinessName: String? { cached?.businessName }

    static var cachedAccentHex: String? { cached?.accentHex }

    static func setCachedBusinessName(_ s: String) {
        if let c = cached {
            cached = Branding(businessName: s,
                              tagline: c.tagline,
                              accentHex: c.accentHex,
                              logoPublicURL: c.logoPublicURL)
        } else {
            cached = Branding(businessName: s, tagline: nil, accentHex: nil, logoPublicURL: nil)
        }
    }

    /// Load branding: prefer profiles.display_name, fallback to branding_settings, else "Your Business".
    static func loadBranding() async throws -> Branding? {
        if let c = cached { return c }

        let client = SupabaseManager.shared.client
        let uid = try SupabaseManager.shared.requireCurrentUserIDString()

        // 1) profiles.display_name
        struct ProfileRow: Decodable { let display_name: String? }
        let profile: ProfileRow = try await client
            .from("profiles")
            .select("display_name")
            .eq("id", value: uid)
            .single()
            .execute()
            .value

        // 2) branding_settings (fetch as array, then .first)
        struct BrandingRow: Decodable {
            let business_name: String?
            let tagline: String?
            let accent_hex: String?
            let logo_public_url: String?
        }

        let rows: [BrandingRow] = try await client
            .from("branding_settings")
            .select("business_name,tagline,accent_hex,logo_public_url")
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value

        let row = rows.first

        func cleaned(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        let resolvedName =
            cleaned(profile.display_name)
            ?? cleaned(row?.business_name)
            ?? "Your Business"

        let result = Branding(
            businessName: resolvedName,
            tagline: cleaned(row?.tagline),
            accentHex: cleaned(row?.accent_hex),
            logoPublicURL: cleaned(row?.logo_public_url)
        )
        cached = result
        return result
    }
}
