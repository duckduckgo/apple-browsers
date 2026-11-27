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

    /// Burns this row's chat. Shown on every row so single-chat Fire is one tap away, not only behind swipe or long-press.
    let fireButton: UIButton = {
        let button = UIButton(type: .system)
        // Same glyph and tint as the Fire accessory on Duck.ai recent-chat suggestion rows (SuggestionRowView).
        button.setImage(DesignSystemImages.Glyphs.Size16.fire, for: .normal)
        button.tintColor = UIColor(designSystemColor: .iconsSecondary)
        button.accessibilityLabel = UserText.aiChatHistoryDeleteSwipeAccessibilityLabel
        button.accessibilityIdentifier = "aiChatHistoryRowFireButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Receives the Fire Button so a confirmation popover can anchor to it on iPad.
    var onFireTapped: ((UIView) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }

    /// The title ends at the Fire Button normally, and at the row's edge while multi-selecting (the button is hidden then).
    private lazy var titleTrailingToFireButton = titleLabel.trailingAnchor.constraint(equalTo: fireButton.leadingAnchor, constant: -4)
    private lazy var titleTrailingToEdge = titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)

    /// Set only by the iPad sidebar, which draws rows on the column instead of grouped cards.
    private var sidebarRowIsCurrentChat: Bool?

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        iconImageView.image = nil
        onFireTapped = nil
    }

    func applySidebarAppearance(isCurrentChat: Bool) {
        sidebarRowIsCurrentChat = isCurrentChat
        selectedBackgroundView = nil
        separatorInset = UIEdgeInsets(top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0)
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        // Multi-select acts on the selection from the toolbar, so the per-row Fire Button steps aside.
        fireButton.isHidden = state.isEditing
        // Deactivate before activating so the two trailing constraints never conflict.
        let (off, on) = state.isEditing ? (titleTrailingToFireButton, titleTrailingToEdge) : (titleTrailingToEdge, titleTrailingToFireButton)
        off.isActive = false
        on.isActive = true
        guard let isCurrentChat = sidebarRowIsCurrentChat else { return }
        let isMarked = isCurrentChat && !state.isEditing
        var background = UIBackgroundConfiguration.clear()
        background.cornerRadius = 12
        background.backgroundInsets = NSDirectionalEdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8)
        if isMarked {
            background.backgroundColor = UIColor(designSystemColor: .accentPrimary)
        } else if state.isHighlighted && !state.isEditing {
            background.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        }
        backgroundConfiguration = background
        let foreground = UIColor(designSystemColor: isMarked ? .accentContentPrimary : .textPrimary)
        titleLabel.textColor = foreground
        iconImageView.tintColor = isMarked ? foreground : UIColor(designSystemColor: .icons)
        fireButton.tintColor = isMarked ? foreground : UIColor(designSystemColor: .iconsSecondary)
    }

    private func setupViews() {
        // Explicit `backgroundColor` keeps the `.insetGrouped` rounded-corner mask
        // attached through swipe gestures (without it the last row's bottom corner
        // flashes square mid-swipe). Bookmarks' cells do the same.
        backgroundColor = UIColor(designSystemColor: .surfaceTertiary)
        // Keep the surface background when selected (the multi-select checkmark indicates
        // selection) instead of the default grey highlight blending the row into the list.
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = UIColor(designSystemColor: .surfaceTertiary)
        selectedBackgroundView = selectedBackground

        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(fireButton)
        fireButton.addTarget(self, action: #selector(fireButtonTapped), for: .touchUpInside)

        // Rows are 52pt tall (per design); `greaterThanOrEqual` lets them grow with
        // larger Dynamic Type sizes rather than clipping.
        let rowHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        rowHeight.priority = .required - 1

        NSLayoutConstraint.activate([
            rowHeight,

            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            titleTrailingToFireButton,
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 11.5),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -11.5),

            // 44pt tap target; the 16pt glyph sits 16pt from the trailing edge, mirroring the leading icon's inset.
            fireButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            fireButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fireButton.widthAnchor.constraint(equalToConstant: 44),
            fireButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)

        // Separator starts where the text starts (16 + 24 + 8).
        separatorInset = UIEdgeInsets(top: 0, left: 48, bottom: 0, right: 0)
    }

    @objc private func fireButtonTapped() {
        onFireTapped?(fireButton)
    }
}
