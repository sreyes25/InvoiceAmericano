//
//  InvoiceAmericanoApp.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//
import SwiftUI

@main
struct InvoiceAmericanoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAuthed = (AuthService.currentUserIDFast() != nil)

    var body: some Scene {
        WindowGroup {
            Group {
                if isAuthed {
                    MainTabView()  // main app UI
                } else {
                    AuthView()
                }
            }
            .animation(.snappy(duration: 0.25), value: isAuthed)   // smooth flip between auth states
            .tint(.blue)                                           // global accent to match app theme
            // Handle email confirmation deep-link
            .onOpenURL { url in
                Task {
                    await AuthService.handleDeepLink(url)
                    isAuthed = (AuthService.currentUserIDFast() != nil)
                }
            }
            // Flip UI when sign-in/sign-out happens
            .onReceive(NotificationCenter.default.publisher(for: .authDidChange)) { _ in
                isAuthed = (AuthService.currentUserIDFast() != nil)
            }
            // Re-check session when app becomes active (covers token refresh / cold starts)
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    isAuthed = (AuthService.currentUserIDFast() != nil)
                }
            }
        }
    }
}
