//
//  AppDelegate.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/9/25.
//

import Foundation
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Debug: confirm notification authorization state + APNs registration attempt
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            print("🔔 Notification settings:", settings.authorizationStatus.rawValue,
                  "alert:", settings.alertSetting.rawValue,
                  "badge:", settings.badgeSetting.rawValue,
                  "sound:", settings.soundSetting.rawValue)

            print("📲 Calling NotificationService.registerIfAuthorized()")
            await NotificationService.registerIfAuthorized()
            print("📲 Finished NotificationService.registerIfAuthorized()")
        }
        // Ensure local notifications are authorized (banners/sounds/badges) even while app is foreground
        LocalNotify.requestIfNeeded()
        return true
    }

    // Device token → hex string
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("🟢 APNs DEVICE TOKEN:", token)
        NotificationService.cache(deviceToken: token)
        Task { await NotificationService.syncDeviceTokenIfNeeded(force: true) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("🔴 APNs REGISTRATION FAILED:", error)
    }

    // Show banners/sounds/badges while app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
