//
//  AIChatMentionPickerEmptyRowView.swift
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

import AppKit

/// "No matching tabs" placeholder row shown inside the `@`-mention picker when the typed
/// filter doesn't match any open tab.
///
/// Intentionally **not** interactive: the row swallows mouse clicks but doesn't run any
/// action, and it can never become highlighted via keyboard navigation. M12's `Enter`
/// handler treats the empty-state row as "no acceptable selection" and falls through to
/// the normal submit path.
final class AIChatMentionPickerEmptyRowView: NSView {

    enum Layout {
        static let height: CGFloat = 28
        static let leadingPadding: CGFloat = 12
        static let trailingPadding: CGFloat = 12
    }

    private let messageLabel = NSTextField(labelWithString: UserText.aiChatMentionPickerNoMatches)

    init() {
        super.init(frame: .zero)
        autoresizesSubviews = true

        messageLabel.font = NSFont.menuFont(ofSize: 0)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 1
        messageLabel.usesSingleLineMode = true
        messageLabel.lineBreakMode = .byTruncatingTail
        addSubview(messageLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Layout.height)
    }

    override func layout() {
        super.layout()
        let menuFont = NSFont.menuFont(ofSize: 0)
        let textHeight = ceil(menuFont.ascender - menuFont.descender)
        let textY = (bounds.height - textHeight) / 2
        let textWidth = max(0, bounds.width - Layout.leadingPadding - Layout.trailingPadding)
        messageLabel.frame = NSRect(x: Layout.leadingPadding, y: textY, width: textWidth, height: textHeight)
    }

    /// Swallow both halves of the click so the empty row never accidentally activates anything.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}
