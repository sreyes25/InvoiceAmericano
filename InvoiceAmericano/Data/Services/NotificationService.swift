//
//  NotificationService.swift
//  InvoiceAmericano
//
//  Created by OpenAI on 11/22/25.
//

import Foundation
import UserNotifications
import UIKit
import Supabase

/// Async-safe gate to prevent overlapping token sync attempts (Swift 6 friendly).
actor TokenSyncGate {
    private var inFlight = false

    /// Runs `operation` only if no other sync is currently in flight.
    /// If a sync is already running, this returns `nil` immediately.
    func runIfNotInFlight<T>(_ operation: () async throws -> T) async rethrows -> T? {
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }
        return try await operation()
    }
}

/// Minimal APNs helper: caches the device token locally and mirrors it to Supabase.
///
/// - Avoids sending PII; only the token + user_id + platform are uploaded.
/// - Provides lightweight status helpers for the Settings debug section.
enum NotificationService {
    private static let defaults = UserDefaults.standard
    private static let tokenKey = "apnsDeviceToken"
    private static let lastSyncedTokenKey = "apnsLastSyncedToken"
    private static let lastSyncedUserIDKey = "apnsLastSyncedUserID"
    private static let lastSyncResultKey = "apnsLastSyncResult"
    private static let lastSyncDateKey = "apnsLastSyncDate"
    private static let syncGate = TokenSyncGate()

    // MARK: - Permissions
    static func currentPermissionStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Request notification authorization from a user-facing surface (Settings/Account).
    /// If granted, registers with APNs so we can obtain a device token.
    static func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            return false
        }
    }

    /// Register with APNs if the user has already granted authorization.
    static func registerIfAuthorized() async {
        let status = await currentPermissionStatus()
        guard status == .authorized || status == .provisional else { return }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Token lifecycle
    static func cache(deviceToken: String) {
        defaults.set(deviceToken, forKey: tokenKey)
    }

    static func cachedDeviceToken() -> String? {
        defaults.string(forKey: tokenKey)
    }
    

    static func syncDeviceTokenIfNeeded(force: Bool = false) async {
        guard let token = cachedDeviceToken(), !token.isEmpty else { return }
        guard let uid = SupabaseManager.shared.currentUserIDString() else { return }

        _ = await syncGate.runIfNotInFlight {
            let lastToken = defaults.string(forKey: lastSyncedTokenKey)
            let lastUserID = defaults.string(forKey: lastSyncedUserIDKey)
            if !force, lastToken == token, lastUserID == uid { return }

            struct Payload: Encodable {
                let user_id: String
                let token: String
                let platform: String
            }

            do {
                print("📲 [NotificationService] Syncing APNs token → Supabase | uid=\(uid) | tokenPrefix=\(token.prefix(10))…")

                // Use UPSERT to avoid duplicate key errors.
                // Your table already has a unique constraint on (user_id, token).
                _ = try await SupabaseManager.shared.client
                    .from("device_tokens")
                    .upsert(Payload(user_id: uid, token: token, platform: "ios"), onConflict: "user_id,token")
                    .execute()

                print("✅ [NotificationService] Token saved to device_tokens")

                defaults.set(token, forKey: lastSyncedTokenKey)
                defaults.set(uid, forKey: lastSyncedUserIDKey)
                defaults.set("success", forKey: lastSyncResultKey)
                defaults.set(Date(), forKey: lastSyncDateKey)
            } catch {
                let message = String(describing: error)
                print("🔴 [NotificationService] Token sync FAILED: \(message)")

                defaults.set("error: \(message)", forKey: lastSyncResultKey)
                defaults.set(Date(), forKey: lastSyncDateKey)
            }
        }
    }

    static func lastSyncSummary() -> (status: String?, date: Date?) {
        (defaults.string(forKey: lastSyncResultKey), defaults.object(forKey: lastSyncDateKey) as? Date)
    }

    @MainActor
    static func setAppBadgeCount(_ count: Int) async {
        if #available(iOS 17.0, *) {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(count)
            } catch {
                print("⚠️ Failed to set app badge count:", error)
            }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }

    static func reset() {
        defaults.removeObject(forKey: lastSyncedTokenKey)
        defaults.removeObject(forKey: lastSyncedUserIDKey)
        defaults.removeObject(forKey: lastSyncResultKey)
        defaults.removeObject(forKey: lastSyncDateKey)
    }
}
extension NotificationService {

    /// Marks all notifications as read for the current user.
    static func markAllNotificationsReadForCurrentUser() async {
        guard let uid = SupabaseManager.shared.currentUserIDString() else { return }

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = f.string(from: Date())

        do {
            _ = try await SupabaseManager.shared.client
                .from("notifications")
                .update(["read_at": now])
                .eq("user_id", value: uid)
                .is("read_at", value: nil)
                .execute()

            print("✅ Marked notifications as read for user:", uid)
        } catch {
            print("❌ Failed to mark notifications read:", error)
        }
    }
}
