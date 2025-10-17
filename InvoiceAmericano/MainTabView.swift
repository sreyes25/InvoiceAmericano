//
//  MainTabView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/2/25.
//

import SwiftUI

struct MainTabView: View {
    @State private var unreadCount = 0
    var body: some View {
        TabView {
            // HOME
            NavigationStack {
                HomeViewPlaceholder()
            }
            .tabItem { Label("Home", systemImage: "house") }

            // INVOICES
            NavigationStack {
                InvoiceListView()
            }
            .tabItem { Label("Invoices", systemImage: "doc.plaintext") }

            // CLIENTS
            NavigationStack {
                ClientListView()
            }
            .tabItem { Label("Clients", systemImage: "person.2") }

            // ACTIVITY
            NavigationStack {
                ActivityAllView(unreadCount: $unreadCount)
            }
            .tabItem { Label("Activity", systemImage: "bell") }
            .badge(unreadCount)

            // ACCOUNT
            NavigationStack {
                AccountViewPlaceholder()
            }
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .task {
            // Start realtime updates
            await RealtimeService.start()

            // Initial unread count
            unreadCount = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .activityInserted)) { _ in
            // When a new event arrives, bump badge count immediately
            unreadCount += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("activityUnreadChanged"))) { note in
            if let n = note.userInfo?["count"] as? Int {
                unreadCount = n
            }
        }
    }
}

// MARK: - Placeholders (replace with your real views when ready)

private struct HomeViewPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Home").font(.title3).bold()
            Text("Quick actions, KPIs, and recent invoices go here.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("New Invoice", action: {})
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Home")
    }
}

private struct ClientListPlaceholder: View {
    var body: some View {
        List {
            ForEach(0..<8, id: \.self) { i in
                VStack(alignment: .leading) {
                    Text("Client \(i)").bold()
                    Text("client\(i)@example.com").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Clients")
        .toolbar { Button { } label: { Image(systemName: "person.badge.plus") } }
    }
}


private struct AccountViewPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Account").font(.title3).bold()
            Text("Profile, preferences, branding, and sign out.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Log Out") {
                Task { try? await AuthService.signOut() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Account")
    }
}
