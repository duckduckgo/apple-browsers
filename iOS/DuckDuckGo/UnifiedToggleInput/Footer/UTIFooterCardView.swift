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
        static let primaryButtonHeight: CGFloat = 34
        static let primaryButtonHorizontalPadding: CGFloat = 14
        static let dismissSize: CGFloat = 32
        static let primaryButtonStrokeWidth: CGFloat = 0.5
    }

    var onPrimaryTap: (() -> Void)?
    var onDismissTap: (() -> Void)?

    let contentView = UIView()

    private let usageRing = UTIFooterUsageRingView()
    private let alertIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.alertRecolorable)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)

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
        case .usageRing(let progress):
            usageRing.isHidden = false
            alertIcon.isHidden = true
            usageRing.setProgress(progress, animated: animateIcon)
        case .alert:
            usageRing.isHidden = true
            alertIcon.isHidden = false
        }

        titleLabel.text = message.title
        subtitleLabel.text = message.subtitle
        subtitleLabel.isHidden = message.subtitle?.isEmpty ?? true

        if let primaryAction = message.primaryAction {
            primaryButton.isHidden = false
            primaryButton.configuration?.title = primaryAction.title
        } else {
            primaryButton.isHidden = true
            primaryButton.configuration?.title = nil
        }

        dismissButton.isHidden = !message.isDismissible
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }

    @objc private func primaryTapped() {
        onPrimaryTap?()
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

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        [usageRing, alertIcon].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentHuggingPriority(.required, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
            contentView.addSubview($0)
        }
        alertIcon.contentMode = .scaleAspectFit
        alertIcon.isHidden = true

        for label in [titleLabel, subtitleLabel] {
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.adjustsFontForContentSizeCategory = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        titleLabel.font = .daxFootnoteSemibold()
        subtitleLabel.font = .daxCaption1()

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = Constants.textSpacing
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textStack)

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
                primaryButton.configuration = Self.makePrimaryButtonConfiguration()
        primaryButton.setContentHuggingPriority(.required, for: .horizontal)
        primaryButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .primaryActionTriggered)
        contentView.addSubview(primaryButton)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.setImage(DesignSystemImages.Glyphs.Size16.close, for: .normal)
        dismissButton.accessibilityLabel = UserText.utiDuckAIWarningsDismissAccessibilityLabel
        dismissButton.setContentHuggingPriority(.required, for: .horizontal)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .primaryActionTriggered)
        contentView.addSubview(dismissButton)

        let contentTop = contentView.topAnchor.constraint(equalTo: topAnchor, constant: Self.overlap + Constants.contentTopGap)
        contentTop.priority = .defaultHigh

        NSLayoutConstraint.activate([
            contentTop,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.contentLeading),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.contentTrailing),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.contentBottom),

            usageRing.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            usageRing.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            usageRing.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            usageRing.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            alertIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            alertIcon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            alertIcon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            alertIcon.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            textStack.leadingAnchor.constraint(equalTo: usageRing.trailingAnchor, constant: Constants.iconTextGap),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            textStack.trailingAnchor.constraint(equalTo: primaryButton.leadingAnchor, constant: -Constants.actionSpacing),
            primaryButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            primaryButton.heightAnchor.constraint(equalToConstant: Constants.primaryButtonHeight),
            primaryButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -Constants.actionSpacing),
            primaryButton.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            primaryButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),

            dismissButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dismissButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            dismissButton.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            dismissButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: Constants.dismissSize),
            dismissButton.heightAnchor.constraint(equalToConstant: Constants.dismissSize),
        ])

        applyColors()
    }

    static func makePrimaryButtonConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                              leading: Constants.primaryButtonHorizontalPadding,
                                                              bottom: 0,
                                                              trailing: Constants.primaryButtonHorizontalPadding)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .daxFootnoteRegular()
            return outgoing
        }
        return configuration
    }

    func applyColors() {
        backgroundColor = UIColor(designSystemColor: .surfaceSecondary)
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
        subtitleLabel.textColor = UIColor(designSystemColor: .textSecondary)
        alertIcon.tintColor = UIColor(designSystemColor: .icons)
        dismissButton.tintColor = UIColor(designSystemColor: .iconsSecondary)
        primaryButton.configuration?.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        primaryButton.configuration?.background.backgroundColor = UIColor(designSystemColor: .surfaceCanvas)
        primaryButton.configuration?.background.strokeColor = UIColor(designSystemColor: .lines)
        primaryButton.configuration?.background.strokeWidth = Constants.primaryButtonStrokeWidth
    }
}
