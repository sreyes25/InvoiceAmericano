//
//  Profile.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.
//

import Foundation

public struct Profile: Decodable, Identifiable {
    public let id: UUID
    public let email: String?
    public let full_name: String?
}
