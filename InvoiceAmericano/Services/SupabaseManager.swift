//
//  SupabaseManager.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/5/25.
//

import Foundation
import Supabase

enum Env {
    static let supabaseURL = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co")!         // e.g. https://xxx.supabase.co
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBiaGx5bm1nbWdyemh5bm5ybW5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwOTU5MTcsImV4cCI6MjA3MjY3MTkxN30.lu-ICiQNv6MTq1CD4mn21UANFwjVDO41jADzPDCzOuw"              // anon public key
}

final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: Env.supabaseURL,
            supabaseKey: Env.supabaseAnonKey
        )
    }
}
