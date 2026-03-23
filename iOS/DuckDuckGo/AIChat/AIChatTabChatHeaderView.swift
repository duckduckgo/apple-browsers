//
//  AIChatTabChatHeaderView.swift
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

protocol AIChatTabChatHeaderViewDelegate: AnyObject {
    func aiChatTabChatHeaderDidTapSettings()
    func aiChatTabChatHeaderDidTapNewChat()
    func aiChatTabChatHeaderDidTapUpgrade()
}

final class AIChatTabChatHeaderView: UIView {

    private enum Constants {
        static let headerHeight: CGFloat = 60
        static let buttonSize: CGFloat = 44
        static let horizontalPadding: CGFloat = 16
        static let upgradeArrowSize: CGFloat = 12
        static let titleSpacing: CGFloat = 4
        static let titleKerning: CGFloat = -0.23
    }

    weak var delegate: AIChatTabChatHeaderViewDelegate?

    private var isSubscriptionActive: Bool = false

    private lazy var settingsButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.list,
        accessibilityLabel: "Chat settings",
        action: #selector(settingsTapped)
    )

    private lazy var newChatButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.compose,
        accessibilityLabel: "New chat",
        action: #selector(newChatTapped)
    )

    private lazy var titleContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(upgradeTapped))
        container.addGestureRecognizer(tap)
        return container
    }()

    private lazy var freePlanLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = makeTitleAttributedString(
            text: UserText.aiChatHeaderFreePlan,
            font: .daxSubheadSemibold(),
            color: UIColor(designSystemColor: .textPrimary)
        )
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var separatorDot: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = makeTitleAttributedString(
            text: "\u{2022}",
            font: .daxSubheadSemibold(),
            color: UIColor(designSystemColor: .textTertiary)
        )
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var upgradeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = makeTitleAttributedString(
            text: UserText.aiChatHeaderUpgrade,
            font: .daxSubheadRegular(),
            color: UIColor(designSystemColor: .accent)
        )
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var upgradeArrow: UIImageView = {
        let image = DesignSystemImages.Glyphs.Size12.arrowUp
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = UIColor(designSystemColor: .accent)
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var paidTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = makeTitleAttributedString(
            text: UserText.aiChatHeaderPaidTitle,
            font: .daxSubheadSemibold(),
            color: UIColor(designSystemColor: .textPrimary)
        )
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var freeTitleStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [freePlanLabel, separatorDot, upgradeLabel, upgradeArrow])
        stack.axis = .horizontal
        stack.spacing = Constants.titleSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateButtonShadows()
        }
    }

    func configure(isSubscriptionActive: Bool) {
        self.isSubscriptionActive = isSubscriptionActive
        freeTitleStack.isHidden = isSubscriptionActive
        paidTitleLabel.isHidden = !isSubscriptionActive
    }

    private func setupUI() {
        backgroundColor = UIColor(singleUseColor: .duckAIContextualSheetBackground)
        addSubview(settingsButton)
        addSubview(newChatButton)
        addSubview(titleContainer)

        titleContainer.addSubview(freeTitleStack)
        titleContainer.addSubview(paidTitleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.headerHeight),

            settingsButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            settingsButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            newChatButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            newChatButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newChatButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            newChatButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            titleContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleContainer.leadingAnchor.constraint(greaterThanOrEqualTo: settingsButton.trailingAnchor, constant: 8),
            titleContainer.trailingAnchor.constraint(lessThanOrEqualTo: newChatButton.leadingAnchor, constant: -8),

            freeTitleStack.topAnchor.constraint(equalTo: titleContainer.topAnchor),
            freeTitleStack.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            freeTitleStack.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor),
            freeTitleStack.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor),

            paidTitleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor),
            paidTitleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            paidTitleLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor),
            paidTitleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor),

            upgradeArrow.widthAnchor.constraint(equalToConstant: Constants.upgradeArrowSize),
            upgradeArrow.heightAnchor.constraint(equalToConstant: Constants.upgradeArrowSize),
        ])

        upgradeLabel.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: UserText.aiChatHeaderUpgrade) { [weak self] _ in
                self?.upgradeTapped()
                return true
            }
        ]

        configure(isSubscriptionActive: false)
        updateButtonShadows()
    }

    private func makeIconButton(image: DesignSystemImage, accessibilityLabel: String, action: Selector) -> UIButton {
        let button: UIButton
        if #available(iOS 26, *) {
            var config = UIButton.Configuration.glass()
            config.image = image
            config.cornerStyle = .capsule
            button = UIButton(configuration: config)
        } else {
            button = makeIconButtonLegacy(image: image)
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(designSystemColor: .icons)
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeIconButtonLegacy(image: DesignSystemImage) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.backgroundColor = UIColor(designSystemColor: .controlsRaisedFillPrimary)
        button.layer.cornerRadius = Constants.buttonSize / 2
        return button
    }

    private func updateButtonShadows() {
        if #available(iOS 26, *) { return }
        let isDark = traitCollection.userInterfaceStyle == .dark
        for button in [settingsButton, newChatButton] {
            if isDark {
                button.layer.shadowColor = UIColor.white.cgColor
                button.layer.shadowOpacity = 0.35
                button.layer.shadowRadius = 8
                button.layer.shadowOffset = .zero
                button.layer.borderWidth = 0.5
                button.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
            } else {
                button.layer.shadowColor = UIColor.black.cgColor
                button.layer.shadowOpacity = 0.09
                button.layer.shadowRadius = 6
                button.layer.shadowOffset = CGSize(width: 0, height: 5)
                button.layer.borderWidth = 0
                button.layer.borderColor = nil
            }
        }
    }

    private func makeTitleAttributedString(text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .kern: Constants.titleKerning,
        ])
    }

    @objc private func settingsTapped() { delegate?.aiChatTabChatHeaderDidTapSettings() }
    @objc private func newChatTapped() { delegate?.aiChatTabChatHeaderDidTapNewChat() }
    @objc private func upgradeTapped() {
        if !isSubscriptionActive {
            delegate?.aiChatTabChatHeaderDidTapUpgrade()
        }
    }
}
