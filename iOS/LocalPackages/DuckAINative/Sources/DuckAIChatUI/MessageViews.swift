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
        VStack(alignment: .trailing, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                if !prompt.isEmpty {
                    Text(linkedPrompt)
                        .font(DuckAIChatTokens.Typography.body.font)
                        .lineSpacing(DuckAIChatTokens.Typography.body.lineSpacing)
                        .padding(.vertical, DuckAIChatTokens.Typography.body.lineSpacing / 2)
                        .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(contexts.enumerated()), id: \.offset) { _, context in
                    BubbleContextView(context: context)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(DuckAIChatTokens.Color.userBubble, in: bubbleShape)
            .overlay(alignment: .topTrailing) {
                if contexts.isEmpty {
                    BubbleTail()
                        .fill(DuckAIChatTokens.Color.userBubble)
                        .frame(width: 12, height: 21)
                        .offset(x: 12)
                }
            }
            ChatCopyButton(text: prompt)
                .accessibilityIdentifier("NativeChat.UserCopy")
        }
        .padding(.trailing, 12)
        .padding(.top, 12)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24,
                               bottomTrailingRadius: 24, topTrailingRadius: contexts.isEmpty ? 0 : 24)
    }

    private var contexts: [ContextPart] {
        message.parts.compactMap {
            guard case .context(let context) = $0 else { return nil }
            if case .request = context { return nil }
            return context
        }
    }

    private var linkedPrompt: AttributedString {
        var attributed = AttributedString(prompt)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return attributed }
        for match in detector.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)) {
            if let range = Range(match.range, in: prompt), let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].link = match.url
            }
        }
        return attributed
    }

    private var prompt: String {
        let text = message.parts.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined(separator: "\n")
        if !text.isEmpty { return text }
        for part in message.parts {
            if case .context(.request(let request)) = part {
                switch request {
                case .summarize: return "Summarize"
                case .translate: return "Translate"
                }
            }
        }
        return text
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 3.072, y: 9.154))
        path.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 12, y: 10.127), control2: CGPoint(x: 12, y: 15.564))
        path.addLine(to: CGPoint(x: 12.001, y: 0))
        path.addCurve(to: CGPoint(x: 1.465, y: 6.297), control1: CGPoint(x: 7.219, y: 0), control2: CGPoint(x: 3.707, y: 2.859))
        path.addCurve(to: CGPoint(x: 3.072, y: 9.154), control1: CGPoint(x: 0.675, y: 7.51), control2: CGPoint(x: 1.634, y: 8.997))
        path.closeSubpath()
        return path.applying(CGAffineTransform(a: -rect.width / 12, b: 0, c: 0, d: rect.height / 21, tx: rect.width, ty: 0))
    }
}

private struct BubbleContextView: View {
    let context: ContextPart
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 16, height: 16)
                Text(subtitle)
                    .font(DuckAIChatTokens.Typography.caption.font)
                    .lineSpacing(DuckAIChatTokens.Typography.caption.lineSpacing)
                    .tint(DuckAIChatTokens.Color.textPrimary)
            }
            .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
            if let selectionText {
                Button(isExpanded ? "Show less" : "Show more") { isExpanded.toggle() }
                    .font(DuckAIChatTokens.Typography.subtitle.font.weight(.medium))
                    .foregroundStyle(DuckAIChatTokens.Color.accent)
                    .buttonStyle(.plain)
                if isExpanded {
                    HStack(alignment: .top, spacing: 16) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DuckAIChatTokens.Color.controlTertiary)
                            .frame(width: 4)
                        Text(selectionText)
                            .font(DuckAIChatTokens.Typography.body.font)
                            .lineSpacing(DuckAIChatTokens.Typography.body.lineSpacing)
                            .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
                            .textSelection(.enabled)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    private var subtitle: AttributedString {
        var result = AttributedString(prefix)
        var title = AttributedString(sourceTitle)
        title.foregroundColor = DuckAIChatTokens.Color.textPrimary
        title.underlineStyle = .single
        title.link = sourceURL
        result.append(title)
        return result
    }

    private var prefix: String {
        switch context {
        case .page: "Page content from "
        case .selection: "Selected text from "
        case .pastedText: "Pasted text"
        case .request: ""
        }
    }

    private var sourceTitle: String {
        switch context {
        case .page(let page): page.title
        case .selection(let selection): selection.title
        default: ""
        }
    }

    private var sourceURL: URL? {
        switch context {
        case .page(let page): page.url
        case .selection(let selection): selection.url
        default: nil
        }
    }

    private var selectionText: String? {
        switch context {
        case .selection(let selection): selection.content
        case .pastedText(let text): text
        default: nil
        }
    }

    private var symbol: String {
        switch context {
        case .page: "globe"
        case .selection: "text.quote"
        default: "doc.on.clipboard"
        }
    }
}

struct AssistantPartsView: View {
    let parts: [AssistantPart]
    let isStreaming: Bool
    let modelName: String
    let isActive: Bool
    @State private var isReasoningExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                AssistantHeading(title: headingTitle, isActive: isActive, isLoading: isStreaming)
                Spacer(minLength: 0)
                if let reasoning {
                    reasoningButton(reasoning)
                        .padding(.trailing, -8)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if let reasoning, isReasoningExpanded || reasoning.displaySeconds == nil {
                    Text(reasoning.text)
                        .font(DuckAIChatTokens.Typography.subtitle.font)
                        .lineSpacing(DuckAIChatTokens.Typography.subtitle.lineSpacing)
                        .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
                        .textSelection(.enabled)
                }
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    switch part {
                    case .text(let text):
                        MarkdownView(markdown: text, isStreaming: isStreaming && index == parts.count - 1)
                    case .refusal:
                        Text("This model can't help with this request.")
                            .font(DuckAIChatTokens.Typography.body.font)
                            .lineSpacing(DuckAIChatTokens.Typography.body.lineSpacing)
                            .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
                    case .reasoning, .toolCall, .toolResult, .source:
                        EmptyView()
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var headingTitle: String {
        guard isStreaming else { return modelName }
        return parts.contains { if case .text = $0 { true } else { false } } ? "Generating response" : "Thinking"
    }

    private var reasoning: Reasoning? {
        parts.compactMap { if case .reasoning(let reasoning) = $0 { reasoning } else { nil } }.last
    }

    private func reasoningButton(_ reasoning: Reasoning) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isReasoningExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                if let seconds = reasoning.displaySeconds {
                    Text("\(seconds)s")
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(elapsedSeconds(reasoning, at: context.date))s")
                    }
                }
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isReasoningExpanded ? 180 : 0))
            }
            .font(DuckAIChatTokens.Typography.modelName.font)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
        .buttonStyle(ChatGhostButtonStyle())
        .accessibilityLabel("Reasoning")
        .accessibilityValue(isReasoningExpanded ? "Expanded" : "Collapsed")
    }

    private func elapsedSeconds(_ reasoning: Reasoning, at date: Date) -> Int {
        guard case .thinking(let since) = reasoning.timing else { return reasoning.displaySeconds ?? 1 }
        return max(1, Int(date.timeIntervalSince(since).rounded(.up)))
    }
}
