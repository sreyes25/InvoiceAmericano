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
        case .none: return I18n.tr("payment_method.none")
        case .zelle: return I18n.tr("payment_method.zelle")
        case .check: return I18n.tr("payment_method.check")
        case .stripe: return I18n.tr("payment_method.stripe")
        case .venmo: return I18n.tr("payment_method.venmo")
        case .cashApp: return I18n.tr("payment_method.cash_app")
        case .ach: return I18n.tr("payment_method.ach")
        case .custom: return I18n.tr("payment_method.custom")
        }
    }

    var detailsPlaceholder: String {
        switch self {
        case .none:
            return ""
        case .zelle:
            return I18n.tr("payment_details.zelle")
        case .check:
            return ""
        case .stripe:
            return ""
        case .venmo:
            return I18n.tr("payment_details.venmo")
        case .cashApp:
            return I18n.tr("payment_details.cash_app")
        case .ach:
            return I18n.tr("payment_details.ach")
        case .custom:
            return I18n.tr("payment_details.custom")
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
        pdfLines(language: .english)
    }

    func pdfLines(language: InvoiceContentLanguage) -> [String] {
        switch method {
        case .zelle:
            if let details, !details.isEmpty {
                return ["Zelle: \(details)"]
            }
            return ["Zelle"]
        case .check:
            if let mailingAddress, !mailingAddress.isEmpty {
                let title = (language == .spanish) ? "Cheque por correo:" : "Check by mail:"
                return [title, mailingAddress]
            }
            return [(language == .spanish) ? "Cheque por correo" : "Check by mail"]
        case .stripe:
            return [
                (language == .spanish)
                    ? "El enlace de pago de Stripe se incluira al enviar."
                    : "Stripe payment link will be included when sending."
            ]
        default:
            if let details, !details.isEmpty {
                return ["\(method.title): \(details)"]
            }
            return [method.title]
        }
    }
}

enum InvoiceNotesCodec {
    private static let paymentMarker = "[IA_PAYMENT_META_V1]"
    private static let languageMarker = "[IA_LANGUAGE_META_V1]"

    static func compose(
        userNotes: String,
        payment: InvoicePaymentInfo?,
        invoiceLanguage: InvoiceContentLanguage = .english
    ) -> String? {
        let cleanNotes = trimmedOrNil(userNotes)
        let cleanPayment = normalizedPayment(payment)
        let languageMeta: String? = (invoiceLanguage == .english)
            ? nil
            : (languageMarker + invoiceLanguage.rawValue)

        if cleanNotes == nil && cleanPayment == nil && languageMeta == nil {
            return nil
        }

        let paymentBlock: String? = {
            guard let cleanPayment else { return nil }
            do {
                let data = try JSONEncoder().encode(cleanPayment)
                return paymentMarker + data.base64EncodedString()
            } catch {
                return nil
            }
        }()

        return [cleanNotes, languageMeta, paymentBlock]
            .compactMap { $0?.trimmedNonEmpty }
            .joined(separator: "\n\n")
            .trimmedNonEmpty
    }

    static func extract(
        from storedNotes: String?
    ) -> (userNotes: String?, payment: InvoicePaymentInfo?, invoiceLanguage: InvoiceContentLanguage?) {
        guard let storedNotes, !storedNotes.isEmpty else {
            return (nil, nil, nil)
        }

        var notesBlock = storedNotes
        var decodedPayment: InvoicePaymentInfo?

        if let markerRange = storedNotes.range(of: paymentMarker) {
            notesBlock = String(storedNotes[..<markerRange.lowerBound])
            let encodedPart = String(storedNotes[markerRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: encodedPart) {
                decodedPayment = try? JSONDecoder().decode(InvoicePaymentInfo.self, from: data)
            }
        }

        var invoiceLanguage: InvoiceContentLanguage?
        var userNotesPart = notesBlock
        if let languageRange = notesBlock.range(of: languageMarker) {
            let rawLanguage = String(notesBlock[languageRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            invoiceLanguage = InvoiceContentLanguage(rawValue: rawLanguage)
            userNotesPart = String(notesBlock[..<languageRange.lowerBound])
        }

        return (
            trimmedOrNil(userNotesPart),
            normalizedPayment(decodedPayment),
            invoiceLanguage
        )
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

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
