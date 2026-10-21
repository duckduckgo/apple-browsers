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

struct MarkdownView: View {
    let markdown: String
    let isStreaming: Bool

    var body: some View {
        let blocks = MarkdownParser.blocks(from: markdown, isStreaming: isStreaming)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                BlockView(block: block, isStreaming: isStreaming && index == blocks.count - 1)
                    .padding(.top, spacing(before: index, in: blocks))
            }
        }
        .padding(.top, blocks.first.map(topMargin) ?? 0)
        .padding(.bottom, blocks.last.map(finalMargin) ?? 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spacing(before index: Int, in blocks: [MarkdownBlock]) -> CGFloat {
        guard index > 0 else { return 0 }
        let previous = blocks[index - 1]
        let current = blocks[index]
        if case .heading(let level, _) = current {
            switch previous {
            case .paragraph, .list: return 40
            case .heading(let previousLevel, _) where previousLevel + 1 == level: return 24
            default: break
            }
        }
        return max(bottomMargin(previous), topMargin(current))
    }

    private func finalMargin(_ block: MarkdownBlock) -> CGFloat {
        switch block {
        case .paragraph, .list: 0
        default: bottomMargin(block)
        }
    }

    private func topMargin(_ block: MarkdownBlock) -> CGFloat {
        switch block {
        case .blockquote, .table: 16
        case .thematicBreak: 32
        default: 0
        }
    }

    private func bottomMargin(_ block: MarkdownBlock) -> CGFloat {
        switch block {
        case .heading: 12
        case .blockquote, .table, .codeBlock: 16
        case .thematicBreak: 32
        default: 8
        }
    }
}

private struct BlockView: View {
    let block: MarkdownBlock
    var isStreaming = false

    var body: some View {
        switch block {
        case .heading(let level, let text):
            InlineText(text, style: DuckAIChatTokens.Typography.heading(level), isStreaming: isStreaming)
        case .paragraph(let text):
            InlineText(text, isStreaming: isStreaming)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(start + index)." : "•")
                            .font(DuckAIChatTokens.Typography.body.font)
                            .foregroundStyle(DuckAIChatTokens.Color.listMarker)
                            .frame(width: 16, alignment: .trailing)
                        InlineText(item, isStreaming: isStreaming)
                    }
                }
            }
            .padding(.leading, 20)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
        case .blockquote(let blocks):
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DuckAIChatTokens.Color.controlTertiary)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        BlockView(block: block, isStreaming: isStreaming)
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
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(language ?? "")
                    .font(DuckAIChatTokens.Typography.codeLabel.font)
                    .lineSpacing(DuckAIChatTokens.Typography.codeLabel.lineSpacing)
                    .foregroundStyle(DuckAIChatTokens.Color.codeLanguage)
                Spacer(minLength: 0)
                ChatCopyButton(text: code, size: 24)
            }
            .padding(EdgeInsets(top: 12, leading: 8, bottom: 8, trailing: 12))
            .frame(minHeight: 44)
            Text(code)
                .font(DuckAIChatTokens.Typography.code.font)
                .lineSpacing(DuckAIChatTokens.Typography.code.lineSpacing)
                .padding(.vertical, DuckAIChatTokens.Typography.code.lineSpacing / 2)
                .foregroundStyle(DuckAIChatTokens.Color.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                .background(DuckAIChatTokens.Color.codeBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8))
        .background(DuckAIChatTokens.Color.codeFrame, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TableView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            table
            ScrollView(.horizontal, showsIndicators: false) {
                table.fixedSize(horizontal: true, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                    InlineText("**\(cell)**", style: DuckAIChatTokens.Typography.tableCell)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 0, leading: 1, bottom: 4, trailing: 16))
                }
            }
            Rectangle().fill(DuckAIChatTokens.Color.textPrimary).frame(height: 1.6).gridCellUnsizedAxes(.horizontal)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        InlineText(cell, style: DuckAIChatTokens.Typography.tableCell)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(EdgeInsets(top: 8, leading: 1, bottom: 8, trailing: 8))
                    }
                }
                if index < rows.count - 1 {
                    Rectangle().fill(DuckAIChatTokens.Color.decorationSecondary).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
