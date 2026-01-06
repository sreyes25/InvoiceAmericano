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

/// Minimal APNs helper: caches the device token locally and mirrors it to Supabase.
///
/// - Avoids sending PII; only the token + user_id + platform are uploaded.
/// - Provides lightweight status helpers for the Settings debug section.
enum NotificationService {
    private static let defaults = UserDefaults.standard
    private static let tokenKey = "apnsDeviceToken"
    private static let lastSyncedTokenKey = "apnsLastSyncedToken"
    private static let lastSyncResultKey = "apnsLastSyncResult"
    private static let lastSyncDateKey = "apnsLastSyncDate"

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

        let lastToken = defaults.string(forKey: lastSyncedTokenKey)
        if !force, lastToken == token { return }

        struct Payload: Encodable {
            let user_id: String
            let token: String
            let platform: String
        }

        do {
            _ = try await SupabaseManager.shared.client
                .from("device_tokens")
                .upsert(Payload(user_id: uid, token: token, platform: "ios"), onConflict: "token")
                .execute()

            defaults.set(token, forKey: lastSyncedTokenKey)
            defaults.set("success", forKey: lastSyncResultKey)
            defaults.set(Date(), forKey: lastSyncDateKey)
        } catch {
            defaults.set("error", forKey: lastSyncResultKey)
            defaults.set(Date(), forKey: lastSyncDateKey)
        }
    }

    static func lastSyncSummary() -> (status: String?, date: Date?) {
        (defaults.string(forKey: lastSyncResultKey), defaults.object(forKey: lastSyncDateKey) as? Date)
    }

    static func reset() {
        defaults.removeObject(forKey: lastSyncedTokenKey)
        defaults.removeObject(forKey: lastSyncResultKey)
        defaults.removeObject(forKey: lastSyncDateKey)
    }
}
