//
//  RealtimeService.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import Foundation
import Supabase

enum RealtimeService {
    private static var channel: RealtimeChannelV2?

    static func start() async {
        // avoid duplicates
        if channel != nil { return }

        // Create a V2 channel
        let ch = SupabaseManager.shared.client.realtimeV2.channel("activity-feed")

        // Listen for INSERTs on public.invoice_activity using the typed API
        let _ = ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "invoice_activity"
        ) { insert in
            let dict = insert.record
            guard let any = dict["event"],
                  case let .string(event) = any else { return }

            // Hop to main for UI-related work (NotificationCenter + LocalNotify)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .activityInserted, object: nil, userInfo: ["event": event])

                switch event {
                case "paid":
                    LocalNotify.show(title: "Invoice Paid", body: "A client just paid an invoice.")
                case "overdue":
                    LocalNotify.show(title: "Invoice Overdue", body: "An invoice is now overdue.")
                case "due_soon":
                    LocalNotify.show(title: "Invoice Due Soon", body: "An invoice is due soon.")
                default:
                    break
                }
            }
        }

        // Subscribe (V2 non-async; throws)
        do {
            try await ch.subscribeWithError()
        } catch {
            print("Realtime subscribe error:", error)
        }
        channel = ch
    }

    static func stop() async {
        await channel?.unsubscribe()
        channel = nil
    }
}

extension Notification.Name {
    static let activityInserted = Notification.Name("activityInserted")
}
