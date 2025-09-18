//
//  ClientsView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import SwiftUI

struct ClientsView: View {
    @StateObject var vm = ClientsViewModel()

    var body: some View {
        NavigationView {
            List(vm.items) { c in
                VStack(alignment: .leading) {
                    Text(c.name).font(.headline)
                    if let e = c.email { Text(e).font(.caption).foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Clients")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task { await vm.refresh() }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                TextField("Client name", text: $vm.name).textFieldStyle(.roundedBorder)
                TextField("Client email (optional)", text: $vm.email).textFieldStyle(.roundedBorder)
                Button("Add Client") { Task { await vm.add() } }.buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .alert(vm.error ?? "", isPresented: .constant(vm.error != nil)) { Button("OK") { vm.error = nil } }
    }
}
