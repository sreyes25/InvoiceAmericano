//
//  AppSupport.swift
//  InvoiceAmericano
//
//  Created by OpenAI on 11/22/25.
//

import Foundation

enum AppSupport {
    static let supportEmail = "reyesasergio@resynctechnology.com"
    static let privacyPolicyURL = URL(string: "https://invoiceamericano.app/privacy")!
    static let openAIAPIKeysURL = URL(string: "https://platform.openai.com/settings/organization/api-keys")!
    static var openAIAPIKey: String {
        // Reads from Info.plist -> OPENAI_KEY, which should be provided by your hidden .xcconfig.
        let raw = Bundle.main.object(forInfoDictionaryKey: "OPENAI_KEY") as? String ?? ""
        return raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}

extension URL {
    /// Decodes both regular query items and hash-fragment key/value pairs.
    /// Supabase links may deliver auth data in either location.
    var decodedQueryParameters: [String: String] {
        var result: [String: String] = [:]
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return result
        }

        for item in components.queryItems ?? [] {
            guard let value = item.value, !value.isEmpty else { continue }
            result[item.name] = value
            mergeNestedParameters(from: value, into: &result)
        }

        if let fragment = components.fragment, fragment.contains("=") {
            mergeNestedParameters(from: fragment, into: &result)
        }

        return result
    }

    var hasRecoveryHint: Bool {
        if decodedQueryParameters["type"]?.lowercased() == "recovery" { return true }
        let raw = absoluteString.lowercased()
        if raw.contains("type=recovery") { return true }
        if raw.contains("type%3drecovery") { return true }
        return false
    }

    private func mergeNestedParameters(from rawValue: String, into params: inout [String: String]) {
        let decoded = rawValue.removingPercentEncoding ?? rawValue
        let candidates = [rawValue, decoded]

        for candidate in candidates {
            // Nested URL value
            if let nestedURL = URL(string: candidate),
               let nestedComps = URLComponents(url: nestedURL, resolvingAgainstBaseURL: false) {
                for item in nestedComps.queryItems ?? [] {
                    guard let value = item.value, !value.isEmpty else { continue }
                    params[item.name] = value
                }
                if let fragment = nestedComps.fragment, fragment.contains("=") {
                    let fragmentURL = "invoiceamericano://fragment?\(fragment)"
                    let fragmentItems = URLComponents(string: fragmentURL)?.queryItems ?? []
                    for item in fragmentItems {
                        guard let value = item.value, !value.isEmpty else { continue }
                        params[item.name] = value
                    }
                }
            }

            // Raw key=value&key=value payload
            if candidate.contains("="), candidate.contains("&") {
                let synthetic = "invoiceamericano://params?\(candidate)"
                for item in URLComponents(string: synthetic)?.queryItems ?? [] {
                    guard let value = item.value, !value.isEmpty else { continue }
                    params[item.name] = value
                }
            }
        }
    }
}
