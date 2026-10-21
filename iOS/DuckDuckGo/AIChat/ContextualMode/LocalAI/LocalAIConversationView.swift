//
//  LocalAIConversationView.swift
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

import DesignResourcesKit
import LocalAI
import SwiftUI
import UIKit

/// Duck.ai's design tokens, read from its web app in the dark scheme. Light values are approximations.
enum LocalAIChatPalette {
    static let background = dynamic(dark: rgb(0x111111), light: rgb(0xFFFFFF))
    static let textPrimary = dynamic(dark: .white, light: rgb(0x222222))
    static let textSecondary = dynamic(dark: .white.withAlphaComponent(0.66), light: .black.withAlphaComponent(0.6))
    static let textTertiary = dynamic(dark: .white.withAlphaComponent(0.36), light: .black.withAlphaComponent(0.36))
    /// `container-tertiary-background`: the user's message.
    static let userBubble = dynamic(dark: .white.withAlphaComponent(0.09), light: .black.withAlphaComponent(0.06))
    static let input = dynamic(dark: rgb(0x333333), light: rgb(0xFFFFFF))
    static let inputBorder = dynamic(dark: .white.withAlphaComponent(0.12), light: .black.withAlphaComponent(0.12))
    static let surface = dynamic(dark: rgb(0x222222), light: rgb(0xF2F2F2))
    static let accent = rgb(0x75B6EB)

    private static func dynamic(dark: UIColor, light: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    private static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Duck.ai sets its chat in DuckSans Product, which the app bundles; system font if it's missing.
enum LocalAIChatFont {
    /// Body text is 16 pt on a 24 pt line; SwiftUI line spacing is what's added on top of the font's own height.
    static let bodyLineSpacing: CGFloat = 5

    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .bold, .semibold: "DuckSansProduct-Bold"
        case .medium: "DuckSansProduct-Medium"
        default: "DuckSansProduct-Regular"
        }
        guard UIFont(name: name, size: size) != nil else { return .system(size: size, weight: weight) }
        return .custom(name, size: size, relativeTo: .body)
    }
}

/// A native take on Duck.ai's chat: the user's messages in bubbles, replies full width beside the Duck.ai
/// avatar, streaming in, and a "Reply…" field for follow-ups.
struct LocalAIConversationView: View {

    @ObservedObject var model: LocalAIChatViewModel
    let onContinueInDuckAI: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        privacyNotice
                        ForEach(model.turns) { turn in
                            UserMessageBubble(text: turn.prompt)
                            AssistantMessage(turn: turn,
                                             isFirst: turn.id == model.turns.first?.id,
                                             isLast: turn.id == model.turns.last?.id,
                                             onContinueInDuckAI: onContinueInDuckAI)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.turns) { _ in
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            inputBar
        }
        .background(Color(LocalAIChatPalette.background))
    }

    private static let bottomID = "LocalAI.Conversation.Bottom"

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 18))
            Text("Answered on your device. These messages aren't sent to Duck.ai.")
                .font(LocalAIChatFont.text(15))
        }
        .foregroundColor(Color(LocalAIChatPalette.textSecondary))
        .padding(.horizontal, 20)
    }

    /// Duck.ai's input: #333 field, 1 pt border, fully rounded.
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply…", text: $model.draft, axis: .vertical)
                .font(LocalAIChatFont.text(16))
                .foregroundColor(Color(LocalAIChatPalette.textPrimary))
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(model.sendDraft)
                .padding(.vertical, 14)
                .accessibilityIdentifier("LocalAI.ReplyField")
            if model.isRunning {
                roundButton(systemImage: "stop.fill", label: "Stop", identifier: "LocalAI.Stop", action: model.stop)
            } else {
                roundButton(systemImage: "arrow.up", label: "Send", identifier: "LocalAI.Send", action: model.sendDraft)
                    .disabled(!model.canSend)
                    .opacity(model.canSend ? 1 : 0.4)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 6)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(LocalAIChatPalette.input))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(LocalAIChatPalette.inputBorder), lineWidth: 1))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(LocalAIChatPalette.background))
    }

    private func roundButton(systemImage: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(LocalAIChatPalette.background))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(LocalAIChatPalette.textPrimary)))
        }
        .padding(.bottom, 7)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// Full width, `border-radius: 24 0 24 24`, padding 16×20.
private struct UserMessageBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LocalAIChatFont.text(16))
            .lineSpacing(LocalAIChatFont.bodyLineSpacing)
            .foregroundColor(Color(LocalAIChatPalette.textPrimary))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 0)
                    .fill(Color(LocalAIChatPalette.userBubble))
            )
            .accessibilityIdentifier("LocalAI.UserMessage")
    }
}

