//
//  SupabaseStorageService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.
//

import Foundation
import Supabase

enum SupabaseStorageService {
    private static let brandingBucket = "branding"

    /// Upload or replace the user's branding logo in the Supabase storage bucket.
    static func uploadBrandingLogo(data: Data) async throws -> String {
        let client = SupabaseManager.shared.client

        // Safely get the current user ID (lowercased for RLS match)
        let uid = try SupabaseManager.shared.requireCurrentUserIDString(lowercased: true)

        // Consistent lowercase path to match RLS policy
        let path = "users/\(uid)/branding/logo.png"
        print("[Storage] Uploading logo for uid=\(uid) to path=\(path)")

        // Upload file, allowing overwrite (upsert)
        try await client.storage
            .from(Self.brandingBucket)
            .upload(path, data: data, options: FileOptions(
                contentType: "image/png",
                upsert: true
            ))

        // Return the public URL for the uploaded file
        let url = try client.storage
            .from(Self.brandingBucket)
            .getPublicURL(path: path)

        print("[Storage] Logo uploaded successfully. URL: \(url.absoluteString)")
        return url.absoluteString
    }
}
