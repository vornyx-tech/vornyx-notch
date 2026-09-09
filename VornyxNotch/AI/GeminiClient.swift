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
    /// Let the model reason before answering. Slower, and rarely worth it for
    /// the one-or-two-sentence answers this window has room for.
    var thinking: Bool = false

    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models"

    /// The newest Flash model. Flash rather than Pro on purpose: Pro cannot be
    /// told to think less, which is the whole point of the setting below.
    static let newestModel = "gemini-3.8-flash"

    /// Opens the TLS connection to Google ahead of the first message.
    ///
    /// DNS plus handshake is most of a second on a cold connection, and it lands
    /// squarely on the first thing you type. Doing it when the tab opens moves
    /// that cost into the time you spend typing. The response is discarded -
    /// only the pooled connection matters, and `URLSession.shared` keys its pool
    /// by host, so the real request reuses it.
    static func warmUp() {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request).resume()
    }

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
        do {
            try await stream(history: history, tuningThinking: true, onDelta: onDelta)
        } catch let GeminiError.badResponse(status, _) where status == 400 && !thinking {
            // A 400 is how a model refuses the thinking level we asked for, and
            // it says only "Request contains an invalid argument" - the field is
            // never named, so there is nothing to match on. Models come and go
            // faster than this app ships, so rather than track which one takes
            // what, drop the setting and ask again. If the request was really
            // bad for some other reason it fails the same way a second time and
            // that error is the one the user sees. A slow reply beats no reply.
            try await stream(history: history, tuningThinking: false, onDelta: onDelta)
        }
    }

    private func stream(
        history: [AIChatMessage],
        tuningThinking: Bool,
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
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(for: history, tuningThinking: tuningThinking)
        )
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

    /// How many past messages go back to Gemini with each question.
    ///
    /// The whole transcript used to be resent every turn, so a long chat made
    /// every question slower than the one before it - the model has to read the
    /// entire history before it can start answering. A follow-up in a notch
    /// window depends on the last few turns, not on the first one.
    private static let historyLimit = 12

    private func requestBody(
        for history: [AIChatMessage],
        tuningThinking: Bool = true
    ) -> [String: Any] {
        var body: [String: Any] = [
            "contents": history.filter { !$0.isError }
                .suffix(Self.historyLimit)
                .map { message in
                    [
                        "role": message.role == .user ? "user" : "model",
                        "parts": [["text": message.text]],
                    ]
                }
        ]
        if !systemPrompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }
        if tuningThinking, let config = thinkingConfig() {
            body["generationConfig"] = ["thinkingConfig": config]
        }
        return body
    }

    /// Gemini 3 cannot be told to stop thinking, only to think less, so "off"
    /// means the lowest level rather than none.
    ///
    /// `low` and not `minimal`: every model that takes a thinking level accepts
    /// `low`, while `minimal` is rejected outright by some of the Flash models.
    /// The speed difference between the two is small next to the difference
    /// from the default, so the one that always works wins.
    private func thinkingConfig() -> [String: Any]? {
        thinking ? nil : ["thinkingLevel": "low"]
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
