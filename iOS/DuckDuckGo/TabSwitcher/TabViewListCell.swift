//
//  TabViewListCell.swift
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
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import UIComponents

final class TabViewListCell: TabViewCell {

    enum Constants {
        static let titleLinkSpacing: CGFloat = 2
        static let leadingPadding: CGFloat = 16
        static let trailingPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 8
        static let faviconSize: CGFloat = 24
        static let faviconTrailingPadding: CGFloat = 8
        static let rowHeight: CGFloat = 44
        static let unreadSize: CGFloat = 10
        static let unreadOffset: CGFloat = 6
    }

    static let reuseIdentifier = "TabViewListCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
        finalizeSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func setupLayout() {
        super.setupLayout()

        title.font = .daxBodySemibold()
        title.setContentHuggingPriority(.defaultLow, for: .vertical)
        title.setContentCompressionResistancePriority(.defaultHigh + 1, for: .vertical)

        let mainStack = HitTestStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .horizontal
        background.addSubview(mainStack)

        let faviconContainer = UIView()
        faviconContainer.translatesAutoresizingMaskIntoConstraints = false
        faviconContainer.addSubview(favicon)
        mainStack.addArrangedSubview(faviconContainer)

        let titleButtonsContainer = UIView()
        titleButtonsContainer.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(titleButtonsContainer)

        let titleLinkStack = UIStackView()
        titleLinkStack.translatesAutoresizingMaskIntoConstraints = false
        titleLinkStack.axis = .vertical
        titleLinkStack.spacing = Constants.titleLinkSpacing
        titleLinkStack.addArrangedSubview(title)
        titleButtonsContainer.addSubview(titleLinkStack)

        let linkLabel = FadeOutLabel()
        linkLabel.translatesAutoresizingMaskIntoConstraints = false
        linkLabel.font = .daxSubheadSemibold()
        linkLabel.lineBreakMode = .byClipping
        linkLabel.isAccessibilityElement = false
        linkLabel.setContentHuggingPriority(.defaultLow + 2, for: .vertical)
        titleLinkStack.addArrangedSubview(linkLabel)
        link = linkLabel

        titleButtonsContainer.addSubview(buttonContainer)

        background.addSubview(unread)

        let spacing = buttonContainer.leadingAnchor.constraint(equalTo: titleLinkStack.trailingAnchor,
                                                               constant: TabViewCell.Constants.removeButtonTextSpacingRegular)
        textButtonSpacing = spacing

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Constants.leadingPadding),
            background.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: Constants.trailingPadding),
            mainStack.topAnchor.constraint(equalTo: background.topAnchor, constant: Constants.verticalPadding),
            background.bottomAnchor.constraint(equalTo: mainStack.bottomAnchor, constant: Constants.verticalPadding),
            mainStack.centerYAnchor.constraint(equalTo: background.centerYAnchor),

            favicon.widthAnchor.constraint(equalToConstant: Constants.faviconSize),
            favicon.heightAnchor.constraint(equalToConstant: Constants.faviconSize),
            favicon.leadingAnchor.constraint(equalTo: faviconContainer.leadingAnchor),
            favicon.centerYAnchor.constraint(equalTo: faviconContainer.centerYAnchor),
            faviconContainer.trailingAnchor.constraint(equalTo: favicon.trailingAnchor, constant: Constants.faviconTrailingPadding),
            faviconContainer.heightAnchor.constraint(equalToConstant: Constants.rowHeight),

            titleLinkStack.leadingAnchor.constraint(equalTo: titleButtonsContainer.leadingAnchor),
            titleLinkStack.topAnchor.constraint(equalTo: titleButtonsContainer.topAnchor, constant: Constants.verticalPadding),
            titleButtonsContainer.bottomAnchor.constraint(equalTo: titleLinkStack.bottomAnchor, constant: Constants.verticalPadding),

            buttonContainer.topAnchor.constraint(equalTo: titleButtonsContainer.topAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: titleButtonsContainer.bottomAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: titleButtonsContainer.trailingAnchor),
            spacing,

            removeButton.widthAnchor.constraint(equalToConstant: Constants.rowHeight),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.rowHeight),
            removeButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            removeButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            removeButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),

            unread.widthAnchor.constraint(equalToConstant: Constants.unreadSize),
            unread.heightAnchor.constraint(equalToConstant: Constants.unreadSize),
            unread.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Constants.unreadOffset),
            unread.topAnchor.constraint(equalTo: background.topAnchor, constant: Constants.unreadOffset),
        ])
    }
}
