//
//  MainTabView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/2/25.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @State private var unreadCount: Int = 0
    @State private var justClearedBadge: Bool = false
    
    private var badgeText: String? {
        unreadCount == 0 ? nil : String(unreadCount)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // HOME
            NavigationStack {
                HomeViewPlaceholder()
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            // INVOICES
            NavigationStack {
                InvoiceListView()
            }
            .tabItem { Label("Invoices", systemImage: "doc.plaintext") }
            .tag(1)

            // CLIENTS
            NavigationStack {
                ClientListView()
            }
            .tabItem { Label("Clients", systemImage: "person.2") }
            .tag(2)

            // ACTIVITY
            NavigationStack {
                ActivityAllView()
                    .navigationDestination(for: UUID.self) { invoiceId in
                        InvoiceDetailView(invoiceId: invoiceId)
                    }
            }
            .tabItem { Label("Activity", systemImage: "bell") }
            .tag(3)
            .badge(badgeText)
            
            // ACCOUNT
            NavigationStack {
                AccountView()
            }
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
            .tag(4)
        }
        .task {
            // Load badge count initially
            if let c = try? await ActivityService.countUnread() {
                await MainActor.run { unreadCount = c }
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 3 {
                // Viewing Activity: clear badge immediately and mark server-side as read
                Task {
                    await MainActor.run {
                        unreadCount = 0
                        justClearedBadge = true
                    }
                    try? await ActivityService.markAllAsRead()
                }
            } else {
                // If we just cleared it this session, keep it at 0 and skip a recount once.
                if justClearedBadge {
                    justClearedBadge = false
                    unreadCount = 0
                } else {
                    Task {
                        if let c = try? await ActivityService.countUnread() {
                            await MainActor.run { unreadCount = c }
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .activityUnreadChanged)) { note in
            if let n = note.userInfo?["count"] as? Int {
                unreadCount = n
            }
        }

    }
}




// MARK: - Placeholders (keep until real views replace them)

private struct HomeViewPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Home").font(.title3).bold()
            Text("Quick actions, KPIs, and recent invoices go here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("New Invoice", action: {})
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Home")
    }
}

private struct AccountViewPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Account").font(.title3).bold()
            Text("Profile, preferences, branding, and sign out.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Log Out") {
                Task { try? await AuthService.signOut() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Account")
    }
}
