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

        // Create v2 Realtime channel
        let ch = SupabaseManager.shared.client.realtimeV2.channel("activity-feed")

        // Listen for INSERTs on public.invoice_activity (Supabase Realtime v2 Swift API)
        _ = ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "invoice_activity"
        ) { payload in
            // payload.record is [String: AnyJSON]
            let row = payload.record

            // Extract event type
            var eventString = ""
            if let any = row["event"] {
                if let s = any.stringValue { eventString = s }
                else if let s = any.value as? String { eventString = s }
                else { eventString = String(describing: any) }
            }

            // Notify on main thread
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .activityInserted,
                    object: nil,
                    userInfo: ["event": eventString]
                )

                switch eventString {
                case "paid":
                    LocalNotify.show(title: "Invoice Paid", body: "A client just paid an invoice.")
                case "overdue":
                    LocalNotify.show(title: "Invoice Overdue", body: "An invoice is now overdue.")
                case "due_soon":
                    LocalNotify.show(title: "Invoice Due Soon", body: "An invoice is due soon.")
                default:
                    if !eventString.isEmpty {
                        LocalNotify.show(title: "Invoice Activity", body: "New event: \(eventString)")
                    }
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
