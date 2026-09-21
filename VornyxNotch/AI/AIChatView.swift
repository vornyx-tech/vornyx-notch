//
//  AIChatView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// The AI chat as a notch tab: transcript on top, one-line composer at the
/// bottom. Sized for a wide, short strip rather than a tall chat window.
struct AIChatView: View {
    @EnvironmentObject var vm: VornyxViewModel
    @StateObject private var chat = AIChatManager.shared
    @FocusState private var composerFocused: Bool
    /// Balances begin/endInteraction so the counter can't drift.
    @State private var holdingNotch = false
    /// Transcript height, and how much of it is on screen.
    @State private var transcriptContentHeight: CGFloat = 0
    @State private var transcriptVisibleHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            if !chat.hasAPIKey {
                missingKeyNotice
            } else {
                transcript
                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            // Permit typing without stealing focus from the app you were in.
            guard chat.hasAPIKey else { return }
            VornyxNotchSkyLightWindow.setKeyboardInputEnabled(true)
            GeminiClient.warmUp()
        }
        .onDisappear {
            // Keyboard input stays on: `ContentView` turns it off when the
            // notch closes.
            releaseNotch()
        }
        .onChange(of: chat.isThinking) { _, thinking in
            // Pin the notch only while a reply is arriving, since cutting one
            // off half-written loses it.
            thinking ? holdNotch() : releaseNotch()
        }
        .onExitCommand {
            composerFocused = false
        }
    }

    private func holdNotch() {
        guard !holdingNotch else { return }
        holdingNotch = true
        SharingStateManager.shared.beginInteraction()
    }

    private func releaseNotch() {
        guard holdingNotch else { return }
        holdingNotch = false
        SharingStateManager.shared.endInteraction()
    }

    private var missingKeyNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(Color.effectiveAccent)
            Text("No Gemini API key")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text("Add one in Settings → AI to chat here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if chat.messages.isEmpty {
                        Text("Ask anything.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 12)
                    }
                    ForEach(chat.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if chat.isThinking && !chat.isStreaming {
                        ThinkingDots()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 2)
                .measuringHeight(into: $transcriptContentHeight)
            }
            .scrollIndicators(.never)
            // The transcript takes the swipe away from the close gesture.
            .scrollableNotchContent()
            .measuringHeight(into: $transcriptVisibleHeight)
            // Ask the notch to stretch; past its allowance this scrolls.
            .preference(
                key: NotchContentFitKey.self,
                value: NotchContentFit(
                    content: transcriptContentHeight,
                    visible: transcriptVisibleHeight
                )
            )
            .onChange(of: chat.messages.count) {
                MarkdownCache.prune(keeping: chat.messages)
                scrollToEnd(proxy)
            }
            .onChange(of: chat.isThinking) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.smooth(duration: 0.25)) {
            if chat.isThinking {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = chat.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: AIChatMessage) -> some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.isError ? AttributedString(message.text) : styled(message))
                .font(.callout)
                .textSelection(.enabled)
                .foregroundStyle(message.isError ? Color.red.opacity(0.9) : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .notchSurface(
                    RoundedRectangle(cornerRadius: 12, style: .continuous),
                    stroke: 0,
                    tint: isUser
                        ? Color.effectiveAccent.opacity(0.35)
                        : Color(nsColor: .secondarySystemFill).opacity(0.6),
                    glassTint: isUser ? Color.effectiveAccent.opacity(0.45) : Color.black.opacity(0.28))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// The message's rendered Markdown, parsed once per change rather than
    /// once per redraw.
    private func styled(_ message: AIChatMessage) -> AttributedString {
        MarkdownCache.value(for: message, parse: parseMarkdown)
    }

    /// Renders the model's Markdown rather than showing its syntax. Bold runs
    /// take the accent colour and italics a softer tint.
    private func parseMarkdown(_ text: String) -> AttributedString {
        guard var attributed = try? AttributedString(
            markdown: text,
            // Inline-only keeps paragraph breaks intact.
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            return AttributedString(text)
        }

        // Collect first: mutating while iterating runs invalidates them.
        let runs = attributed.runs.map { ($0.range, $0.inlinePresentationIntent) }
        for (range, intent) in runs {
            guard let intent else { continue }
            if intent.contains(.stronglyEmphasized) {
                attributed[range].foregroundColor = Color.effectiveAccent
                attributed[range].inlinePresentationIntent = nil
            } else if intent.contains(.emphasized) {
                attributed[range].foregroundColor = Color.effectiveAccent.opacity(0.75)
                attributed[range].inlinePresentationIntent = nil
            } else if intent.contains(.code) {
                attributed[range].font = .system(.callout, design: .monospaced)
                attributed[range].foregroundColor = .white.opacity(0.9)
            }
        }
        return attributed
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message Gemini…", text: $chat.draft, axis: .horizontal)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.white)
                .focused($composerFocused)
                .onSubmit { chat.send() }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .notchSurface(
                    Capsule(), stroke: 0,
                    tint: Color(nsColor: .secondarySystemFill).opacity(0.5),
                    glassTint: Color.black.opacity(0.28))

            Button {
                chat.isThinking ? chat.cancel() : chat.send()
            } label: {
                Image(systemName: chat.isThinking ? "stop.fill" : "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(
                        chat.canSend || chat.isThinking ? Color.effectiveAccent : Color.gray
                    ))
            }
            .springyTile(hoverScale: 1.08, pressScale: 0.92, hoverBrightness: 0.1)
            .disabled(!chat.canSend && !chat.isThinking)

            Button {
                chat.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .springyTile(hoverScale: 1.1, pressScale: 0.9, hoverBrightness: 0.2)
            .disabled(chat.messages.isEmpty)
        }
    }
}

/// Parsed Markdown, kept between redraws and keyed by the message it came
/// from. One entry per message, replaced as a streaming reply grows.
@MainActor
private enum MarkdownCache {
    private static var entries: [UUID: (text: String, value: AttributedString)] = [:]

    static func value(
        for message: AIChatMessage,
        parse: (String) -> AttributedString
    ) -> AttributedString {
        if let hit = entries[message.id], hit.text == message.text { return hit.value }
        let parsed = parse(message.text)
        entries[message.id] = (message.text, parsed)
        return parsed
    }

    /// Drop entries for messages that are gone.
    static func prune(keeping messages: [AIChatMessage]) {
        guard entries.count > messages.count else { return }
        let live = Set(messages.map(\.id))
        entries = entries.filter { live.contains($0.key) }
    }
}

/// Three dots that breathe while a reply is in flight.
private struct ThinkingDots: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == phase ? 0.9 : 0.3))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .notchSurface(
            RoundedRectangle(cornerRadius: 12, style: .continuous), stroke: 0,
            tint: Color(nsColor: .secondarySystemFill).opacity(0.6),
            glassTint: Color.black.opacity(0.28))
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
        }
    }
}
