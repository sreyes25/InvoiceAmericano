//
//  Language.swift
//  InvoiceAmericano
//
//  Created by Codex on 3/31/26.
//

import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case spanish = "es"

    static let storageKey = "appLanguageCode"
    static let defaultRawValue = preferredDefault().rawValue

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: return "en"
        case .spanish: return "es"
        }
    }

    var menuTitle: String {
        switch (self, AppLanguage.current) {
        case (.english, .spanish): return "Ingles"
        case (.spanish, .spanish): return "Espanol"
        case (.english, .english): return "English"
        case (.spanish, .english): return "Spanish"
        }
    }

    static func preferredDefault() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("es") ? .spanish : .english
    }

    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? defaultRawValue
        return AppLanguage(rawValue: raw) ?? preferredDefault()
    }
}

enum InvoiceContentLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case spanish = "es"

    static let storageKey = "defaultInvoiceLanguageCode"
    static let defaultRawValue = AppLanguage.defaultRawValue

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: return "en_US_POSIX"
        case .spanish: return "es_MX"
        }
    }

    var menuTitle: String {
        switch (self, AppLanguage.current) {
        case (.english, .spanish): return "Ingles"
        case (.spanish, .spanish): return "Espanol"
        case (.english, .english): return "English"
        case (.spanish, .english): return "Spanish"
        }
    }

    var pdfDateLabel: String {
        switch self {
        case .english: return "Date"
        case .spanish: return "Fecha"
        }
    }

    var pdfDueLabel: String {
        switch self {
        case .english: return "Due"
        case .spanish: return "Vence"
        }
    }

    var pdfBillToLabel: String {
        switch self {
        case .english: return "Bill To:"
        case .spanish: return "Facturar a:"
        }
    }

    var pdfItemLabel: String {
        switch self {
        case .english: return "ITEM"
        case .spanish: return "ITEM"
        }
    }

    var pdfDescriptionLabel: String {
        switch self {
        case .english: return "DESCRIPTION"
        case .spanish: return "DESCRIPCION"
        }
    }

    var pdfAmountLabel: String {
        switch self {
        case .english: return "AMOUNT"
        case .spanish: return "IMPORTE"
        }
    }

    var pdfItemsContinuedLabel: String {
        switch self {
        case .english: return "Items (continued)"
        case .spanish: return "Items (continuacion)"
        }
    }

    var pdfSubtotalLabel: String {
        switch self {
        case .english: return "SUBTOTAL"
        case .spanish: return "SUBTOTAL"
        }
    }

    var pdfTaxLabel: String {
        switch self {
        case .english: return "TAX"
        case .spanish: return "IMPUESTO"
        }
    }

    var pdfTotalLabel: String {
        switch self {
        case .english: return "TOTAL"
        case .spanish: return "TOTAL"
        }
    }

    var pdfPaymentDetailsLabel: String {
        switch self {
        case .english: return "Payment Details:"
        case .spanish: return "Detalles de pago:"
        }
    }

    var pdfNoteLabel: String {
        switch self {
        case .english: return "Note"
        case .spanish: return "Nota"
        }
    }

    var pdfThankYouLine: String {
        switch self {
        case .english: return "Thank you for your business!"
        case .spanish: return "Gracias por su preferencia!"
        }
    }

    var pdfEachSuffix: String {
        switch self {
        case .english: return "each"
        case .spanish: return "c/u"
        }
    }

    func defaultFooterTemplate(businessName: String) -> String {
        let cleanBusiness = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBusiness.isEmpty else {
            switch self {
            case .english:
                return "Questions about this invoice? Reach out anytime."
            case .spanish:
                return "Preguntas sobre esta factura? Comunicate con nosotros."
            }
        }

        switch self {
        case .english:
            return "Questions about this invoice? Contact \(cleanBusiness)."
        case .spanish:
            return "Preguntas sobre esta factura? Contacta a \(cleanBusiness)."
        }
    }

    func sendMessage(clientName: String, invoiceNumber: String, includesPaymentLink: Bool) -> String {
        switch (self, includesPaymentLink) {
        case (.english, true):
            return """
            Hi \(clientName),

            Please find your invoice #\(invoiceNumber) attached.

            A secure payment link is attached to this message.

            Thank you.
            """
        case (.english, false):
            return """
            Hi \(clientName),

            Please find your invoice #\(invoiceNumber) attached.

            Let me know if you have any questions.

            Thank you.
            """
        case (.spanish, true):
            return """
            Hola \(clientName),

            Te comparto tu factura #\(invoiceNumber) adjunta.

            Inclui un enlace seguro de pago en este mensaje.

            Gracias.
            """
        case (.spanish, false):
            return """
            Hola \(clientName),

            Te comparto tu factura #\(invoiceNumber) adjunta.

            Si tienes preguntas, escribeme.

            Gracias.
            """
        }
    }

    func mismatchWarning(appLanguage: AppLanguage) -> String? {
        switch (appLanguage, self) {
        case (.english, .english), (.spanish, .spanish):
            return nil
        case (.english, .spanish):
            return "App UI is in English. This invoice will be generated in Spanish."
        case (.spanish, .english):
            return "La app esta en Espanol. Esta factura se generara en Ingles."
        }
    }
}

enum I18n {
    private static func bundle(for language: AppLanguage) -> Bundle {
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return localizedBundle
        }
        return .main
    }

    static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle(for: .current), value: key, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale(identifier: AppLanguage.current.localeIdentifier), arguments: args)
    }
}

enum InvoiceStatusLocalizer {
    static func title(for status: String) -> String {
        switch status.lowercased() {
        case "open": return I18n.tr("status.open")
        case "sent": return I18n.tr("status.sent")
        case "paid": return I18n.tr("status.paid")
        case "overdue": return I18n.tr("status.overdue")
        case "all": return I18n.tr("status.all")
        default: return status.capitalized
        }
    }
}

enum ActivityEventLocalizer {
    static func title(for event: String) -> String {
        switch event.lowercased() {
        case "created": return I18n.tr("activity.created")
        case "sent": return I18n.tr("status.sent")
        case "opened": return I18n.tr("activity.opened")
        case "paid": return I18n.tr("status.paid")
        case "due_soon": return I18n.tr("activity.due_soon")
        case "overdue": return I18n.tr("status.overdue")
        case "archived": return I18n.tr("activity.archived")
        case "deleted": return I18n.tr("activity.deleted")
        default: return event.capitalized
        }
    }
}
