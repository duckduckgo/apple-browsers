//
//  UTIFooterCardView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

final class UTIFooterCardView: UIView {

    static let overlap: CGFloat = 44

    private enum Constants {
        static let cornerRadius: CGFloat = 28
        static let contentTopGap: CGFloat = 12
        static let contentBottom: CGFloat = 12
        static let contentLeading: CGFloat = 16
        static let contentTrailing: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconTextGap: CGFloat = 10
        static let textSpacing: CGFloat = 1
        static let actionSpacing: CGFloat = 8
        static let dismissSize: CGFloat = 32
        /// What the dismiss button and its gap take off the trailing edge when the card carries one.
        static let dismissTrailingFootprint: CGFloat = dismissSize + actionSpacing
    }

    var onPrimaryTap: (() -> Void)?
    var onDismissTap: (() -> Void)?

    let contentView = UIView()

    private let usageRing = UTIFooterUsageRingView()
    private let alertIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.alertRecolorable)
    private let modelSwitchIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.importExport)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UTIFooterActionButton()
    private let dismissButton = UIButton(type: .system)

    private var actionCollapsedWidthConstraint: NSLayoutConstraint?
    private var actionTrailingConstraint: NSLayoutConstraint?
    private var iconSlotWidthConstraint: NSLayoutConstraint?
    private var iconTextGapConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: UTIFooterMessage, animateIcon: Bool) {
        switch message.icon {
        case .none:
            usageRing.isHidden = true
            alertIcon.isHidden = true
            modelSwitchIcon.isHidden = true
        case .usageRing(let progress, let severity):
            usageRing.isHidden = false
            alertIcon.isHidden = true
            modelSwitchIcon.isHidden = true
            usageRing.setProgress(progress, severity: severity, animated: animateIcon)
        case .alert:
            usageRing.isHidden = true
            alertIcon.isHidden = false
            modelSwitchIcon.isHidden = true
        case .modelSwitch:
            usageRing.isHidden = true
            alertIcon.isHidden = true
            modelSwitchIcon.isHidden = false
        }
        let hasIcon = message.icon != UTIFooterMessage.Icon.none
        iconSlotWidthConstraint?.constant = hasIcon ? Constants.iconSize : 0
        iconTextGapConstraint?.constant = hasIcon ? Constants.iconTextGap : 0

        // A title above a reset line is a headline that truncates; a standalone one is body copy.
        let isStandaloneCopy = message.subtitle == nil
        titleLabel.numberOfLines = isStandaloneCopy ? 2 : 1
        titleLabel.font = isStandaloneCopy ? .daxFootnoteRegular() : .daxFootnoteSemibold()
        titleLabel.text = message.title

        subtitleLabel.numberOfLines = message.primaryAction == nil ? 2 : 1
        subtitleLabel.text = message.subtitle
        subtitleLabel.isHidden = message.subtitle?.isEmpty ?? true

        if let primaryAction = message.primaryAction {
            actionButton.isHidden = false
            actionButton.configure(title: primaryAction.title)
        } else {
            actionButton.isHidden = true
        }
        // Hidden views still take part in Auto Layout, so the footprint collapses explicitly.
        actionCollapsedWidthConstraint?.isActive = message.primaryAction == nil

        dismissButton.isHidden = !message.isDismissible
        // Otherwise the CTA stops short of the trailing edge by the width of a close button that
        // isn't there.
        actionTrailingConstraint?.constant = message.isDismissible ? -Constants.dismissTrailingFootprint : 0
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }

    @objc private func dismissTapped() {
        onDismissTap?()
    }

}

// MARK: - Setup

private extension UTIFooterCardView {

