//
//  ActivityEvent.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import Foundation

struct ActivityEvent: Identifiable, Decodable {
    let id: UUID
    let invoice_id: UUID
    let event: String
    let metadata: [String: AnyDecodable]?
    let actor_user: UUID?
    let created_at: String
}

// Helper for decoding JSONB loosely
struct AnyDecodable: Decodable {}
