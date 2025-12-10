//
//  InvoiceDetail.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/7/25.
//

// Models/InvoiceDetail.swift
import Foundation

struct LineItemRow: Decodable, Identifiable {
    let id: UUID
    let title: String?
    let description: String
    let qty: Int
    let unit_price: Double
    let amount: Double
}

struct InvoiceDetail: Decodable {
    let id: UUID
    let number: String
    let status: String
    let subtotal: Double?
    let tax: Double?
    let total: Double?
    let currency: String?
    let created_at: String?
    let issued_at: String?        // <-- we use this in the PDF
    let dueDate: String?          // maps from due_date
    let checkout_url: String?
    let notes: String?
    let client: ClientRef?
    let line_items: [LineItemRow]

    enum CodingKeys: String, CodingKey {
        case id, number, status, subtotal, tax, total, currency, created_at
        case issued_at                 // <-- include this
        case dueDate = "due_date"      // snake_case -> camelCase
        case notes
        case checkout_url, client, line_items
    }
}
