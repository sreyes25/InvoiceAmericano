//
//  InvoiceAmericanoApp.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//
import SwiftUI
import Supabase
import PostgREST
import Auth

@main
struct InvoiceAmericanoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAuthed = (AuthService.currentUserIDFast() != nil)
    @State private var showOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var onboardingStatusError: String?

    private func recomputeOnboardingFlag() async {
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let uid = session.user.id

            struct ProfileRow: Decodable { let display_name: String? }
            let row: ProfileRow = try await client
                .from("profiles")
                .select("display_name")
                .eq("id", value: uid.uuidString)
                .single()
                .execute()
                .value

            let shouldShowOnboarding = (row.display_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            await MainActor.run {
                self.onboardingStatusError = nil
                self.showOnboarding = shouldShowOnboarding
                self.hasCompletedOnboarding = !self.showOnboarding
            }
        } catch {
            await MainActor.run {
                self.onboardingStatusError = "You’re offline. Using your last saved onboarding status."
                // If we previously completed onboarding, keep the user in the app despite network errors.
                self.showOnboarding = self.hasCompletedOnboarding ? false : true
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                
                if isAuthed {
                    if showOnboarding {
                        OnboardingFlow()
                    } else {
                        MainTabView()
                    }
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
                    if isAuthed { await recomputeOnboardingFlag() }
                }
            }
            // Flip UI when sign-in/sign-out happens
            .onReceive(NotificationCenter.default.publisher(for: .authDidChange)) { _ in
                isAuthed = (AuthService.currentUserIDFast() != nil)
                if isAuthed {
                    Task { await recomputeOnboardingFlag() }
                    Task { await NotificationService.syncDeviceTokenIfNeeded() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .onboardingDidFinish)) { _ in
                Task { await recomputeOnboardingFlag() }
            }
            // Re-check session when app becomes active (covers token refresh / cold starts)
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    isAuthed = (AuthService.currentUserIDFast() != nil)
                    if isAuthed {
                        Task { await recomputeOnboardingFlag() }
                    }
                }
            }
            .task {
                AnalyticsService.track(.appLaunch)
                if isAuthed {
                    await recomputeOnboardingFlag()
                    await NotificationService.syncDeviceTokenIfNeeded()
                }
            }
            .overlay(alignment: .top) {
                if let onboardingStatusError {
                    Text(onboardingStatusError)
                        .font(.footnote.weight(.semibold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .padding(.top, 12)
                }
            }
        }
    }
}

extension Notification.Name {
    static let onboardingDidFinish = Notification.Name("OnboardingDidFinish")
}
