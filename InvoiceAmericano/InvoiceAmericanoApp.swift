//
//  InvoiceAmericanoApp.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//
import SwiftUI

import SwiftUI

@main
struct InvoiceAmericanoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isAuthed = (AuthService.currentUserIDFast() != nil)

    var body: some Scene {
        WindowGroup {
            
            let root = Group {
                if isAuthed {
                    MainTabView()  // main app UI
                } else {
                    AuthView()
                }
            }
            root
                // Handle email confirmation deep-link
                .onOpenURL { url in
                    Task {
                        do {
                            try await AuthService.handleDeepLink(url)
                            isAuthed = (AuthService.currentUserIDFast() != nil)
                        } catch {
                            print("Deep link error:", error)
                        }
                    }
                }
                // Flip UI when sign-in/sign-out happens
                .onReceive(NotificationCenter.default.publisher(for: .authDidChange)) { _ in
                    isAuthed = (AuthService.currentUserIDFast() != nil)
                }
        }
    }
}
