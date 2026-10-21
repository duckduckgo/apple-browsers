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

public struct ChatView: View {
    @Bindable var session: ChatSession
    let surface: ChatSurface
    let actions: ChatActions
    @State private var draft = ""

    public init(session: ChatSession, surface: ChatSurface, actions: ChatActions) {
        self.session = session
        self.surface = surface
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 0) {
            if surface == .fullScreen {
                header
            }
            transcript
            composer
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

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DuckAIChatTokens.Spacing.s24) {
                    ForEach(session.state.messages) { message in
                        switch message {
                        case .user(let user):
                            UserMessageView(message: user)
                        case .assistant(let assistant):
                            VStack(alignment: .leading, spacing: DuckAIChatTokens.Spacing.s8) {
                                AssistantPartsView(parts: assistant.parts, isStreaming: false)
                                if assistant.id == lastAssistantID, session.state.liveReply == nil {
                                    ReplyActions(text: plainText(assistant.parts),
                                                 canRedo: session.state.canRedo,
                                                 redo: session.redo,
                                                 continueInWeb: { actions.continueInWeb(session.state.context) })
                                }
                            }
                        }
                    }
                    if let live = session.state.liveReply {
                        if live.parts.isEmpty {
                            StatusLine(stage: live.stage, availability: session.state.availability, download: session.download)
                        } else {
                            AssistantPartsView(parts: live.parts, isStreaming: true)
                        }
                    }
                    if case .error(let error) = session.state.status {
                        ErrorRow(error: error, canRedo: session.state.canRedo, redo: session.redo)
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(DuckAIChatTokens.Spacing.s16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.state) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
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
        HStack(spacing: DuckAIChatTokens.Spacing.s8) {
            if let fraction {
                ProgressView(value: fraction).frame(width: 80)
            } else {
                ProgressView()
            }
            Text(title)
                .font(DuckAIChatTokens.Typography.tableCell.font)
                .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
        }
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
        HStack(spacing: DuckAIChatTokens.Spacing.s12) {
            Text(message)
                .font(DuckAIChatTokens.Typography.body.font)
                .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
            if canRedo {
                Button("Redo", action: redo)
                    .accessibilityIdentifier("NativeChat.Redo")
            }
        }
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
        HStack(spacing: DuckAIChatTokens.Spacing.s16) {
            Button {
                copyToPasteboard(text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel("Copy")
            if canRedo {
                Button(action: redo) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Redo")
                .accessibilityIdentifier("NativeChat.Redo")
            }
            Spacer()
            Button("Continue in Duck.ai", action: continueInWeb)
                .font(DuckAIChatTokens.Typography.tableCell.font)
                .accessibilityIdentifier("NativeChat.ContinueInWeb")
        }
        .buttonStyle(.plain)
        .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
    }

    private func copyToPasteboard(_ text: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = text
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }
}
