//
//  OpenAILogoService.swift
//  InvoiceAmericano
//
//  Created by Codex on 3/4/26.
//

import Foundation
import UIKit

enum OpenAILogoServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case api(String)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OpenAI API key. Set OPENAI_KEY in your hidden config."
        case .invalidResponse:
            return "The AI service returned an invalid response."
        case .api(let message):
            return message
        case .decodeFailed:
            return "Couldn't decode generated image data."
        }
    }
}

enum OpenAILogoService {
    private static let endpoint = URL(string: "https://api.openai.com/v1/images/generations")!

    static func generateLogos(prompt: String, count: Int = 4) async throws -> [UIImage] {
        let key = AppSupport.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw OpenAILogoServiceError.missingAPIKey }

        let clampedCount = min(max(count, 1), 4)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 35

        struct Body: Encodable {
            let model: String
            let prompt: String
            let n: Int
            let size: String
            let background: String?
            let output_format: String?
        }

        let bodyWithTransparency = Body(
            model: "gpt-image-1",
            prompt: prompt,
            n: clampedCount,
            size: "1024x1024",
            background: "transparent",
            output_format: "png"
        )
        request.httpBody = try JSONEncoder().encode(bodyWithTransparency)

        var (data, response) = try await URLSession.shared.data(for: request)
        guard var http = response as? HTTPURLResponse else { throw OpenAILogoServiceError.invalidResponse }

        struct APIErrorEnvelope: Decodable {
            struct APIErrorValue: Decodable { let message: String? }
            let error: APIErrorValue?
        }

        if !(200..<300).contains(http.statusCode) {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            let message = (envelope?.error?.message ?? "").lowercased()
            let unsupported = message.contains("unknown parameter") || message.contains("unsupported")
            if unsupported && (message.contains("background") || message.contains("output_format")) {
                // Fallback for older image API variants that reject transparency params.
                request.httpBody = try JSONEncoder().encode(
                    Body(
                        model: "gpt-image-1",
                        prompt: prompt,
                        n: clampedCount,
                        size: "1024x1024",
                        background: nil,
                        output_format: nil
                    )
                )
                (data, response) = try await URLSession.shared.data(for: request)
                guard let retryHTTP = response as? HTTPURLResponse else { throw OpenAILogoServiceError.invalidResponse }
                http = retryHTTP
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            let message = envelope?.error?.message ?? "OpenAI request failed (\(http.statusCode))."
            throw OpenAILogoServiceError.api(message)
        }

        struct GenerationResponse: Decodable {
            struct Item: Decodable {
                let b64_json: String?
                let url: String?
            }
            let data: [Item]
        }

        let decoded = try JSONDecoder().decode(GenerationResponse.self, from: data)
        if decoded.data.isEmpty { throw OpenAILogoServiceError.invalidResponse }

        var images: [UIImage] = []
        for item in decoded.data {
            if let b64 = item.b64_json,
               let bytes = Data(base64Encoded: b64),
               let image = UIImage(data: bytes) {
                images.append(image)
                continue
            }

            if let urlString = item.url,
               let url = URL(string: urlString) {
                let (remoteData, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: remoteData) {
                    images.append(image)
                }
            }
        }

        if images.isEmpty { throw OpenAILogoServiceError.decodeFailed }
        return images
    }
}
