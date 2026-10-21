//
//  InlineText.swift
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

import SwiftUI

struct InlineText: View {
    let source: String
    let style: DuckAIChatTokens.Typography.Style
    let isStreaming: Bool

    init(_ source: String, style: DuckAIChatTokens.Typography.Style = DuckAIChatTokens.Typography.body, isStreaming: Bool = false) {
        self.source = source
        self.style = style
        self.isStreaming = isStreaming
    }

    var body: some View {
        Group {
            if hasCode || isStreaming {
                InlineRunLayout(lineHeight: style.lineHeight) {
                    ForEach(Array(fragments.enumerated()), id: \.offset) { _, fragment in
                        InlineFragmentView(fragment: fragment, style: style, isStreaming: isStreaming)
                    }
                }
            } else {
                Text(attributed)
                    .font(style.font)
                    .tracking(style.tracking)
                    .lineSpacing(style.lineSpacing)
                    .padding(.vertical, style.lineSpacing / 2)
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
        .tint(DuckAIChatTokens.Color.accent)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    private var hasCode: Bool {
        attributed.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }
    }

    private var fragments: [InlineFragment] {
        let text = attributed
        var result: [InlineFragment] = []
        for run in text.runs {
            let isCode = run.inlinePresentationIntent?.contains(.code) == true
            var content = AttributedString(text[run.range])
            if isCode {
                content.inlinePresentationIntent = nil
                result.append(InlineFragment(text: content, isCode: true, isNewline: false))
            } else {
                var word = AttributedString()
                for character in content.characters {
                    if character == "\n" {
                        if !word.characters.isEmpty {
                            result.append(InlineFragment(text: word, isCode: false, isNewline: false))
                            word = AttributedString()
                        }
                        result.append(InlineFragment(text: AttributedString(""), isCode: false, isNewline: true))
                    } else {
                        var letter = AttributedString(String(character))
                        letter.mergeAttributes(run.attributes)
                        word.append(letter)
                        if character.isWhitespace {
                            result.append(InlineFragment(text: word, isCode: false, isNewline: false))
                            word = AttributedString()
                        }
                    }
                }
                if !word.characters.isEmpty {
                    result.append(InlineFragment(text: word, isCode: false, isNewline: false))
                }
            }
        }
        return result
    }
}

private struct InlineFragment {
    let text: AttributedString
    let isCode: Bool
    let isNewline: Bool
}

private struct InlineFragmentView: View {
    let fragment: InlineFragment
    let style: DuckAIChatTokens.Typography.Style
    let isStreaming: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        Group {
            if fragment.isNewline {
                Color.clear.frame(width: 0, height: 0)
            } else if fragment.isCode {
                Text(fragment.text)
                    .font(DuckAIChatTokens.Typography.inlineCode.font)
                    .lineSpacing(DuckAIChatTokens.Typography.inlineCode.lineSpacing)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(DuckAIChatTokens.Color.controlSecondary, in: RoundedRectangle(cornerRadius: 4))
                    .textSelection(.enabled)
            } else {
                Text(fragment.text)
                    .font(style.font)
                    .tracking(style.tracking)
                    .lineSpacing(style.lineSpacing)
                    .textSelection(.enabled)
            }
        }
        .layoutValue(key: InlineNewlineKey.self, value: fragment.isNewline)
        .opacity(!isStreaming || reduceMotion || isVisible ? 1 : 0)
        .onAppear {
            withAnimation(isStreaming && !reduceMotion ? .easeIn(duration: 0.25) : nil) { isVisible = true }
        }
    }
}

private struct InlineNewlineKey: LayoutValueKey {
    static let defaultValue = false
}

private struct InlineRunLayout: Layout {
    let lineHeight: CGFloat

    private struct Placement {
        let index: Int
        let point: CGPoint
        let proposal: ProposedViewSize
    }

    private struct RowItem {
        let index: Int
        let dimensions: ViewDimensions
        let proposal: ProposedViewSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for placement in arrange(width: bounds.width, subviews: subviews).placements {
            subviews[placement.index].place(at: CGPoint(x: bounds.minX + placement.point.x, y: bounds.minY + placement.point.y),
                                           proposal: placement.proposal)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [Placement]) {
        let width = max(1, width)
        var placements: [Placement] = []
        var row: [RowItem] = []
        var x: CGFloat = 0
        var y: CGFloat = 0

        func finishRow() {
            let ascent = row.map { $0.dimensions[.firstTextBaseline] }.max() ?? 0
            let descent = row.map { $0.dimensions.height - $0.dimensions[.firstTextBaseline] }.max() ?? 0
            let height = max(lineHeight, ascent + descent)
            var rowX: CGFloat = 0
            for item in row {
                placements.append(Placement(index: item.index,
                                            point: CGPoint(x: rowX, y: y + (height - ascent - descent) / 2 + ascent - item.dimensions[.firstTextBaseline]),
                                            proposal: item.proposal))
                rowX += item.dimensions.width
            }
            y += height
            row.removeAll()
            x = 0
        }

        for (index, subview) in subviews.enumerated() {
            if subview[InlineNewlineKey.self] {
                finishRow()
                continue
            }
            let ideal = subview.sizeThatFits(.unspecified)
            let proposal = ProposedViewSize(width: min(ideal.width, width), height: nil)
            let dimensions = subview.dimensions(in: proposal)
            if x > 0 && x + dimensions.width > width { finishRow() }
            row.append(RowItem(index: index, dimensions: dimensions, proposal: proposal))
            x += dimensions.width
        }
        if !row.isEmpty { finishRow() }
        return (CGSize(width: width, height: y), placements)
    }
}
