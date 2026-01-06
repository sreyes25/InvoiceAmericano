//
//  InvoiceAmericanoTests.swift
//  InvoiceAmericanoTests
//
//  Created by Sergio Reyes on 9/19/25.
//

import Foundation
import Testing
import Realtime
@testable import InvoiceAmericano

struct InvoiceAmericanoTests {

    // MARK: Authentication
    @Test func authRedirectURLIsAppScheme() {
        let url = AuthService.defaultRedirectURL
        #expect(url.scheme == "invoiceamericano")
        #expect(url.host == "auth-callback")
    }

    // MARK: Invoice creation + filtering
    @Test func normalizeLineItemTrimsPlaceholders() {
        let draft = LineItemDraft(title: " Title ", description: " Description ", quantity: 0, unitPrice: 10)
        let normalized = InvoiceService.normalizeLineItem(draft)

        #expect(normalized.title == "Title")
        #expect(normalized.description == "Description")
        #expect(normalized.quantity == 1) // coerced to minimum quantity
        #expect(normalized.amount == 10)
    }

    @Test func normalizeLineItemFallsBackWhenEmpty() {
        let draft = LineItemDraft(title: "   ", description: "   ", quantity: -1, unitPrice: 25)
        let normalized = InvoiceService.normalizeLineItem(draft)

        #expect(normalized.title == nil)
        #expect(normalized.description == "Item")
        #expect(normalized.quantity == 1)
        #expect(normalized.amount == 25)
    }

    @Test func filterInvoicesDetectsOverdueOpenInvoices() throws {
        // Build sample rows with mixed statuses/dates
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let today = formatter.date(from: "2024-10-10")!
        let yesterday = formatter.date(from: "2024-10-09")!
        let nextWeek = formatter.date(from: "2024-10-17")!

        let overdueRow = InvoiceRow(
            id: UUID(),
            number: "A1",
            status: "open",
            clientId: nil,
            total: 10,
            created_at: nil,
            dueDate: formatter.string(from: yesterday),
            client: nil,
            sent_at: nil
        )

        let paidRow = InvoiceRow(
            id: UUID(),
            number: "A2",
            status: "paid",
            clientId: nil,
            total: 10,
            created_at: nil,
            dueDate: formatter.string(from: yesterday),
            client: nil,
            sent_at: nil
        )

        let futureRow = InvoiceRow(
            id: UUID(),
            number: "A3",
            status: "open",
            clientId: nil,
            total: 10,
            created_at: nil,
            dueDate: formatter.string(from: nextWeek),
            client: nil,
            sent_at: nil
        )

        let filtered = InvoiceService.filterInvoices([overdueRow, paidRow, futureRow], status: .overdue, today: today)
        #expect(filtered.count == 1)
        #expect(filtered.first?.id == overdueRow.id)
    }

    // MARK: Profile updates
    @Test func resolveNotificationsEnabledDefaultsToTrue() {
        let emptyRows: [ProfileSettingsRow] = []
        #expect(ProfileService.resolveNotificationsEnabled(from: emptyRows) == true)

        let explicitFalse = [ProfileSettingsRow(notifications_enabled: false)]
        #expect(ProfileService.resolveNotificationsEnabled(from: explicitFalse) == false)
    }

    // MARK: Realtime notifications
    @Test func realtimeExtractsEventAndMessages() {
        let record: [String: AnyJSON] = ["event": AnyJSON("paid")]
        let event = RealtimeService.extractEvent(record)
        #expect(event == "paid")

        let message = RealtimeService.notificationMessage(for: event)
        #expect(message?.title == "Invoice Paid")
        #expect(message?.body.contains("paid") == true)
    }
}
