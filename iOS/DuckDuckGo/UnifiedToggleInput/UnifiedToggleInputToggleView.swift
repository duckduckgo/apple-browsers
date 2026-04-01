//
//  UnifiedToggleInputToggleView.swift
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

/// Pill-shaped segmented toggle for switching between Search and Duck.ai modes.
final class UnifiedToggleInputToggleView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let height: CGFloat = 40
        static let innerHeight: CGFloat = 36
        static let cornerRadius: CGFloat = 20
        static let innerCornerRadius: CGFloat = 18
        static let segmentSpacing: CGFloat = 2
        static let iconTextSpacing: CGFloat = 4
        static let horizontalPadding: CGFloat = 2
        static let animationDuration: TimeInterval = 0.25
    }

    // MARK: - Properties

    private(set) var selectedMode: TextEntryMode = .aiChat

    var onModeChanged: ((TextEntryMode) -> Void)?

    // MARK: - UI Components

    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .controlsRaisedBackdrop)
        view.layer.cornerRadius = Constants.cornerRadius
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var indicator: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .controlsRaisedFillPrimary)
        view.layer.cornerRadius = Constants.innerCornerRadius
        view.layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        view.layer.shadowOpacity = 1.0
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 6
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var searchButton: UIButton = makeSegmentButton(
        icon: DesignSystemImages.Glyphs.Size16.findSearch,
        title: UserText.searchInputToggleSearchButtonTitle,
        tag: 0
    )

    private lazy var duckAIButton: UIButton = {
        let button = makeSegmentButton(
            icon: DesignSystemImages.Glyphs.Size16.aiChat,
            title: UserText.searchInputToggleAIChatButtonTitle,
            tag: 1
        )
        button.accessibilityIdentifier = "AddressBar.Button.DuckAI"
        return button
    }()

    private lazy var stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [searchButton, duckAIButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = Constants.segmentSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Constraints

    private var indicatorToSearch: NSLayoutConstraint!
    private var indicatorToDuckAI: NSLayoutConstraint!

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    /// Sets the selected mode without firing the callback.
    func setMode(_ mode: TextEntryMode, animated: Bool) {
        guard mode != selectedMode else { return }
        selectedMode = mode
        updateIndicator(animated: animated)
        updateButtonAppearance()
    }

    // MARK: - Setup

    private func setupUI() {
        addSubview(backgroundView)
        backgroundView.addSubview(indicator)
        backgroundView.addSubview(stackView)

        indicatorToSearch = indicator.leadingAnchor.constraint(equalTo: searchButton.leadingAnchor)
        indicatorToSearch.priority = .defaultHigh
        indicatorToDuckAI = indicator.leadingAnchor.constraint(equalTo: duckAIButton.leadingAnchor)
        indicatorToDuckAI.priority = .defaultHigh

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            {
                let heightConstraint = backgroundView.heightAnchor.constraint(equalToConstant: Constants.height)
                heightConstraint.priority = .defaultHigh
                return heightConstraint
            }(),

            stackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: Constants.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -Constants.horizontalPadding),
            {
                let topConstraint = stackView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: Constants.horizontalPadding)
                topConstraint.priority = .defaultHigh
                return topConstraint
            }(),
            {
                let bottomConstraint = stackView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -Constants.horizontalPadding)
                bottomConstraint.priority = .defaultHigh
                return bottomConstraint
            }(),

            indicatorToDuckAI,
            indicator.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: Constants.horizontalPadding),
            indicator.heightAnchor.constraint(equalToConstant: Constants.innerHeight),
            indicator.widthAnchor.constraint(equalTo: searchButton.widthAnchor),
        ])

        updateButtonAppearance()
    }

    private func makeSegmentButton(icon: DesignSystemImage, title: String, tag: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.imagePadding = Constants.iconTextSpacing
        config.baseForegroundColor = UIColor(designSystemColor: .textPrimary)

        let fontMetrics = UIFontMetrics(forTextStyle: .body)
        config.attributedTitle = AttributedString(title, attributes: .init([
            .font: fontMetrics.scaledFont(for: .systemFont(ofSize: 16, weight: .medium))
        ]))
        config.image = icon.withRenderingMode(.alwaysTemplate)
        config.contentInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 16)

        let button = UIButton(configuration: config)
        button.tag = tag
        button.tintColor = UIColor(designSystemColor: .textPrimary)
        button.addTarget(self, action: #selector(segmentTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Actions

    @objc private func segmentTapped(_ sender: UIButton) {
        let mode: TextEntryMode = sender.tag == 0 ? .search : .aiChat
        guard mode != selectedMode else { return }
        selectedMode = mode
        updateIndicator(animated: true)
        updateButtonAppearance()
        onModeChanged?(mode)
    }

    // MARK: - Updates

    private func updateIndicator(animated: Bool) {
        let isSearch = selectedMode == .search
        indicatorToSearch.isActive = isSearch
        indicatorToDuckAI.isActive = !isSearch

        guard animated else {
            layoutIfNeeded()
            return
        }

        UIView.animate(withDuration: Constants.animationDuration, delay: 0, options: .curveEaseInOut) {
            self.layoutIfNeeded()
        }
    }

    private func updateButtonAppearance() {
        // Icons are template-rendered so they inherit the text color — no per-state image swap needed.
    }
}
