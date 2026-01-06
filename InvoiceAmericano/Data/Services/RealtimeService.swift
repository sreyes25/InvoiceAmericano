//
//  RealtimeService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

// NOTE: Updated to use InsertAction + subscribeWithError per latest supabase-swift Realtime v2.

import Foundation
import Supabase
import Realtime

/// Handles live invoice activity updates via Supabase Realtime v2.
enum RealtimeService {
    private static var channel: RealtimeChannelV2?

    static func start() async {
        // Avoid duplicates
        if channel != nil { return }

        guard let uid = SupabaseManager.shared.currentUserIDString() else {
            print("⚠️ Realtime start skipped: missing user id")
            return
        }

        // Create v2 Realtime channel
        // Note: channel config types are internal in current supabase-swift; rely on RLS to scope events per user.
        let ch = SupabaseManager.shared.client.realtimeV2.channel("activity-feed")

        // Listen for INSERTs on public.invoice_activity (Supabase Realtime v2 Swift API)
        _ = ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "invoice_activity"
        ) { payload in
            // payload.record is [String: AnyJSON]
            let row = payload.record

            let eventString = extractEvent(row)

            // Notify on main thread
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .activityInserted,
                    object: nil,
                    userInfo: ["event": eventString]
                )

                let message = notificationMessage(for: eventString)
                if let message {
                    LocalNotify.show(title: message.title, body: message.body)
                }
            }
        }

        // Subscribe with updated v2 call (subscribe() is deprecated; use subscribeWithError)
        do {
            try await ch.subscribeWithError()
            channel = ch
            print("✅ Realtime channel 'activity-feed' started")
        } catch {
            print("❌ Realtime subscribe failed: \(error)")
        }
    }

    static func stop() async {
        if let ch = channel {
            await ch.unsubscribe()
            channel = nil
            print("🛑 Realtime channel stopped")
        }
    }
}

extension Notification.Name {
    static let activityInserted = Notification.Name("activityInserted")
}

extension RealtimeService {
    static func extractEvent(_ record: [String: AnyJSON]) -> String {
        guard let any = record["event"] else { return "" }
        if let s = any.stringValue { return s }
        if let s = any.value as? String { return s }
        return String(describing: any)
    }

    static func notificationMessage(for event: String) -> (title: String, body: String)? {
        switch event {
        case "paid":
            return ("Invoice Paid", "A client just paid an invoice.")
        case "overdue":
            return ("Invoice Overdue", "An invoice is now overdue.")
        case "due_soon":
            return ("Invoice Due Soon", "An invoice is due soon.")
        case "":
            return nil
        default:
            return ("Invoice Activity", "New event: \(event)")
        }
    }
}
