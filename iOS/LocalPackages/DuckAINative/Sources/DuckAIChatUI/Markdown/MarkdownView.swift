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

#if canImport(UIKit)
import UIKit

final class MarkdownBlockView: UIStackView {
    private var block: MarkdownBlock?
    private var codeText: InlineTextView?

    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 8
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ value: MarkdownBlock) {
        guard block != value else { return }
        let previous = block
        block = value
        switch value {
        case .paragraph(let text):
            if case .paragraph = previous, let view = arrangedSubviews.first as? InlineTextView { view.update(text); return }
        case .heading(let level, let text):
            if case .heading(let oldLevel, _) = previous, oldLevel == level, let view = arrangedSubviews.first as? InlineTextView {
                view.update(text, style: ChatTypography.heading(level)); return
            }
        case .codeBlock(let language, let code):
            if case .codeBlock(let oldLanguage, _) = previous, oldLanguage == language,
               let view = codeText {
                view.update(code, style: ChatTypography.code, markdown: false)
                return
            }
        default: break
        }
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        backgroundColor = .clear
        codeText = nil
        spacing = 8
        isLayoutMarginsRelativeArrangement = false
        switch value {
        case .paragraph(let text): addText(text)
        case .heading(let level, let text): addText(text, style: ChatTypography.heading(level))
        case .list(let ordered, let start, let items): addList(ordered: ordered, start: start, items: items)
        case .codeBlock(let language, let code): addCode(language: language, code: code)
        case .blockquote(let blocks): addQuote(blocks)
        case .table(let header, let rows): addTable(header: header, rows: rows)
        case .thematicBreak:
            let line = UIView()
            line.backgroundColor = DuckAIChatTokens.Color.decorationSecondary
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
            addArrangedSubview(line)
        }
    }

    private func addList(ordered: Bool, start: Int, items: [String]) {
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        for (index, text) in items.enumerated() {
            let row = UIStackView()
            row.alignment = .top
            row.spacing = 8
            let marker = chatLabel(ordered ? "\(start + index)." : "•")
            marker.textColor = DuckAIChatTokens.Color.listMarker
            marker.textAlignment = .right
            marker.widthAnchor.constraint(greaterThanOrEqualToConstant: 16).isActive = true
            marker.setContentHuggingPriority(.required, for: .horizontal)
            marker.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(marker)
            let content = InlineTextView()
            content.update(text)
            row.addArrangedSubview(content)
            addArrangedSubview(row)
        }
    }

    private func addCode(language: String?, code: String) {
        backgroundColor = DuckAIChatTokens.Color.codeFrame
        layer.cornerRadius = 16
        spacing = 0
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 8, right: 8)
        let label = chatLabel(language ?? "Code", style: ChatTypography.codeLabel)
        label.textColor = DuckAIChatTokens.Color.codeLanguage
        let copy = chatIconButton("Copy code", symbol: "doc.on.doc") { [weak self] in
            guard case .codeBlock(_, let text) = self?.block else { return }
            UIPasteboard.general.string = text
        }
        let heading = UIStackView(arrangedSubviews: [label, UIView(), copy])
        heading.alignment = .center
        heading.isLayoutMarginsRelativeArrangement = true
        heading.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        heading.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        addArrangedSubview(heading)
        let text = InlineTextView()
        text.update(code, style: ChatTypography.code, markdown: false)
        text.backgroundColor = DuckAIChatTokens.Color.codeBackground
        text.layer.cornerRadius = 12
        text.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 16, right: 16)
        codeText = text
        addArrangedSubview(text)
    }

    private func addQuote(_ blocks: [MarkdownBlock]) {
        let row = UIStackView()
        row.spacing = 16
        let rule = UIView()
        rule.backgroundColor = DuckAIChatTokens.Color.controlTertiary
        rule.layer.cornerRadius = 2
        rule.widthAnchor.constraint(equalToConstant: 4).isActive = true
        row.addArrangedSubview(rule)
        let quoted = UIStackView()
        quoted.axis = .vertical
        quoted.spacing = 8
        for block in blocks { let child = MarkdownBlockView(); child.update(block); quoted.addArrangedSubview(child) }
        row.addArrangedSubview(quoted)
        addArrangedSubview(row)
    }

    private func addTable(header: [String], rows: [[String]]) {
        spacing = 0
        for (index, cells) in ([header] + rows).enumerated() {
            let row = UIStackView()
            row.distribution = .fillEqually
            row.spacing = 8
            for cell in cells {
                let text = InlineTextView()
                text.update(index == 0 ? "**" + cell + "**" : cell, style: ChatTypography.tableCell)
                text.textContainerInset = UIEdgeInsets(top: index == 0 ? 0 : 8, left: 1, bottom: index == 0 ? 4 : 8, right: 8)
                row.addArrangedSubview(text)
            }
            addArrangedSubview(row)
            if index < rows.count {
                let separator = UIView()
                separator.backgroundColor = index == 0 ? DuckAIChatTokens.Color.textPrimary : DuckAIChatTokens.Color.decorationSecondary
                separator.heightAnchor.constraint(equalToConstant: index == 0 ? 1.6 : 1).isActive = true
                addArrangedSubview(separator)
            }
        }
    }

    private func addText(_ text: String, style: ChatTypography.Style = ChatTypography.body, markdown: Bool = true) {
        let view = InlineTextView()
        view.update(text, style: style, markdown: markdown)
        addArrangedSubview(view)
    }
}
#endif
