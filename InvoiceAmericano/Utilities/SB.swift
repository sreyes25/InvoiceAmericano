//
//  SB.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//

import Foundation
import Supabase

final class SB {
    static let shared = SB()
    let client: SupabaseClient

    private init() {
        let url = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co")!
        let anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBiaGx5bm1nbWdyemh5bm5ybW5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwOTU5MTcsImV4cCI6MjA3MjY3MTkxN30.lu-ICiQNv6MTq1CD4mn21UANFwjVDO41jADzPDCzOuw"

        client = SupabaseClient(supabaseURL: url, supabaseKey: anon)

    }
}

private struct DeviceTokenInsert: Encodable {
    let user_id: UUID
    let token: String
    let platform: String
}

extension SB {
    func registerDeviceToken(_ token: String) async throws {
        // Safely obtain user ID depending on your SDK version
        let uid: UUID
        if let user = client.auth.currentUser {
            uid = user.id
        } else if let sessionUser = try? await client.auth.session.user.id {
            uid = sessionUser
        } else {
            print("⚠️ No authenticated user; skipping device token registration")
            return
        }

        let payload = DeviceTokenInsert(user_id: uid, token: token, platform: "ios")

        _ = try await client
            .from("device_tokens")
            .upsert(payload)
            .execute()

        print("✅ Device token registered successfully")
    }
}
