//
//  AuthViewModel.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import SwiftUI
import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isAuthenticated = (AuthService.userID != nil)
    @Published var error: String?

    func signIn() async {
        do { try await AuthService.signIn(email: email, password: password)
             isAuthenticated = (AuthService.userID != nil)
        } catch { self.error = error.localizedDescription }
    }
    func signUp() async {
        do { try await AuthService.signUp(email: email, password: password)
             isAuthenticated = (AuthService.userID != nil)
        } catch { self.error = error.localizedDescription }
    }
    func signOut() async {
        do { try await AuthService.signOut(); isAuthenticated = false }
        catch { self.error = error.localizedDescription }
    }
}