/// The Dax AI avatar at 31 pt, text from 60 pt (measured from Duck.ai), then copy, stats and hand-off.
private struct AssistantMessage: View {
    let turn: LocalAIChatTurn
    let isFirst: Bool
    let isLast: Bool
    let onContinueInDuckAI: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image("DuckAI")
                .resizable()
                .scaledToFit()
                .frame(width: 21, height: 21)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 12) {
                if turn.reply.isEmpty && turn.isStreaming {
                    if let status = turn.status {
                        WorkingIndicator(status: status, since: turn.statusSince, readsPage: isFirst)
                    } else {
                        TypingIndicator()
                    }
                }
                LocalAIMarkdownView(text: turn.reply)
                if let error = turn.error {
                    Text(error)
                        .font(LocalAIChatFont.text(15))
                        .foregroundColor(Color(designSystemColor: .destructivePrimary))
                }
                if !turn.isStreaming {
                    footer
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 19)
        .padding(.trailing, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("LocalAI.Result")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = turn.reply
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy")
                if isLast {
                    Button("Continue in Duck.ai", action: onContinueInDuckAI)
                        .font(LocalAIChatFont.text(15, weight: .medium))
                        .foregroundColor(Color(LocalAIChatPalette.accent))
                        .accessibilityIdentifier("LocalAI.ContinueInDuckAI")
                }
            }
            .foregroundColor(Color(LocalAIChatPalette.textSecondary))
            if let stats = turn.stats {
                Text(stats)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Color(LocalAIChatPalette.textTertiary))
            }
        }
    }
}

/// Duck.ai's Markdown styles (`.MD`): 16/24 body, 8 pt between blocks, 24 pt above headings that follow
/// text, list text 44 pt in with tertiary markers.
struct LocalAIMarkdownView: View {
    let text: String

    var body: some View {
        let blocks = LocalAIMarkdown.blocks(from: text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    .padding(.top, Self.extraTopSpacing(for: block, isFirst: index == 0))
            }
        }
        .foregroundColor(Color(LocalAIChatPalette.textPrimary))
        .textSelection(.enabled)
    }

    /// Headings after other blocks get 24 pt above: the stack's 8 plus 16.
    private static func extraTopSpacing(for block: LocalAIMarkdownBlock, isFirst: Bool) -> CGFloat {
        guard !isFirst, case .heading = block else { return 0 }
        return 16
    }

    @ViewBuilder
    private func view(for block: LocalAIMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(LocalAIChatFont.text(level == 1 ? 24 : level == 2 ? 20 : 16, weight: .bold))
                .padding(.bottom, -4)
        case .paragraph(let text):
            Text(Self.inline(text)).font(LocalAIChatFont.text(16)).lineSpacing(LocalAIChatFont.bodyLineSpacing)
        case .bulletList(let items):
            list(items) { _ in "•" }
        case .numberedList(let items):
            list(items) { "\($0 + 1)." }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(size: 14, design: .monospaced)).padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(LocalAIChatPalette.surface)))
        }
    }

    private func list(_ items: [String], marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marker(index))
                        .font(LocalAIChatFont.text(16))
                        .foregroundColor(Color(LocalAIChatPalette.textTertiary))
                        .frame(width: 20, alignment: .trailing)
                    Text(Self.inline(item)).font(LocalAIChatFont.text(16)).lineSpacing(LocalAIChatFont.bodyLineSpacing)
                }
            }
        }
        .padding(.leading, 16)
    }

    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// "Loading the model…" / "Reading the page…" with a bar that fills over the expected time, from the last
/// measured reading speed. It stops at 95 % so it never claims to be done before the first words arrive.
private struct WorkingIndicator: View {
    let status: LocalAIStatus
    let since: Date
    /// The first reply reads the page; follow-ups only read the new message (the page is already cached).
    let readsPage: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(LocalAIChatFont.text(15))
                    .foregroundColor(Color(LocalAIChatPalette.textSecondary))
                if let expected = expectedSeconds {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color(LocalAIChatPalette.userBubble))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color(LocalAIChatPalette.accent))
                                    .frame(width: geometry.size.width * fraction(at: context.date, expected: expected))
                            }
                    }
                    .frame(width: 160, height: 4)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("LocalAI.Working")
    }

    private var title: String {
        switch status {
        case .loadingModel: "Loading the model…"
        case .readingInput: readsPage ? "Reading the page…" : "Reading your message…"
        }
    }

    private var expectedSeconds: Double? {
        guard case .readingInput(let tokens) = status else { return nil }
        return Double(tokens) / LocalAIChatViewModel.readTokensPerSecond
    }

    private func fraction(at date: Date, expected: Double) -> CGFloat {
        CGFloat(min(0.95, date.timeIntervalSince(since) / max(expected, 0.1)))
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color(LocalAIChatPalette.textSecondary))
                    .frame(width: 7, height: 7)
                    .opacity(index == phase ? 1 : 0.35)
            }
        }
        .frame(height: 24)
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
        .accessibilityLabel("Generating")
    }
}
