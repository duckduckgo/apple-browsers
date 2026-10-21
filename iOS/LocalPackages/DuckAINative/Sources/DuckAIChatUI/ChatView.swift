//
//  ChatView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import DuckAIChatCore
import SwiftUI

public enum ChatSurface: Sendable {
    case contextualSheet
    case fullScreen
    /// Inside a browser tab, whose own chrome supplies the title and input.
    case tab
}

/// What the chat asks of the screen that hosts it.
public struct ChatActions {
    public var close: () -> Void
    public var continueInWeb: (ChatContext) -> Void

    public init(close: @escaping () -> Void, continueInWeb: @escaping (ChatContext) -> Void) {
        self.close = close
        self.continueInWeb = continueInWeb
    }
}

/// What a chat with no messages yet shows, like the frontend's welcome.
public struct ChatEmptyState {
    public var image: Image
    public var title: String

    public init(image: Image, title: String) {
        self.image = image
        self.title = title
    }
}

public struct ChatView: View {
    @Bindable var session: ChatSession
    let surface: ChatSurface
    let actions: ChatActions
    let showsComposer: Bool
    let emptyState: ChatEmptyState?
    @State private var draft = ""

    /// `showsComposer` is false when the host app drives the session from its own input.
    public init(session: ChatSession, surface: ChatSurface, actions: ChatActions, showsComposer: Bool = true,
                emptyState: ChatEmptyState? = nil) {
        self.session = session
        self.surface = surface
        self.actions = actions
        self.showsComposer = showsComposer
        self.emptyState = emptyState
    }

    public var body: some View {
        VStack(spacing: 0) {
            if surface == .fullScreen {
                header
            }
            if let emptyState, session.state.messages.isEmpty, session.state.liveReply == nil {
                welcome(emptyState)
            } else {
                transcript
            }
            if showsComposer {
                composer
            }
        }
        .background(DuckAIChatTokens.Color.pageBackground)
    }

