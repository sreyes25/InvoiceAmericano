//
//  SB.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import Foundation
import Supabase

final class SB {
    static let shared = SB()
    let client: SupabaseClient
    private init() {
        client = SupabaseClient(
            supabaseURL: AppEnv.supabaseURL,
            supabaseKey: AppEnv.supabaseAnonKey
        )
    }
}
