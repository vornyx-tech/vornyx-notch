//
//  GeminiClient.swift
//  VornyxNotch
//

import Foundation

enum GeminiError: LocalizedError {
    case missingAPIKey
    case badResponse(status: Int, message: String?)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a Gemini API key in Settings → AI."
        case .badResponse(let status, let message):
            if let message, !message.isEmpty { return message }
            return "Gemini returned HTTP \(status)."
        case .emptyReply:
            return "Gemini returned an empty reply."
        }
    }
}

/// Thin client over the Gemini `generateContent` endpoint. Deliberately small:
/// one request, one reply, whole conversation sent each time.
struct GeminiClient {
    var model: String
    var systemPrompt: String

    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models"

    func send(history: [AIChatMessage]) async throws -> String {
        guard let key = KeychainStore.geminiAPIKey else { throw GeminiError.missingAPIKey }

        guard let url = URL(string: "\(Self.endpoint)/\(model):generateContent") else {
            throw GeminiError.badResponse(status: 0, message: "Bad model name.")
        }

        var body: [String: Any] = [
            "contents": history.filter { !$0.isError }.map { message in
                [
                    "role": message.role == .user ? "user" : "model",
                    "parts": [["text": message.text]],
                ]
            }
        ]
        if !systemPrompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            throw GeminiError.badResponse(status: status, message: Self.errorMessage(from: data))
        }

        guard let text = Self.firstText(from: data), !text.isEmpty else {
            throw GeminiError.emptyReply
        }
        return text
    }

    /// Pull `candidates[0].content.parts[*].text` out of the response.
    private static func firstText(from data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else { return nil }

        return parts.compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Gemini reports problems as `{"error": {"message": "..."}}`.
    private static func errorMessage(from data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }
}
