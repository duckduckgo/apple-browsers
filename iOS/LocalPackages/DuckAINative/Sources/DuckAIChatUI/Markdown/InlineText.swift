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

#if canImport(UIKit)
import UIKit

final class InlineTextView: UITextView {
    private var source = ""

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        linkTextAttributes = [.foregroundColor: DuckAIChatTokens.Color.accent]
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ text: String, style: ChatTypography.Style = ChatTypography.body, markdown: Bool = true) {
        guard source != text || attributedText.length == 0 else { return }
        source = text
        let result = NSMutableAttributedString(string: "")
        if markdown, let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            for run in parsed.runs {
                var attributes: [NSAttributedString.Key: Any] = [.font: style.font, .foregroundColor: DuckAIChatTokens.Color.textPrimary]
                let intent = run.inlinePresentationIntent ?? []
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if let descriptor = style.font.fontDescriptor.withSymbolicTraits(traits), !traits.isEmpty {
                    attributes[.font] = UIFont(descriptor: descriptor, size: style.size)
                }
                if intent.contains(.code) {
                    attributes[.font] = ChatTypography.inlineCode.font
                    attributes[.backgroundColor] = DuckAIChatTokens.Color.codeFrame
                }
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let link = run.link { attributes[.link] = link }
                result.append(NSAttributedString(string: String(parsed.characters[run.range]), attributes: attributes))
            }
        } else {
            result.append(NSAttributedString(string: text, attributes: [.font: style.font, .foregroundColor: DuckAIChatTokens.Color.textPrimary]))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = style.lineHeight
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        attributedText = result
        invalidateIntrinsicContentSize()
    }
}
#endif
