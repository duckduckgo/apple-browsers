//
//  MarkdownView.swift
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

/// Renders a reply's Markdown with the frontend's block spacing. Only the last block changes while streaming.
struct MarkdownView: View {
    let markdown: String
    let isStreaming: Bool

    var body: some View {
        let blocks = MarkdownParser.blocks(from: markdown, isStreaming: isStreaming)
        VStack(alignment: .leading, spacing: DuckAIChatTokens.Spacing.s8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                BlockView(block: block)
                    .padding(.top, extraTopSpacing(blocks, index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The frontend puts 24 pt above a heading that follows body text.
    private func extraTopSpacing(_ blocks: [MarkdownBlock], _ index: Int) -> CGFloat {
        guard index > 0, case .heading = blocks[index] else { return 0 }
        return DuckAIChatTokens.Spacing.s16
    }
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            InlineText(text, style: level == 1 ? DuckAIChatTokens.Typography.h1 : level == 2 ? DuckAIChatTokens.Typography.h2 : DuckAIChatTokens.Typography.h3)
        case .paragraph(let text):
            InlineText(text)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: DuckAIChatTokens.Spacing.s8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: DuckAIChatTokens.Spacing.s8) {
                        Text(ordered ? "\(start + index)." : "•")
                            .font(DuckAIChatTokens.Typography.body.font)
                            .foregroundStyle(DuckAIChatTokens.Color.listMarker)
                            .frame(minWidth: DuckAIChatTokens.Spacing.s16, alignment: .trailing)
                        InlineText(item)
                    }
                }
            }
            .padding(.leading, DuckAIChatTokens.Spacing.s8)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
        case .blockquote(let blocks):
            HStack(alignment: .top, spacing: DuckAIChatTokens.Spacing.s16) {
                Rectangle()
                    .fill(DuckAIChatTokens.Color.controlTertiary)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: DuckAIChatTokens.Spacing.s8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        BlockView(block: block)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let header, let rows):
            TableView(header: header, rows: rows)
        case .thematicBreak:
            Rectangle()
                .fill(DuckAIChatTokens.Color.decorationSecondary)
                .frame(height: 1)
                .padding(.vertical, DuckAIChatTokens.Spacing.s16)
        }
    }
}

struct InlineText: View {
    let source: String
    let style: DuckAIChatTokens.Typography.Style

    init(_ source: String, style: DuckAIChatTokens.Typography.Style = DuckAIChatTokens.Typography.body) {
        self.source = source
        self.style = style
    }

    var body: some View {
        Text(attributed)
            .font(style.font)
            .lineSpacing(style.lineHeight - style.size)
            .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
            .tint(DuckAIChatTokens.Color.accent)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                Text(language)
                    .font(DuckAIChatTokens.Typography.tableCell.font)
                    .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
                    .padding(.horizontal, DuckAIChatTokens.Spacing.s12)
                    .padding(.vertical, DuckAIChatTokens.Spacing.s8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
                    .textSelection(.enabled)
                    .padding(DuckAIChatTokens.Spacing.s12)
            }
            .background(DuckAIChatTokens.Color.codeBackground,
                        in: RoundedRectangle(cornerRadius: DuckAIChatTokens.Radius.codeInner))
        }
        .padding(DuckAIChatTokens.Spacing.s4)
        .background(DuckAIChatTokens.Color.codeFrame,
                    in: RoundedRectangle(cornerRadius: DuckAIChatTokens.Radius.codeOuter))
    }
}

private struct TableView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: DuckAIChatTokens.Spacing.s16, verticalSpacing: DuckAIChatTokens.Spacing.s8) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        InlineText("**\(cell)**", style: DuckAIChatTokens.Typography.tableCell)
                    }
                }
                Rectangle().fill(DuckAIChatTokens.Color.textPrimary).frame(height: 1.6).gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            InlineText(cell, style: DuckAIChatTokens.Typography.tableCell)
                        }
                    }
                    Rectangle().fill(DuckAIChatTokens.Color.decorationSecondary).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                }
            }
        }
    }
}