    private var header: some View {
        HStack {
            Button(action: actions.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("NativeChat.Close")
            Spacer()
            VStack(spacing: 0) {
                Text("Duck.ai")
                    .font(DuckAIChatTokens.Typography.h3.font)
                Text("On device · \(session.descriptor.displayName)")
                    .font(DuckAIChatTokens.Typography.tableCell.font)
                    .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
        .padding(.horizontal, DuckAIChatTokens.Spacing.s8)
    }

    private func welcome(_ emptyState: ChatEmptyState) -> some View {
        VStack(spacing: DuckAIChatTokens.Spacing.s12) {
            Spacer()
            emptyState.image
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text(emptyState.title)
                .font(DuckAIChatTokens.Typography.h3.font)
                .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
            Text("Answered on this device by \(modelName)")
                .font(DuckAIChatTokens.Typography.subtitle.font)
                .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
            Spacer()
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DuckAIChatTokens.Spacing.s16)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("NativeChat.Welcome")
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(turns.enumerated()), id: \.offset) { index, messages in
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(messages) { message in
                                    messageView(message)
                                }
                                if index == turns.count - 1 {
                                    currentReply
                                }
                            }
                        }
                        if turns.isEmpty {
                            currentReply
                        }
                    }
                    Color.clear.frame(height: 57).id(bottomID)
                }
                .padding(.horizontal, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.state) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: Message) -> some View {
        switch message {
        case .user(let user):
            UserMessageView(message: user)
        case .assistant(let assistant):
            VStack(alignment: .leading, spacing: 0) {
                AssistantPartsView(parts: assistant.parts, isStreaming: false, modelName: modelName,
                                   isActive: assistant.id == session.state.messages.last?.id && session.state.liveReply == nil)
                if assistant.id == lastAssistantID, session.state.liveReply == nil {
                    ReplyActions(text: plainText(assistant.parts), canRedo: session.state.canRedo, redo: session.redo,
                                 continueInWeb: { actions.continueInWeb(session.state.context) })
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var currentReply: some View {
        if let live = session.state.liveReply {
            if live.parts.isEmpty {
                StatusLine(stage: live.stage, availability: session.state.availability, download: session.download)
            } else {
                AssistantPartsView(parts: live.parts, isStreaming: true, modelName: modelName, isActive: true)
            }
        }
        if case .error(let error) = session.state.status {
            ErrorRow(error: error, canRedo: session.state.canRedo, redo: session.redo)
        }
    }

    private var turns: [[Message]] {
        var groups: [[Message]] = []
        for message in session.state.messages {
            if case .user = message {
                groups.append([message])
            } else if groups.isEmpty {
                groups.append([message])
            } else {
                groups[groups.count - 1].append(message)
            }
        }
        return groups
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: DuckAIChatTokens.Spacing.s8) {
            TextField("Ask anything", text: $draft, axis: .vertical)
                .font(DuckAIChatTokens.Typography.body.font)
                .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
                .tint(DuckAIChatTokens.Color.accent)
                .lineLimit(1...6)
                .padding(.vertical, DuckAIChatTokens.Spacing.s12)
                .padding(.leading, DuckAIChatTokens.Spacing.s16)
                .accessibilityIdentifier("NativeChat.Composer")
                .onSubmit(send)
            if session.state.canStop {
                Button(action: session.stop) {
                    Image(systemName: "stop.circle.fill").font(.system(size: 32))
                }
                .foregroundStyle(DuckAIChatTokens.Color.accent)
                .accessibilityLabel("Stop")
                .accessibilityIdentifier("NativeChat.Stop")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                }
                .foregroundStyle(DuckAIChatTokens.Color.accent)
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("NativeChat.Send")
            }
        }
        .padding(.trailing, DuckAIChatTokens.Spacing.s8)
        .padding(.vertical, DuckAIChatTokens.Spacing.s4)
        .background(DuckAIChatTokens.Color.inputBackground, in: RoundedRectangle(cornerRadius: DuckAIChatTokens.Radius.input))
        .overlay(RoundedRectangle(cornerRadius: DuckAIChatTokens.Radius.input).stroke(DuckAIChatTokens.Color.inputBorder))
        .padding(DuckAIChatTokens.Spacing.s12)
    }

    private var canSend: Bool {
        session.state.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        session.send(draft)
        draft = ""
    }

    private var modelName: String {
        session.descriptor.modelName.isEmpty ? session.descriptor.displayName : session.descriptor.modelName
    }

    private var lastAssistantID: MessageID? {
        session.state.messages.last { if case .assistant = $0 { true } else { false } }?.id
    }

    private func plainText(_ parts: [AssistantPart]) -> String {
        parts.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined(separator: "\n\n")
    }

    private let bottomID = "bottom"
}

private struct StatusLine: View {
    let stage: LoadingStage
    let availability: ProviderAvailability
    let download: () -> Void

    var body: some View {
        switch (stage, availability) {
        case (.waitingForModel, .needsDownload(let bytes)):
            DownloadCard(bytes: bytes, download: download)
        case (.waitingForModel, .downloading(let fraction)):
            ProgressRow(title: "Downloading model", fraction: fraction)
        case (.provider(.loadingModel(let fraction)), _):
            ProgressRow(title: "Loading model", fraction: fraction)
        case (.provider(.readingInput(let tokens, let fraction)), _):
            ProgressRow(title: "Reading \(tokens.formatted()) tokens", fraction: fraction)
        default:
            ProgressRow(title: "Thinking", fraction: nil)
        }
    }
}

private struct ProgressRow: View {
    let title: String
    let fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            AssistantHeading(title: "Thinking", isLoading: true)
            if title != "Thinking" {
                Text(title)
                    .font(DuckAIChatTokens.Typography.subtitle.font)
                    .lineSpacing(DuckAIChatTokens.Typography.subtitle.lineSpacing)
                    .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
            }
            if let fraction {
                ProgressView(value: fraction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .accessibilityIdentifier("NativeChat.Status")
    }
}

private struct DownloadCard: View {
    let bytes: Int64
    let download: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DuckAIChatTokens.Spacing.s12) {
            Text("Download the on-device model")
                .font(DuckAIChatTokens.Typography.h3.font)
            Text("Chats are answered on this device. The model is \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).")
                .font(DuckAIChatTokens.Typography.body.font)
                .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
            Button("Download", action: download)
                .buttonStyle(.borderedProminent)
                .tint(DuckAIChatTokens.Color.accent)
                .accessibilityIdentifier("NativeChat.Download")
        }
        .padding(DuckAIChatTokens.Spacing.s16)
        .background(DuckAIChatTokens.Color.surfaceTertiary, in: RoundedRectangle(cornerRadius: DuckAIChatTokens.Radius.codeOuter))
    }
}

private struct ErrorRow: View {
    let error: ChatError
    let canRedo: Bool
    let redo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            AssistantHeading(title: "Something went wrong", isError: true)
            Text(message)
                .font(DuckAIChatTokens.Typography.body.font)
                .lineSpacing(DuckAIChatTokens.Typography.body.lineSpacing)
                .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
                .padding(.bottom, 12)
            if canRedo {
                ChatIconButton(symbol: "arrow.clockwise", label: "Redo", action: redo)
                    .accessibilityIdentifier("NativeChat.Redo")
                    .padding(.leading, -8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var message: String {
        switch error {
        case .modelNotDownloaded: "The on-device model isn't downloaded."
        case .modelUnavailable(let reason): reason
        case .inputTooLong: "That's too much text for the on-device model."
        case .conversationTooLong: "This chat is too long. Start a new chat."
        case .emptyResponse: "No response was generated."
        case .network: "Check your connection and try again."
        case .rateLimited: "Too many requests. Try again later."
        case .unknown: "Something went wrong."
        }
    }
}

private struct ReplyActions: View {
    let text: String
    let canRedo: Bool
    let redo: () -> Void
    let continueInWeb: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ChatCopyButton(text: text)
            if canRedo {
                ChatIconButton(symbol: "arrow.clockwise", label: "Redo", action: redo)
                    .accessibilityIdentifier("NativeChat.Redo")
            }
            Spacer(minLength: 0)
            Button("Continue in Duck.ai", action: continueInWeb)
                .font(DuckAIChatTokens.Typography.subtitle.font)
                .padding(.horizontal, 8)
                .frame(minHeight: 36)
                .buttonStyle(ChatGhostButtonStyle())
                .accessibilityIdentifier("NativeChat.ContinueInWeb")
        }
        .padding(.leading, -8)
    }
}
