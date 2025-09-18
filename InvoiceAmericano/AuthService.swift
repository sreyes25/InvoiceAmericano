//
//  AuthService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import Foundation
import Supabase

enum AuthService {
    static var userID: String? {
        SB.shared.client.auth.currentUser?.id.uuidString
    }

    static func signUp(email: String, password: String) async throws {
        _ = try await SB.shared.client.auth.signUp(email: email, password: password)
    }

    static func signIn(email: String, password: String) async throws {
        _ = try await SB.shared.client.auth.signIn(email: email, password: password)
    }

    static func signOut() async throws {
        try await SB.shared.client.auth.signOut()
    }
}
