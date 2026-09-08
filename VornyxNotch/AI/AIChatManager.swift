//
//  AIChatManager.swift
//  VornyxNotch
//

import Defaults
import Foundation

struct AIChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
    var isError: Bool = false
    let date: Date = .init()
}

@MainActor
final class AIChatManager: ObservableObject {
    static let shared = AIChatManager()

    @Published private(set) var messages: [AIChatMessage] = []
    @Published private(set) var isThinking: Bool = false
    /// True between the first streamed chunk and the end of the reply.
    @Published private(set) var isStreaming: Bool = false
    @Published var draft: String = ""

    private var task: Task<Void, Never>?

    private init() {}

    var hasAPIKey: Bool { KeychainStore.hasGeminiAPIKey }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isThinking else { return }

        draft = ""
        messages.append(AIChatMessage(role: .user, text: prompt))
        isThinking = true
        isStreaming = false

        let client = GeminiClient(
            model: Defaults[.geminiModel],
            systemPrompt: Defaults[.aiSystemPrompt]
        )
        let history = messages

        task?.cancel()
        task = Task { [weak self] in
            do {
                try await client.stream(history: history) { delta in
                    self?.appendDelta(delta)
                }
                guard !Task.isCancelled else { return }
                self?.isThinking = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.finish(
                    with: AIChatMessage(
                        role: .assistant,
                        text: error.localizedDescription,
                        isError: true
                    )
                )
            }
        }
    }

    /// First chunk opens a new assistant bubble; the rest grow it in place.
    private func appendDelta(_ delta: String) {
        if let last = messages.last, last.role == .assistant, !last.isError, isStreaming {
            messages[messages.count - 1].text += delta
        } else {
            isStreaming = true
            messages.append(AIChatMessage(role: .assistant, text: delta))
        }
    }

    private func finish(with message: AIChatMessage) {
        messages.append(message)
        isThinking = false
        isStreaming = false
    }

    func cancel() {
        task?.cancel()
        task = nil
        isThinking = false
        isStreaming = false
    }

    func clear() {
        cancel()
        messages.removeAll()
    }
}
