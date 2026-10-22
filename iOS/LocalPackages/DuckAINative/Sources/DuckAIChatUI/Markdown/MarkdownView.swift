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
               let view = arrangedSubviews.last as? InlineTextView {
                view.update(code, style: ChatTypography.code, markdown: false)
                return
            }
        default: break
        }
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        backgroundColor = .clear
        isLayoutMarginsRelativeArrangement = false
        switch value {
        case .paragraph(let text): addText(text)
        case .heading(let level, let text): addText(text, style: ChatTypography.heading(level))
        case .list(let ordered, let start, let items):
            for (index, text) in items.enumerated() {
                let row = UIStackView()
                row.alignment = .top
                row.spacing = 8
                let marker = chatLabel(ordered ? "\(start + index)." : "•")
                marker.setContentHuggingPriority(.required, for: .horizontal)
                marker.setContentCompressionResistancePriority(.required, for: .horizontal)
                row.addArrangedSubview(marker)
                let content = InlineTextView()
                content.update(text)
                row.addArrangedSubview(content)
                addArrangedSubview(row)
            }
        case .codeBlock(let language, let code):
            backgroundColor = DuckAIChatTokens.Color.codeFrame
            layer.cornerRadius = 16
            isLayoutMarginsRelativeArrangement = true
            layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
            let heading = UIStackView(arrangedSubviews: [chatLabel(language ?? "Code", style: ChatTypography.codeLabel),
                                                       chatButton("Copy code", symbol: "doc.on.doc") { [weak self] in
                guard case .codeBlock(_, let text) = self?.block else { return }
                UIPasteboard.general.string = text
            }])
            addArrangedSubview(heading)
            addText(code, style: ChatTypography.code, markdown: false)
        case .blockquote(let blocks):
            backgroundColor = DuckAIChatTokens.Color.userBubble
            isLayoutMarginsRelativeArrangement = true
            layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            let row = UIStackView()
            row.spacing = 12
            let rule = UIView()
            rule.backgroundColor = DuckAIChatTokens.Color.decorationSecondary
            rule.widthAnchor.constraint(equalToConstant: 3).isActive = true
            row.addArrangedSubview(rule)
            let quoted = UIStackView()
            quoted.axis = .vertical
            quoted.spacing = 8
            for block in blocks { let child = MarkdownBlockView(); child.update(block); quoted.addArrangedSubview(child) }
            row.addArrangedSubview(quoted)
            addArrangedSubview(row)
        case .table(let header, let rows):
            for (index, cells) in ([header] + rows).enumerated() {
                let row = UIStackView()
                row.distribution = .fillEqually
                row.spacing = 8
                row.backgroundColor = index == 0 ? DuckAIChatTokens.Color.userBubble : .clear
                for cell in cells {
                    let text = InlineTextView()
                    text.update(index == 0 ? "**" + cell + "**" : cell, style: ChatTypography.tableCell)
                    row.addArrangedSubview(text)
                }
                addArrangedSubview(row)
                let separator = UIView()
                separator.backgroundColor = DuckAIChatTokens.Color.decorationSecondary
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                addArrangedSubview(separator)
            }
        case .thematicBreak:
            let line = UIView()
            line.backgroundColor = DuckAIChatTokens.Color.decorationSecondary
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
            addArrangedSubview(line)
        }
    }

    private func addText(_ text: String, style: ChatTypography.Style = ChatTypography.body, markdown: Bool = true) {
        let view = InlineTextView()
        view.update(text, style: style, markdown: markdown)
        addArrangedSubview(view)
    }
}
#endif
