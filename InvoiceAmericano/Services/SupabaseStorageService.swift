//
//  SupabaseStorageService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.
//

import Foundation
import Supabase

enum SupabaseStorageService {
    // Bucket: branding (public or signed URLs)
    static func uploadBrandingLogo(data: Data) async throws -> String {
        let client = SupabaseManager.shared.client
        let session = try? await client.auth.session
        guard let uid = session?.user.id.uuidString else { throw NSError(domain: "auth", code: 401) }

        // Path: user/{uid}/logo.png (overwrite)
        let path = "user/\(uid)/logo.png"

        // Upload (set upsert true to replace)
        try await client.storage
            .from("branding")
            .upload(
                path,
                data: data,
                options: FileOptions(
                    contentType: "image/png",
                    upsert: true
                )
            )

        // Public URL (assumes bucket 'branding' is public)
        let url = try client.storage.from("branding").getPublicURL(path: path)
        return url.absoluteString
    }
}
