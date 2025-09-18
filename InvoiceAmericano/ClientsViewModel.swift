//
//  ClientsViewModel.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import Foundation
import Combine

@MainActor
final class ClientsViewModel: ObservableObject {
    @Published var items: [DBClient] = []
    @Published var name = ""
    @Published var email = ""
    @Published var error: String?

    func refresh() async {
        do { items = try await ClientService.list() }
        catch { self.error = error.localizedDescription }
    }

    func add() async {
        do {
            try await ClientService.create(name: name, email: email.isEmpty ? nil : email)
            name = ""; email = ""
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
