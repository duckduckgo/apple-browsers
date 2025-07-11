//
//  UpdatedOmniBarSearchView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

final class UpdatedOmniBarSearchView: UIView {

    let privacyInfoContainer: PrivacyInfoContainerView! = {
        // This view is constructed inside an original OmniBar xib, so let's extract it from there.
        let omniBarNib = DefaultOmniBarView.create()
        omniBarNib.privacyInfoContainer.removeFromSuperview()
        return omniBarNib.privacyInfoContainer
    }()
    let notificationContainer: OmniBarNotificationContainerView! = OmniBarNotificationContainerView()

    let loupeIconView = UIImageView()
    let customIconView = UIImageView()
    let dismissButtonView = BrowserChromeButton()

    let leftIconContainer = UIView()
    let textField = TextFieldWithInsets()

    private let leftIconContainerPlaceholder = UIView()
    private let trailingItemsContainer = UIStackView()

    let separatorView = URLSeparatorView()

    let reloadButton = BrowserChromeButton()
    let clearButton = BrowserChromeButton(.secondary)

    let shareButton = BrowserChromeButton()
    let cancelButton = BrowserChromeButton(.secondary)
    let voiceSearchButton = BrowserChromeButton()
    let accessoryButton = BrowserChromeButton()

    private let mainStackView = UIStackView()

    init() {
        super.init(frame: .zero)

        setUpSubviews()
        setUpConstraints()
        setUpProperties()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reduceClearButtonSpacing(_ isReduced: Bool) {
        trailingItemsContainer.setCustomSpacing(isReduced ? -8 : 0, after: clearButton)
    }

    func hideButtons(moveFactor: Double) {
        leftIconContainerPlaceholder.transform = CGAffineTransform(translationX: -leftIconContainerPlaceholder.frame.maxX * moveFactor, y: 0)
        leftIconContainerPlaceholder.alpha = 0

        textField.transform = CGAffineTransform(translationX: -16, y: 0)

        trailingItemsContainer.transform = CGAffineTransform(translationX: (bounds.width - trailingItemsContainer.frame.minX) * moveFactor, y: 0)
        trailingItemsContainer.alpha = 0
    }

    func revealButtons() {
        leftIconContainerPlaceholder.transform = .identity
        leftIconContainerPlaceholder.alpha = 1

        trailingItemsContainer.transform = .identity
        trailingItemsContainer.alpha = 1

        textField.transform = .identity
    }

    private func setUpSubviews() {
        addSubview(mainStackView)

        leftIconContainerPlaceholder.addSubview(leftIconContainer)

        mainStackView.addSubview(notificationContainer)

        mainStackView.addArrangedSubview(leftIconContainerPlaceholder)
        mainStackView.addArrangedSubview(textField)
        mainStackView.addArrangedSubview(trailingItemsContainer)

        mainStackView.addSubview(privacyInfoContainer)

        trailingItemsContainer.addArrangedSubview(clearButton)
        trailingItemsContainer.addArrangedSubview(voiceSearchButton)
        trailingItemsContainer.addArrangedSubview(reloadButton)
        trailingItemsContainer.addArrangedSubview(cancelButton)
        trailingItemsContainer.addArrangedSubview(shareButton)
        trailingItemsContainer.addArrangedSubview(separatorView)
        trailingItemsContainer.addArrangedSubview(accessoryButton)

        leftIconContainer.addSubview(loupeIconView)
        leftIconContainer.addSubview(dismissButtonView)
    }

    private func setUpConstraints() {
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        notificationContainer.translatesAutoresizingMaskIntoConstraints = false
        leftIconContainer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStackView.topAnchor.constraint(equalTo: topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            notificationContainer.leadingAnchor.constraint(equalTo: leftIconContainerPlaceholder.leadingAnchor, constant: 4),
            notificationContainer.trailingAnchor.constraint(equalTo: textField.trailingAnchor),
            notificationContainer.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
            notificationContainer.heightAnchor.constraint(equalTo: textField.heightAnchor, constant: 4),

            leftIconContainerPlaceholder.leadingAnchor.constraint(equalTo: leftIconContainer.leadingAnchor),
            leftIconContainerPlaceholder.trailingAnchor.constraint(equalTo: leftIconContainer.trailingAnchor),
            leftIconContainerPlaceholder.topAnchor.constraint(equalTo: leftIconContainer.topAnchor),
            leftIconContainerPlaceholder.bottomAnchor.constraint(equalTo: leftIconContainer.bottomAnchor),

            privacyInfoContainer.leadingAnchor.constraint(equalTo: leftIconContainerPlaceholder.leadingAnchor, constant: 10),
            privacyInfoContainer.centerYAnchor.constraint(equalTo: textField.centerYAnchor)
        ])

        UpdatedOmniBarView.activateItemSizeConstraints(for: voiceSearchButton)
        UpdatedOmniBarView.activateItemSizeConstraints(for: reloadButton)
        UpdatedOmniBarView.activateItemSizeConstraints(for: clearButton)
        UpdatedOmniBarView.activateItemSizeConstraints(for: shareButton)
        UpdatedOmniBarView.activateItemSizeConstraints(for: cancelButton)
        UpdatedOmniBarView.activateItemSizeConstraints(for: accessoryButton)
        UpdatedOmniBarView.activateItemSizeConstraints(for: leftIconContainer)

        // Use autoresizing mask here so it's less code
        loupeIconView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dismissButtonView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        loupeIconView.frame = leftIconContainer.bounds
        dismissButtonView.frame = leftIconContainer.bounds
    }

    private func setUpProperties() {
        backgroundColor = .clear
        clipsToBounds = true
        tintColor = UIColor(designSystemColor: .icons)

        textField.textAlignment = .left
        textField.contentVerticalAlignment = .center
        textField.font = UIFont.daxBodyRegular()
        textField.textColor = UIColor(designSystemColor: .textPrimary)
        textField.tintColor = UIColor(designSystemColor: .accent)
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.keyboardType = .webSearch

        accessoryButton.setImage(DesignSystemImages.Glyphs.Size24.aiChat)
        UpdatedOmniBarView.setUpCommonProperties(for: accessoryButton)

        reloadButton.setImage(DesignSystemImages.Glyphs.Size24.reload)
        UpdatedOmniBarView.setUpCommonProperties(for: reloadButton)

        clearButton.setImage(DesignSystemImages.Glyphs.Size24.closeCircleSmall)
        UpdatedOmniBarView.setUpCommonProperties(for: clearButton)

        shareButton.setImage(DesignSystemImages.Glyphs.Size24.shareApple)
        UpdatedOmniBarView.setUpCommonProperties(for: shareButton)

        cancelButton.setImage(DesignSystemImages.Glyphs.Size24.close)
        UpdatedOmniBarView.setUpCommonProperties(for: cancelButton)

        voiceSearchButton.setImage(DesignSystemImages.Glyphs.Size24.microphone)
        UpdatedOmniBarView.setUpCommonProperties(for: voiceSearchButton)

        dismissButtonView.setImage(DesignSystemImages.Glyphs.Size24.arrowLeft)
        UpdatedOmniBarView.setUpCommonProperties(for: dismissButtonView)

        loupeIconView.image = DesignSystemImages.Glyphs.Size24.findSearchSmall
        loupeIconView.tintColor = tintColor
        loupeIconView.contentMode = .center

        customIconView.tintColor = tintColor
        customIconView.contentMode = .center
        customIconView.isHidden = true
        customIconView.image = nil

        privacyInfoContainer.isUsingExperimentalAnimations = true
    }
}
