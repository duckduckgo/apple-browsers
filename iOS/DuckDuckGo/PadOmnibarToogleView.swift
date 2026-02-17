//
//  PadOmnibarToogleView.swift
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

final class PadOmnibarToogleView: UIView {

    private enum Metrics {
        static let outerHeight: CGFloat = 36
        static let outerWidth: CGFloat = 102
        static let innerHeight: CGFloat = 32
        static let horizontalPadding: CGFloat = 2
    }

    var onSearchTapped: (() -> Void)?
    var onAIChatTapped: (() -> Void)?

    var selectedMode: TextEntryMode = .search {
        didSet {
            guard oldValue != selectedMode else { return }
            updateSelection(animated: true)
        }
    }

    private let selectedBackgroundView = UIView()
    private let searchButton = BrowserChromeButton()
    private let aiChatButton = BrowserChromeButton()
    private var selectedLeadingConstraint: NSLayoutConstraint!
    private var selectedTrailingConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpSubviews()
        setUpConstraints()
        setUpProperties()
        setUpAccessibility()
        updateSelection(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        addSubview(selectedBackgroundView)
        addSubview(searchButton)
        addSubview(aiChatButton)
    }

    private func setUpConstraints() {
        selectedBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        aiChatButton.translatesAutoresizingMaskIntoConstraints = false

        selectedLeadingConstraint = selectedBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                                                    constant: Metrics.horizontalPadding)
        selectedTrailingConstraint = selectedBackgroundView.trailingAnchor.constraint(equalTo: centerXAnchor,
                                                                                      constant: -1)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Metrics.outerWidth),
            heightAnchor.constraint(equalToConstant: Metrics.outerHeight),

            selectedBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: (Metrics.outerHeight - Metrics.innerHeight) / 2),
            selectedBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(Metrics.outerHeight - Metrics.innerHeight) / 2),
            selectedLeadingConstraint,
            selectedTrailingConstraint,

            searchButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchButton.topAnchor.constraint(equalTo: topAnchor),
            searchButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            searchButton.trailingAnchor.constraint(equalTo: centerXAnchor),

            aiChatButton.leadingAnchor.constraint(equalTo: centerXAnchor),
            aiChatButton.topAnchor.constraint(equalTo: topAnchor),
            aiChatButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            aiChatButton.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func setUpProperties() {
        backgroundColor = UIColor(designSystemColor: .backdrop)
        layer.cornerRadius = Metrics.outerHeight / 2
        layer.cornerCurve = .continuous

        selectedBackgroundView.backgroundColor = UIColor(designSystemColor: .surface)
        selectedBackgroundView.layer.cornerRadius = Metrics.innerHeight / 2
        selectedBackgroundView.layer.cornerCurve = .continuous
        selectedBackgroundView.layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        selectedBackgroundView.layer.shadowOpacity = 1.0
        selectedBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 1)
        selectedBackgroundView.layer.shadowRadius = 2

        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        aiChatButton.addTarget(self, action: #selector(aiChatTapped), for: .touchUpInside)

        searchButton.adjustsImageWhenHighlighted = false
        aiChatButton.adjustsImageWhenHighlighted = false
    }

    private func setUpAccessibility() {
        searchButton.accessibilityLabel = UserText.searchInputToggleSearchButtonTitle
        searchButton.accessibilityIdentifier = "Browser.OmniBar.Button.ModeToggle.Search"
        searchButton.accessibilityTraits = .button

        aiChatButton.accessibilityLabel = UserText.searchInputToggleAIChatButtonTitle
        aiChatButton.accessibilityIdentifier = "Browser.OmniBar.Button.ModeToggle.AIChat"
        aiChatButton.accessibilityTraits = .button
    }

    private func updateSelection(animated: Bool) {
        let isSearchSelected = selectedMode == .search

        selectedLeadingConstraint.isActive = false
        selectedTrailingConstraint.isActive = false

        if isSearchSelected {
            selectedLeadingConstraint = selectedBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                                                        constant: Metrics.horizontalPadding)
            selectedTrailingConstraint = selectedBackgroundView.trailingAnchor.constraint(equalTo: centerXAnchor,
                                                                                          constant: -1)
        } else {
            selectedLeadingConstraint = selectedBackgroundView.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 1)
            selectedTrailingConstraint = selectedBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                                                          constant: -Metrics.horizontalPadding)
        }

        selectedLeadingConstraint.isActive = true
        selectedTrailingConstraint.isActive = true

        searchButton.setImage(isSearchSelected
                              ? DesignSystemImages.Glyphs.Size16.findSearchGradientColor
                              : DesignSystemImages.Glyphs.Size16.findSearch,
                              for: .normal)
        aiChatButton.setImage(isSearchSelected
                              ? DesignSystemImages.Glyphs.Size16.aiChat
                              : DesignSystemImages.Glyphs.Size16.aiChatGradientColor,
                              for: .normal)

        if animated {
            UIView.animate(withDuration: 0.2) {
                self.layoutIfNeeded()
            }
        } else {
            layoutIfNeeded()
        }
    }

    @objc private func searchTapped() {
        selectedMode = .search
        onSearchTapped?()
    }

    @objc private func aiChatTapped() {
        selectedMode = .aiChat
        onAIChatTapped?()
    }
}
