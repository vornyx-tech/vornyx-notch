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

    /// Text that has arrived but is not on screen yet. See `appendDelta`.
    private var pendingDelta: String = ""
    private var flushTask: Task<Void, Never>?

    /// How often streamed text is handed to the view.
    ///
    /// Gemini sends a reply in dozens of small pieces a second, and every one
    /// of them republishes the transcript: SwiftUI then re-lays out and
    /// re-parses the Markdown of every bubble on screen. Batching a frame's
    /// worth at a time makes a long reply arrive markedly quicker while looking
    /// no different - the text is moving faster than this either way.
    private static let deltaFlushInterval = Duration.milliseconds(60)

    private init() { Self.upgradeStaleModel() }

    /// Move users off a model id the app used to ship as its default. Without
    /// this, anyone who installed before today keeps the old model forever,
    /// since their preference file already holds a value. A model the user
    /// typed themselves is theirs to keep.
    private static func upgradeStaleModel() {
        guard !Defaults[.didUpgradeGeminiModel] else { return }
        Defaults[.didUpgradeGeminiModel] = true
        if Defaults.Keys.supersededGeminiModels.contains(Defaults[.geminiModel]) {
            Defaults[.geminiModel] = GeminiClient.newestModel
        }
    }

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
        // Nothing queued from the previous reply may leak into this one.
        flushTask?.cancel()
        flushTask = nil
        pendingDelta = ""

        let client = GeminiClient(
            model: Defaults[.geminiModel],
            systemPrompt: Defaults[.aiSystemPrompt],
            thinking: Defaults[.aiThinking]
        )
        let history = messages

        task?.cancel()
        task = Task { [weak self] in
            do {
                try await client.stream(history: history) { delta in
                    self?.appendDelta(delta)
                }
                guard !Task.isCancelled else { return }
                self?.endStream()
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
    ///
    /// The first one goes straight to the screen - that is the wait the user
    /// actually feels - and the rest queue up for the next flush rather than
    /// each redrawing the transcript on their own.
    private func appendDelta(_ delta: String) {
        guard isStreaming, let last = messages.last, last.role == .assistant, !last.isError else {
            isStreaming = true
            messages.append(AIChatMessage(role: .assistant, text: delta))
            return
        }

        pendingDelta += delta
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.deltaFlushInterval)
            guard !Task.isCancelled else { return }
            self?.flushDelta()
        }
    }

    private func flushDelta() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingDelta.isEmpty else { return }
        defer { pendingDelta = "" }

        guard let last = messages.last, last.role == .assistant, !last.isError else { return }
        messages[messages.count - 1].text += pendingDelta
    }

    /// The reply is complete: show whatever is still queued before settling.
    private func endStream() {
        flushDelta()
        isThinking = false
        isStreaming = false
    }

    private func finish(with message: AIChatMessage) {
        flushDelta()
        messages.append(message)
        isThinking = false
        isStreaming = false
    }

    func cancel() {
        task?.cancel()
        task = nil
        // Keep the part of the reply that did arrive - stopping should not
        // swallow the sentence already on its way to the screen.
        flushDelta()
        isThinking = false
        isStreaming = false
    }

    func clear() {
        cancel()
        messages.removeAll()
    }
}
