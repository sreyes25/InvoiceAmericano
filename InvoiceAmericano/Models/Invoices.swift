//
//  Invoices.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/5/25.
//
import Foundation

// Shape returned by the select with an embedded client object.
struct InvoiceRow: Identifiable, Decodable {
    let id: UUID
    let number: String
    let status: String
    let clientId: UUID?     // maps from DB "client_id"
    let total: Double?        // can be NULL while drafting
    let created_at: String?   // decode as String to avoid format issues
    let dueDate: String?      // maps from DB "due_date"
    let client: ClientRef?
    let sent_at: String?

    enum CodingKeys: String, CodingKey {
        case id, number, status, total, client
        case created_at
        case dueDate = "due_date"
        case sent_at
        case clientId = "client_id"
    }
}

struct ClientRef: Decodable {
    let name: String?
}

enum InvoiceStatus: String, CaseIterable {
    case all = "All"
    case sent = "sent"
    case paid = "paid"
    case overdue = "overdue"

    var filterValue: String? {
        switch self {
        case .all, .overdue: return nil  // handled client‑side
        default: return rawValue
        }
    }
}
