//
//  AnalyticsService.swift
//  InvoiceAmericano
//
//  Created by OpenAI on 11/21/25.
//

import Foundation

/// Lightweight analytics helper that intentionally avoids capturing PII.
/// - Event names are limited to explicit funnel steps.
/// - Metadata is whitelisted, redacted, and truncated before logging.
/// - No network transmission is performed; this is a local audit trail only.
enum AnalyticsService {
    /// Event names allowed in the app. Keep these aligned with the core funnel.
    enum Event: String {
        case appLaunch            = "app_launch"
        case authSignUpStarted    = "auth_sign_up_started"
        case authSignUpSucceeded  = "auth_sign_up_succeeded"
        case authSignInStarted    = "auth_sign_in_started"
        case authSignInSucceeded  = "auth_sign_in_succeeded"
        case authSignedOut        = "auth_signed_out"
        case onboardingCompleted  = "onboarding_completed"
        case invoiceCreated       = "invoice_created"
        case invoiceSent          = "invoice_sent"
    }

    /// Allow only harmless context fields; drop anything else to avoid leaking PII.
    private static let allowedMetadataKeys: Set<String> = [
        "source",       // screen or feature origin, e.g., "home" or "invoices_tab"
        "method",       // e.g., "password" or "apple"
        "status",       // success / failure state labels
        "channel",      // sharing channel such as "messages" or "mail"
        "count"         // numeric counts (as string) for aggregates
    ]

    /// Patterns that would hint at sensitive data. If present, the metadata entry is dropped.
    private static let sensitivePatterns: [String] = [
        "token", "secret", "key", "email", "password", "account", "number", "name", "address"
    ]

    /// Record an analytics event with sanitized metadata.
    static func track(_ event: Event, metadata: [String: String]? = nil) {
        let sanitized = sanitize(metadata)

        #if DEBUG
        // Local audit only; no network transmission.
        if let sanitized {
            print("📈 analytics event=\(event.rawValue) meta=\(sanitized)")
        } else {
            print("📈 analytics event=\(event.rawValue) meta={}")
        }
        #endif
    }

    /// Whitelist, redact, and truncate metadata.
    private static func sanitize(_ metadata: [String: String]?) -> [String: String]? {
        guard let metadata, !metadata.isEmpty else { return nil }

        var safe: [String: String] = [:]
        for (key, value) in metadata {
            guard allowedMetadataKeys.contains(key) else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Drop anything that looks like it could contain sensitive data.
            let lower = trimmed.lowercased()
            guard sensitivePatterns.first(where: { lower.contains($0) }) == nil else { continue }
            guard !lower.contains("@") else { continue } // heuristic: likely an email

            // Truncate to avoid accidentally keeping long payloads.
            let safeValue = String(trimmed.prefix(64))
            safe[key] = safeValue
        }

        return safe.isEmpty ? nil : safe
    }
}
