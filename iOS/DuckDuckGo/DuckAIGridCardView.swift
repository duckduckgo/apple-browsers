//
//  DuckAIGridCardView.swift
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

/// View rendering the rich Duck.ai tab grid card body (title + content + type chip).
final class DuckAIGridCardView: UIView {

    private enum Metrics {
        static let cornerRadius: CGFloat = 12
        static let contentTopInset: CGFloat = 12
        static let contentHorizontalInset: CGFloat = 8
        static let contentBottomInset: CGFloat = 8
        static let titleSnippetSpacing: CGFloat = 4
        static let snippetChipSpacing: CGFloat = 4
        static let chipHeight: CGFloat = 22
    }

    private let titleLabel = UILabel()
    private let snippetLabel = UILabel()
    private let chipView = ChipView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
        setupAccessibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Apply the supplied grid item to the view.
    /// Callers pass `nil` when they want the screenshot fallback
    func configure(with item: DuckAIGridItem) {
        switch item {
        case .text(let title, let snippet):
            titleLabel.text = title
            snippetLabel.text = snippet
            snippetLabel.isHidden = false
            chipView.configure(icon: DesignSystemImages.Glyphs.Size12.chat,
                               label: UserText.aiChatTabSwitcherCardChipChat)
            chipView.isHidden = false

        case .image(let title, _),
             .voice(let title),
             .empty(let title):
            // Dedicated content views for these variants are not built yet; render
            // the title only so the cell scaffold still has something meaningful.
            titleLabel.text = title
            snippetLabel.text = nil
            snippetLabel.isHidden = true
            chipView.isHidden = true
        }

        updateAccessibility(for: item)
    }

    private func setupSubviews() {
        backgroundColor = UIColor(designSystemColor: .backgroundPromptMessage)
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .daxSubheadSemibold()
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        addSubview(titleLabel)

        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        snippetLabel.font = .daxFootnoteRegular()
        snippetLabel.textColor = UIColor(designSystemColor: .textSecondary)
        snippetLabel.numberOfLines = 0
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.adjustsFontForContentSizeCategory = true
        addSubview(snippetLabel)

        chipView.translatesAutoresizingMaskIntoConstraints = false
        chipView.setContentHuggingPriority(.required, for: .horizontal)
        chipView.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(chipView)

        // Snippet may have to shrink so the chip stays anchored to the bottom; let
        // it lose against the chip's bottom anchor instead of breaking the layout.
        let snippetBottom = snippetLabel.bottomAnchor.constraint(lessThanOrEqualTo: chipView.topAnchor,
                                                                 constant: -Metrics.snippetChipSpacing)
        snippetBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.contentTopInset),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.contentHorizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.contentHorizontalInset),

            snippetLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.titleSnippetSpacing),
            snippetLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.contentHorizontalInset),
            snippetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.contentHorizontalInset),
            snippetBottom,

            chipView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.contentHorizontalInset),
            chipView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.contentBottomInset),
            chipView.heightAnchor.constraint(equalToConstant: Metrics.chipHeight)
        ])
    }

    private func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    private func updateAccessibility(for item: DuckAIGridItem) {
        switch item {
        case .text(let title, let snippet):
            accessibilityLabel = title
            accessibilityValue = snippet
        case .image(let title, _), .voice(let title), .empty(let title):
            accessibilityLabel = title
            accessibilityValue = nil
        }
    }
}

// MARK: - Chip

/// Border-only pill rendered at the bottom-leading of the rich card identifying
/// the chat type.
private final class ChipView: UIView {

    private enum Metrics {
        static let cornerRadius: CGFloat = 11
        static let horizontalPadding: CGFloat = 8
        static let iconLabelSpacing: CGFloat = 6
        static let iconSize: CGFloat = 11
        static let borderWidth: CGFloat = 1
    }

    private let iconView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(icon: UIImage, label: String) {
        iconView.image = icon
        self.label.text = label
    }

    private func setupSubviews() {
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = Metrics.borderWidth
        applyBorderColor()

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(designSystemColor: .icons)
        addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .daxCaptionMedium()
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.adjustsFontForContentSizeCategory = true
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor,
                                              constant: Metrics.horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor,
                                           constant: Metrics.iconLabelSpacing),
            label.trailingAnchor.constraint(equalTo: trailingAnchor,
                                            constant: -Metrics.horizontalPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyBorderColor()
        }
    }

    private func applyBorderColor() {
        // CGColor doesn't auto-resolve against the trait collection — refresh in
        // traitCollectionDidChange so dark mode doesn't end up with a stale colour.
        layer.borderColor = UIColor(designSystemColor: .containerBorderPrimary)
            .resolvedColor(with: traitCollection)
            .cgColor
    }
}
