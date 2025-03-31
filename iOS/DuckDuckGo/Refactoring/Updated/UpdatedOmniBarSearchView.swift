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

final class UpdatedOmniBarSearchView: UIView {

    let loupeIconView = UIImageView()
    let customIconView = UIImageView()
    let dismissButtonView = UIButton(type: .custom)

    let leftIconContainer = UIView()

    let textField = TextFieldWithInsets()

    private let trailingItemsContainer = UIStackView()

    let reloadButton = UIButton(type: .custom)
    let clearButton = UIButton(type: .custom)

    let shareButton = UIButton(type: .custom)
    let cancelButton = UIButton(type: .custom)
    let voiceSearchButton = UIButton(type: .custom)
    let accessoryButton = UIButton(type: .custom)

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

    private func setUpSubviews() {
        addSubview(mainStackView)

        mainStackView.addArrangedSubview(leftIconContainer)
        mainStackView.addArrangedSubview(textField)
        mainStackView.addArrangedSubview(trailingItemsContainer)

        trailingItemsContainer.addArrangedSubview(voiceSearchButton)
        trailingItemsContainer.addArrangedSubview(reloadButton)
        trailingItemsContainer.addArrangedSubview(clearButton)
        trailingItemsContainer.addArrangedSubview(cancelButton)
        trailingItemsContainer.addArrangedSubview(URLSeparatorView())
        trailingItemsContainer.addArrangedSubview(accessoryButton)

        leftIconContainer.addSubview(loupeIconView)
        leftIconContainer.addSubview(dismissButtonView)
        leftIconContainer.addSubview(customIconView)
    }

    private func setUpConstraints() {
        mainStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStackView.topAnchor.constraint(equalTo: topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        UpdatedOmniBarView.activateItemSizeConstraints(for: voiceSearchButton)
        UpdatedOmniBarView.activateItemSizeConstraints(for: reloadButton)
        UpdatedOmniBarView.activateItemSizeConstraints(for: clearButton)
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
        textField.font = UIFont.daxBodyRegular()//(ofSize: 16)
        textField.returnKeyType = .go
        textField.textColor = UIColor(designSystemColor: .textPrimary)
        textField.tintColor = UIColor(designSystemColor: .textSelectionFill)

        accessoryButton.setImage(UIImage(resource: .aiChat24E), for: .normal)
        UpdatedOmniBarView.setUpCommonProperties(for: accessoryButton)

        reloadButton.setImage(UIImage(resource: .reload24E), for: .normal)
        UpdatedOmniBarView.setUpCommonProperties(for: reloadButton)

        clearButton.setImage(UIImage(resource: .closeCircleSmall24E), for: .normal)
        UpdatedOmniBarView.setUpCommonProperties(for: clearButton)
        clearButton.tintColor = UIColor(designSystemColor: .iconsSecondary)

        shareButton.setImage(UIImage(resource: .shareApple24E), for: .normal)
        UpdatedOmniBarView.setUpCommonProperties(for: shareButton)

        cancelButton.setImage(UIImage(resource: .close24E), for: .normal)
        UpdatedOmniBarView.setUpCommonProperties(for: cancelButton)
        cancelButton.tintColor = UIColor(designSystemColor: .iconsSecondary)

        voiceSearchButton.setImage(UIImage(resource: .microphone24E), for: .normal)
        UpdatedOmniBarView.setUpCommonProperties(for: voiceSearchButton)

        dismissButtonView.setImage(UIImage(resource: .arrowLeft24E), for: .normal)
        UpdatedOmniBarView.setUpCommonProperties(for: dismissButtonView)

        loupeIconView.image = UIImage(resource: .findSearch24E)
        loupeIconView.tintColor = tintColor
        loupeIconView.contentMode = .center

        customIconView.tintColor = tintColor
        customIconView.contentMode = .center
    }

    private struct Metrics {
//        static let buttonSize: CGFloat = 44
        static let height: CGFloat = 60
//        static let textAreaHeight: CGFloat = 44
    }
}
