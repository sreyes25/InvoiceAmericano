//
//  AppEnv.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import Foundation
enum AppEnv {
    static var supabaseURL: URL {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let u = URL(string: s) else { fatalError("Missing SupabaseURL") }
        return u
    }
    static var supabaseAnonKey: String {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String else {
            fatalError("Missing SupabaseAnonKey")
        }
        return k
    }
}
