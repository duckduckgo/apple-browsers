//
//  PadOmnibarToggleView.swift
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

final class PadOmnibarToggleView: UIView {

    private enum Metrics {
        static let outerHeight: CGFloat = 36
        static let outerWidth: CGFloat = 102
        static let innerHeight: CGFloat = 32
        static let horizontalPadding: CGFloat = 2
        static let selectedWidth: CGFloat = 48
        static let selectedLeadingLeft: CGFloat = horizontalPadding
        static let selectedLeadingRight: CGFloat = outerWidth - horizontalPadding - selectedWidth
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
    private var dragStartLeadingConstant: CGFloat = 0

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
                                                                                    constant: Metrics.selectedLeadingLeft)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Metrics.outerWidth),
            heightAnchor.constraint(equalToConstant: Metrics.outerHeight),

            selectedBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: (Metrics.outerHeight - Metrics.innerHeight) / 2),
            selectedBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(Metrics.outerHeight - Metrics.innerHeight) / 2),
            selectedBackgroundView.widthAnchor.constraint(equalToConstant: Metrics.selectedWidth),
            selectedLeadingConstraint,

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

        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGestureRecognizer.cancelsTouchesInView = false
        addGestureRecognizer(panGestureRecognizer)
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
        selectedLeadingConstraint.constant = isSearchSelected ? Metrics.selectedLeadingLeft : Metrics.selectedLeadingRight

        searchButton.setImage(isSearchSelected
                              ? DesignSystemImages.Glyphs.Size16.findSearchGradientColor
                              : DesignSystemImages.Glyphs.Size16.findSearch,
                              for: .normal)
        aiChatButton.setImage(isSearchSelected
                              ? DesignSystemImages.Glyphs.Size16.aiChat
                              : DesignSystemImages.Glyphs.Size16.aiChatGradientColor,
                              for: .normal)

        if animated {
            UIView.animate(withDuration: 0.24,
                           delay: 0,
                           usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0.2) {
                self.layoutIfNeeded()
            }
        } else {
            layoutIfNeeded()
        }
    }

    @objc private func searchTapped() {
        selectMode(.search, animated: true, notify: true)
    }

    @objc private func aiChatTapped() {
        selectMode(.aiChat, animated: true, notify: true)
    }

    @objc private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            dragStartLeadingConstant = selectedLeadingConstraint.constant

        case .changed:
            let translationX = gestureRecognizer.translation(in: self).x
            let updatedConstant = dragStartLeadingConstant + translationX
            selectedLeadingConstraint.constant = clampedLeadingConstant(updatedConstant)
            layoutIfNeeded()

        case .ended, .cancelled, .failed:
            let modeToSelect = modeForCurrentPosition()
            selectMode(modeToSelect, animated: true, notify: selectedMode != modeToSelect)

        default:
            break
        }
    }

    private func clampedLeadingConstant(_ value: CGFloat) -> CGFloat {
        min(max(value, Metrics.selectedLeadingLeft), Metrics.selectedLeadingRight)
    }

    private func modeForCurrentPosition() -> TextEntryMode {
        let midpoint = (Metrics.selectedLeadingLeft + Metrics.selectedLeadingRight) / 2
        return selectedLeadingConstraint.constant < midpoint ? .search : .aiChat
    }

    private func selectMode(_ mode: TextEntryMode, animated: Bool, notify: Bool) {
        let didChange = selectedMode != mode
        selectedMode = mode
        if !didChange {
            updateSelection(animated: animated)
        }

        guard notify else { return }

        switch mode {
        case .search:
            onSearchTapped?()
        case .aiChat:
            onAIChatTapped?()
        }
    }
}
