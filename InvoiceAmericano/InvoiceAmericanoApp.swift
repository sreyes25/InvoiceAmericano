//
//  InvoiceAmericanoApp.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import SwiftUI
import Foundation   // for AuthService.userID if not already imported

@main
struct InvoiceAmericanoApp: App {
    @State private var authed = (AuthService.userID != nil)

    var body: some Scene {
        WindowGroup {
            if authed {
                // Pass a closure to MainTabView that safely signs out
                MainTabView {
                    Task {
                        do {
                            try await AuthService.signOut()
                        } catch {
                            print("Sign out failed:", error)
                        }
                        authed = false
                    }
                }
            } else {
                AuthView { authed = true }
            }
        }
    }
}
