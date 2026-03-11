//
//  Invoices.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/5/25.
//
import Foundation

// Shape returned by the select with an embedded client object.
struct InvoiceRow: Identifiable, Codable {
    let id: UUID
    let number: String
    let status: String
    let clientId: UUID?     // maps from DB "client_id"
    let total: Double?        // can be NULL while drafting
    let created_at: String?   // decode as String to avoid format issues
    let dueDate: String?      // maps from DB "due_date"
    let client: ClientRef?
    let sent_at: String?
    let checkout_url: String?
    let pdf_saved_at: String?

    enum CodingKeys: String, CodingKey {
        case id, number, status, total, client
        case created_at
        case dueDate = "due_date"
        case sent_at
        case checkout_url
        case pdf_saved_at
        case clientId = "client_id"
    }
}

struct ClientRef: Codable {
    let name: String?
    let colorHex: String?

    enum CodingKeys: String, CodingKey {
        case name
        case colorHex = "color_hex"
    }
}

enum InvoiceStatus: String, CaseIterable {
    case all = "All"
    case open = "open"
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

enum InvoicePaymentMethod: String, Codable, CaseIterable, Identifiable {
    case none
    case zelle
    case check
    case stripe
    case venmo
    case cashApp = "cash_app"
    case ach
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .zelle: return "Zelle"
        case .check: return "Check"
        case .stripe: return "Stripe payment link"
        case .venmo: return "Venmo"
        case .cashApp: return "Cash App"
        case .ach: return "Bank Transfer (ACH)"
        case .custom: return "Other"
        }
    }

    var detailsPlaceholder: String {
        switch self {
        case .none:
            return ""
        case .zelle:
            return "Email or phone for Zelle"
        case .check:
            return ""
        case .stripe:
            return ""
        case .venmo:
            return "@username or payment handle"
        case .cashApp:
            return "$cashtag"
        case .ach:
            return "Bank name, routing/account (or instructions)"
        case .custom:
            return "Describe how the client should pay"
        }
    }

    var requiresDetails: Bool {
        self == .zelle || self == .custom
    }

    var requiresAddress: Bool {
        self == .check
    }
}

struct InvoicePaymentInfo: Codable, Equatable {
    let method: InvoicePaymentMethod
    let details: String?
    let mailingAddress: String?

    var displayLine: String {
        if let details, !details.isEmpty {
            return "\(method.title): \(details)"
        }
        if let mailingAddress, !mailingAddress.isEmpty {
            return "\(method.title): \(mailingAddress)"
        }
        return method.title
    }

    var pdfLines: [String] {
        switch method {
        case .zelle:
            if let details, !details.isEmpty {
                return ["Zelle: \(details)"]
            }
            return ["Zelle"]
        case .check:
            if let mailingAddress, !mailingAddress.isEmpty {
                return ["Check by mail:", mailingAddress]
            }
            return ["Check by mail"]
        case .stripe:
            return ["Stripe payment link will be included when sending."]
        default:
            if let details, !details.isEmpty {
                return ["\(method.title): \(details)"]
            }
            return [method.title]
        }
    }
}

enum InvoiceNotesCodec {
    private static let marker = "[IA_PAYMENT_META_V1]"

    static func compose(userNotes: String, payment: InvoicePaymentInfo?) -> String? {
        let cleanNotes = trimmedOrNil(userNotes)
        let cleanPayment = normalizedPayment(payment)

        if cleanNotes == nil && cleanPayment == nil {
            return nil
        }

        guard let cleanPayment else {
            return cleanNotes
        }

        let encodedPayment: String? = {
            do {
                let data = try JSONEncoder().encode(cleanPayment)
                return data.base64EncodedString()
            } catch {
                return nil
            }
        }()

        guard let encodedPayment else {
            return cleanNotes
        }

        let paymentBlock = marker + encodedPayment
        if let cleanNotes {
            return cleanNotes + "\n\n" + paymentBlock
        }
        return paymentBlock
    }

    static func extract(from storedNotes: String?) -> (userNotes: String?, payment: InvoicePaymentInfo?) {
        guard let storedNotes, !storedNotes.isEmpty else {
            return (nil, nil)
        }

        guard let markerRange = storedNotes.range(of: marker) else {
            return (trimmedOrNil(storedNotes), nil)
        }

        let userNotesPart = String(storedNotes[..<markerRange.lowerBound])
        let userNotes = trimmedOrNil(userNotesPart)

        let encodedPart = String(storedNotes[markerRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let data = Data(base64Encoded: encodedPart),
            let decoded = try? JSONDecoder().decode(InvoicePaymentInfo.self, from: data)
        else {
            return (userNotes, nil)
        }

        return (userNotes, normalizedPayment(decoded))
    }

    private static func normalizedPayment(_ payment: InvoicePaymentInfo?) -> InvoicePaymentInfo? {
        guard let payment else { return nil }
        guard payment.method != .none else { return nil }

        let details = trimmedOrNil(payment.details)
        let mailingAddress = trimmedOrNil(payment.mailingAddress)

        if payment.method.requiresDetails, details == nil {
            return nil
        }
        if payment.method.requiresAddress, mailingAddress == nil {
            return nil
        }

        return InvoicePaymentInfo(
            method: payment.method,
            details: details,
            mailingAddress: mailingAddress
        )
    }

    private static func trimmedOrNil(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
