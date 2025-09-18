//
//  Models.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import Foundation

public struct DBClient: Codable, Identifiable, Hashable, @unchecked Sendable {
    public let id: String
    public let user_id: String
    public var name: String
    public var email: String?
    public var created_at: String?
}

public struct NewClientPayload: Codable, @unchecked Sendable {
    public let id: String
    public let user_id: String
    public let name: String
    public let email: String?
}
