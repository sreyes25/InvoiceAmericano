//
//  Clients.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/6/25.
//

import Foundation

struct ClientRow: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let created_at: Date?
}
