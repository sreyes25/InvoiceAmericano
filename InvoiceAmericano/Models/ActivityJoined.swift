//
//  ActivityJoined.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/20/25.
//

import Foundation

public struct ActivityJoined: Decodable, Identifiable {
    public let id: UUID
    public let invoice_id: UUID
    public let event: String
    public let created_at: String
    public let invoice: Inv?

    public struct Inv: Decodable {
        public let number: String?
        public let client: Client?
    }

    public struct Client: Decodable {
        public let name: String?
    }
}
