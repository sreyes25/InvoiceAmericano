//
//  AuthService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//

import Foundation
import Supabase

enum AuthService {
    static var session: Session? { SB.shared.client.auth.session }
    static var userID: String? { session?.user.id.uuidString }

    static func signUp(email: String, password: String) async throws {
        _ = try await SB.shared.client.auth.signUp(email: email, password: password)
        // Depending on Supabase email settings, user may need to confirm via email.
        // After confirmation, signIn will return a valid session.
    }

    static func signIn(email: String, password: String) async throws {
        _ = try await SB.shared.client.auth.signIn(email: email, password: password)
        // session now available via SB.shared.client.auth.session
    }

    static func signOut() async throws {
        try await SB.shared.client.auth.signOut()
    }
}
