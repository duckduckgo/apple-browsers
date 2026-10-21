//
//  MessageViews.swift
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

struct UserMessageView: View {
    let message: UserMessage

    var body: some View {
        VStack(alignment: .trailing, spacing: DuckAIChatTokens.Spacing.s8) {
            ForEach(Array(contexts.enumerated()), id: \.offset) { _, context in
                ContextChip(context: context)
            }
            if !text.isEmpty {
                Text(text)
                    .font(DuckAIChatTokens.Typography.body.font)
                    .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
                    .textSelection(.enabled)
                    .padding(.vertical, DuckAIChatTokens.Spacing.s12)
                    .padding(.horizontal, DuckAIChatTokens.Spacing.s20)
                    .background(DuckAIChatTokens.Color.userBubble, in: DuckAIChatTokens.Radius.userBubble)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, DuckAIChatTokens.Spacing.s40)
    }

    private var contexts: [ContextPart] {
        message.parts.compactMap { if case .context(let context) = $0 { context } else { nil } }
    }

    private var text: String {
        message.parts.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined(separator: "\n")
    }
}

private struct ContextChip: View {
    let context: ContextPart

    var body: some View {
        Label(title, systemImage: symbol)
            .font(DuckAIChatTokens.Typography.tableCell.font)
            .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
            .lineLimit(1)
            .padding(.vertical, DuckAIChatTokens.Spacing.s8)
            .padding(.horizontal, DuckAIChatTokens.Spacing.s12)
            .overlay(Capsule().stroke(DuckAIChatTokens.Color.decorationSecondary))
    }

    private var title: String {
        switch context {
        case .page(let page): page.title
        case .selection(let selection): "\u{201C}\(selection.content)\u{201D}"
        case .pastedText(let text): text
        case .request(.summarize): "Summarize"
        case .request(.translate(let language)): "Translate to \(language.name)"
        }
    }

    private var symbol: String {
        switch context {
        case .page: "globe"
        case .selection: "text.quote"
        case .pastedText: "doc.on.clipboard"
        case .request(.summarize): "text.alignleft"
        case .request(.translate): "character.bubble"
        }
    }
}

struct AssistantPartsView: View {
    let parts: [AssistantPart]
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DuckAIChatTokens.Spacing.s12) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                switch part {
                case .text(let text):
                    MarkdownView(markdown: text, isStreaming: isStreaming && index == parts.count - 1)
                        .contentTransition(.opacity)
                        .animation(.easeIn(duration: 0.25), value: text)
                case .reasoning(let reasoning):
                    ReasoningView(reasoning: reasoning)
                case .refusal:
                    Text("I can't help with that request.")
                        .font(DuckAIChatTokens.Typography.body.font)
                        .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
                case .toolCall, .toolResult, .source:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReasoningView: View {
    let reasoning: Reasoning
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DuckAIChatTokens.Spacing.s8) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: DuckAIChatTokens.Spacing.s4) {
                    Text(label)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(DuckAIChatTokens.Typography.tableCell.font)
                .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
            }
            .buttonStyle(.plain)
            if isExpanded || reasoning.displaySeconds == nil {
                Text(reasoning.text)
                    .font(DuckAIChatTokens.Typography.tableCell.font)
                    .foregroundStyle(DuckAIChatTokens.Color.textTertiary)
            }
        }
    }

    private var label: String {
        reasoning.displaySeconds.map { "Thought for \($0)s" } ?? "Thinking"
    }
}
