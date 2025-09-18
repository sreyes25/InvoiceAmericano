//
//  MainTabView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import SwiftUI

struct MainTabView: View {
    var onSignOut: () -> Void
    var body: some View {
        TabView {
            ClientsView()
                .tabItem { Label("Clients", systemImage: "person.2") }
            Text("Invoices (next)")
                .tabItem { Label("Invoices", systemImage: "doc.plaintext") }
            Button("Sign Out") { onSignOut() }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}

