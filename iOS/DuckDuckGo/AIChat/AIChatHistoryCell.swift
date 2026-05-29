//
//  AIChatHistoryCell.swift
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

import UIKit
import DesignResourcesKit
import DesignResourcesKitIcons

/// Row in the native Duck.ai chat-history table. 24pt glyph + single-line title,
/// laid out programmatically. Mirrors the shape of `BookmarkCell` but skips the
/// favourite indicator since chats don't have one.
final class AIChatHistoryCell: UITableViewCell {

    static let reuseIdentifier = "AIChatHistoryCell"

    let iconImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = UIColor(designSystemColor: .icons)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }

    func configure(with chat: ChatItem) {
        iconImageView.image = Self.icon(for: chat.kind, pinned: chat.pinned)
        titleLabel.text = chat.title
    }

    private func setupViews() {
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)

        // Figma spec: 24pt icon slot with ~2pt inset → 20pt visible glyph. Our
        // DesignSystem glyphs fill the whole frame, so use a 20pt frame to match
        // the visible size. 16pt from card edge, 8pt gap to text, 11.5pt vertical
        // padding (≈44pt row height).
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 20),
            iconImageView.heightAnchor.constraint(equalToConstant: 20),

            // Keep the text position the same as a 24pt icon would produce (12pt
            // gap visually = 8pt gap from a 24pt slot, but here our slot is 20pt
            // so we use 12pt to preserve the same text start position).
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 11.5),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -11.5)
        ])

        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)

        // Separator should start where the text starts (after icon), not at the
        // cell's leading edge — matches Figma + Apple HIG.
        separatorInset = UIEdgeInsets(top: 0, left: 16 + 20 + 12, bottom: 0, right: 0)
    }

    private static func icon(for kind: ChatItem.Kind, pinned: Bool) -> UIImage {
        // Only the text-pinned variant exists in DesignSystemImages so far; voice
        // and image fall back to their non-pinned glyphs until those variants ship.
        switch (kind, pinned) {
        case (.text, true): return DesignSystemImages.Glyphs.Size24.chatPinned
        case (.text, false): return DesignSystemImages.Glyphs.Size24.chat
        case (.voice, _): return DesignSystemImages.Glyphs.Size24.voice
        case (.image, _): return DesignSystemImages.Glyphs.Size24.image
        }
    }
}