    func setupUI() {
        layer.cornerRadius = Constants.cornerRadius
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        clipsToBounds = true
        accessibilityIdentifier = "AIChat.Footer.Card"

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        [usageRing, alertIcon, modelSwitchIcon].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentHuggingPriority(.required, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
            contentView.addSubview($0)
        }
        usageRing.accessibilityIdentifier = "AIChat.Footer.Icon.UsageRing"
        alertIcon.accessibilityIdentifier = "AIChat.Footer.Icon.Alert"
        modelSwitchIcon.accessibilityIdentifier = "AIChat.Footer.Icon.ModelSwitch"
        alertIcon.contentMode = .scaleAspectFit
        alertIcon.isHidden = true
        modelSwitchIcon.contentMode = .scaleAspectFit
        modelSwitchIcon.isHidden = true

        for label in [titleLabel, subtitleLabel] {
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.adjustsFontForContentSizeCategory = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        titleLabel.font = .daxFootnoteSemibold()
        titleLabel.accessibilityIdentifier = "AIChat.Footer.Label.Title"
        subtitleLabel.font = .daxCaption1()
        subtitleLabel.accessibilityIdentifier = "AIChat.Footer.Label.Subtitle"

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = Constants.textSpacing
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textStack)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.onPrimaryTap = { [weak self] in self?.onPrimaryTap?() }
        contentView.addSubview(actionButton)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.setImage(DesignSystemImages.Glyphs.Size16.close, for: .normal)
        dismissButton.accessibilityLabel = UserText.utiDuckAIWarningsDismissAccessibilityLabel
        dismissButton.accessibilityIdentifier = "AIChat.Footer.Button.Dismiss"
        dismissButton.setContentHuggingPriority(.required, for: .horizontal)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .primaryActionTriggered)
        contentView.addSubview(dismissButton)

        let contentTop = contentView.topAnchor.constraint(equalTo: topAnchor, constant: Self.overlap + Constants.contentTopGap)
        contentTop.priority = .defaultHigh

        let actionCollapsedWidth = actionButton.widthAnchor.constraint(equalToConstant: 0)
        actionCollapsedWidthConstraint = actionCollapsedWidth

        // Pinned to the content rather than to the dismiss button, so a hidden dismiss button leaves
        // no gap behind it.
        let actionTrailing = actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                                   constant: -Constants.dismissTrailingFootprint)
        actionTrailingConstraint = actionTrailing

        let iconSlotWidth = usageRing.widthAnchor.constraint(equalToConstant: Constants.iconSize)
        iconSlotWidthConstraint = iconSlotWidth
        let iconTextGap = textStack.leadingAnchor.constraint(equalTo: usageRing.trailingAnchor,
                                                            constant: Constants.iconTextGap)
        iconTextGapConstraint = iconTextGap

        NSLayoutConstraint.activate([
            contentTop,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.contentLeading),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.contentTrailing),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.contentBottom),

            usageRing.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            usageRing.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            iconSlotWidth,
            usageRing.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            alertIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            alertIcon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            alertIcon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            alertIcon.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            modelSwitchIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            modelSwitchIcon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            modelSwitchIcon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            modelSwitchIcon.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            iconTextGap,
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            textStack.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -Constants.actionSpacing),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionTrailing,
            actionButton.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            actionButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),

            dismissButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dismissButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            dismissButton.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            dismissButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: Constants.dismissSize),
            dismissButton.heightAnchor.constraint(equalToConstant: Constants.dismissSize),
        ])

        applyColors()
    }

    func applyColors() {
        backgroundColor = UIColor(designSystemColor: .surfaceSecondary)
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
        subtitleLabel.textColor = UIColor(designSystemColor: .textSecondary)
        alertIcon.tintColor = UIColor(designSystemColor: .icons)
        modelSwitchIcon.tintColor = UIColor(designSystemColor: .icons)
        dismissButton.tintColor = UIColor(designSystemColor: .iconsSecondary)
        actionButton.applyColors()
    }
}

// MARK: - Action button

/// The card's CTA: a plain pill. The model picker lives in the toolbar, not here.
final class UTIFooterActionButton: UIView {

    private enum Constants {
        static let height: CGFloat = 34
        static let titleHorizontalPadding: CGFloat = 14
        static let strokeWidth: CGFloat = 0.5
    }

    var onPrimaryTap: (() -> Void)?

    private let primaryButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        primaryButton.configuration?.title = title
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func applyColors() {
        backgroundColor = UIColor(designSystemColor: .surfaceCanvas)
        layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        primaryButton.configuration?.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }

    private func setupUI() {
        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.borderWidth = Constants.strokeWidth

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.accessibilityIdentifier = "AIChat.Footer.Button.Primary"
        primaryButton.configuration = Self.makePrimaryConfiguration()
        // The label gives before the pill does, so a zero-width collapse can't break the layout.
        primaryButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .primaryActionTriggered)
        addSubview(primaryButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.height),

            primaryButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            primaryButton.topAnchor.constraint(equalTo: topAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        applyColors()
    }

    private static func makePrimaryConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                              leading: Constants.titleHorizontalPadding,
                                                              bottom: 0,
                                                              trailing: Constants.titleHorizontalPadding)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .daxFootnoteRegular()
            return outgoing
        }
        return configuration
    }

    @objc private func primaryTapped() {
        onPrimaryTap?()
    }
}
