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
        // TODO: put your REAL values here
        let url = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co")!
        let anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBiaGx5bm1nbWdyemh5bm5ybW5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwOTU5MTcsImV4cCI6MjA3MjY3MTkxN30.lu-ICiQNv6MTq1CD4mn21UANFwjVDO41jADzPDCzOuw"

        client = SupabaseClient(supabaseURL: url, supabaseKey: anon)
        // Optional: keep session fresh
        // Task { try? await client.auth.initialize() }
    }
}
