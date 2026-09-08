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

        let client = GeminiClient(
            model: Defaults[.geminiModel],
            systemPrompt: Defaults[.aiSystemPrompt]
        )
        let history = messages

        task?.cancel()
        task = Task { [weak self] in
            do {
                let reply = try await client.send(history: history)
                guard !Task.isCancelled else { return }
                self?.finish(with: AIChatMessage(role: .assistant, text: reply))
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

    private func finish(with message: AIChatMessage) {
        messages.append(message)
        isThinking = false
    }

    func cancel() {
        task?.cancel()
        task = nil
        isThinking = false
    }

    func clear() {
        cancel()
        messages.removeAll()
    }
}
