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

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anon,
            options: SupabaseClientOptions(
                auth: .init(flowType: .pkce)
            )
        )

    }
}

private struct DeviceTokenInsert: Encodable {
    let user_id: UUID
    let token: String
    let platform: String
}

extension SB {
    func registerDeviceToken(_ token: String) async throws {
        // Only register if a user is authenticated
        guard let user = client.auth.currentUser else {
            print("⚠️ No authenticated user; skipping device token registration")
            return
        }

        let payload = DeviceTokenInsert(user_id: user.id, token: token, platform: "ios")

        _ = try await client
            .from("device_tokens")
            .upsert(payload)
            .execute()

        print("✅ Device token registered successfully")
    }
}
