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

    /// Streams the reply token by token via server-sent events.
    ///
    /// `generateContent` only answers once the whole reply is composed, which
    /// on a long answer means staring at nothing for several seconds. This
    /// hands back each chunk as it arrives, so text starts appearing almost
    /// immediately even though total time is unchanged.
    func stream(
        history: [AIChatMessage],
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        guard let key = KeychainStore.geminiAPIKey else { throw GeminiError.missingAPIKey }

        guard let url = URL(string: "\(Self.endpoint)/\(model):streamGenerateContent?alt=sse") else {
            throw GeminiError.badResponse(status: 0, message: "Bad model name.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(for: history))
        request.timeoutInterval = 120

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            // The error body arrives down the same stream; collect it so the
            // user sees Gemini's own message rather than a bare status code.
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw GeminiError.badResponse(status: status, message: Self.errorMessage(from: body))
        }

        var received = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }

            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", !payload.isEmpty else { continue }

            guard let chunk = Self.firstText(from: Data(payload.utf8)), !chunk.isEmpty else {
                continue
            }
            received = true
            await onDelta(chunk)
        }

        if !received { throw GeminiError.emptyReply }
    }

    private func requestBody(for history: [AIChatMessage]) -> [String: Any] {
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
        return body
    }

    func send(history: [AIChatMessage]) async throws -> String {
        guard let key = KeychainStore.geminiAPIKey else { throw GeminiError.missingAPIKey }

        guard let url = URL(string: "\(Self.endpoint)/\(model):generateContent") else {
            throw GeminiError.badResponse(status: 0, message: "Bad model name.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(for: history))
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
