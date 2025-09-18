//
//  AnyEncodable.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/18/25.
//

import Foundation

// Erases the concrete Encodable type and marks it cross-actor safe.
public struct AnyEncodable: Encodable, @unchecked Sendable {
    private let _encode: (Encoder) throws -> Void
    public init<T: Encodable>(_ value: T) { self._encode = value.encode }
    public func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
