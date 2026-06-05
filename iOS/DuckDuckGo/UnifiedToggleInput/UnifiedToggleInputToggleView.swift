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
        static let cornerRadius: CGFloat = 20
        static let innerCornerRadius: CGFloat = 18
        static let segmentSpacing: CGFloat = 2
        static let iconTextSpacing: CGFloat = 4
        static let horizontalPadding: CGFloat = 2
        static let animationDuration: TimeInterval = 0.25
        /// Horizontal drag speed (pt/s) above which a release commits in the flick direction,
        /// regardless of whether the pill has crossed the midpoint.
        static let flickVelocityThreshold: CGFloat = 300
    }

    // MARK: - Properties

    private(set) var selectedMode: TextEntryMode = .aiChat

    var onModeChanged: ((TextEntryMode) -> Void)?

    // MARK: - Drag State

    private var dragStartMode: TextEntryMode = .aiChat
    /// Resting leading-x of the indicator for each mode, in this view's coordinate space,
    /// captured at drag start so the gesture stays correct across resize / rotation / Dynamic Type.
    private var dragSearchRestX: CGFloat = 0
    private var dragDuckAIRestX: CGFloat = 0
    private var dragIndicatorWidth: CGFloat = 0

    // MARK: - UI Components

    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .controlsRaisedBackdrop)
        view.alpha = 0.5
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
        stack.layer.cornerRadius = Constants.cornerRadius - Constants.horizontalPadding
        stack.clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Constraints

    private var indicatorToSearch: NSLayoutConstraint!
    private var indicatorToDuckAI: NSLayoutConstraint!

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Clip to pill so the indicator shadow doesn't leak past the pill edge.
        clipsToBounds = true
        layer.cornerRadius = Constants.cornerRadius
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
        // Siblings, not children of backgroundView — its 0.5 alpha would cascade onto labels/indicator.
        addSubview(backgroundView)
        addSubview(indicator)
        addSubview(stackView)

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

            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            {
                let topConstraint = stackView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.horizontalPadding)
                topConstraint.priority = .defaultHigh
                return topConstraint
            }(),
            {
                let bottomConstraint = stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.horizontalPadding)
                bottomConstraint.priority = .defaultHigh
                return bottomConstraint
            }(),

            indicatorToDuckAI,
            {
                let topConstraint = indicator.topAnchor.constraint(equalTo: topAnchor, constant: Constants.horizontalPadding)
                topConstraint.priority = .defaultHigh
                return topConstraint
            }(),
            {
                let bottomConstraint = indicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.horizontalPadding)
                bottomConstraint.priority = .defaultHigh
                return bottomConstraint
            }(),
            indicator.widthAnchor.constraint(equalTo: searchButton.widthAnchor),
        ])

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        updateButtonAppearance()
    }

    private func makeSegmentButton(icon: DesignSystemImage, title: String, tag: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.imagePadding = Constants.iconTextSpacing
        config.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        // Without this, the segment label wraps onto a second line when the toggle is squeezed
        // by the inline back button + the AI-tab bottom margins. Truncate instead of wrap.
        config.titleLineBreakMode = .byTruncatingTail

        let fontMetrics = UIFontMetrics(forTextStyle: .body)
        config.attributedTitle = AttributedString(title, attributes: .init([
            .font: fontMetrics.scaledFont(for: .systemFont(ofSize: 16, weight: .medium))
        ]))
        config.image = icon.withRenderingMode(.alwaysTemplate)
        config.contentInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 16)

        let button = UIButton(configuration: config)
        button.tag = tag
        button.tintColor = UIColor(designSystemColor: .textPrimary)
        button.titleLabel?.numberOfLines = 1
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

    // MARK: - Drag

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginDrag()
        case .changed:
            updateDrag(translationX: gesture.translation(in: self).x)
        case .ended, .cancelled, .failed:
            endDrag(velocityX: gesture.velocity(in: self).x)
        default:
            break
        }
    }

    private func beginDrag() {
        dragStartMode = selectedMode
        // Indicator rest positions equal the buttons' leading edges (see the indicator constraints).
        dragSearchRestX = convert(searchButton.bounds, from: searchButton).minX
        dragDuckAIRestX = convert(duckAIButton.bounds, from: duckAIButton).minX
        dragIndicatorWidth = indicator.bounds.width
    }

    private func updateDrag(translationX: CGFloat) {
        let travel = dragDuckAIRestX - dragSearchRestX
        // Anchored at the drag-start side and clamped to the track, so the pill can reach the
        // far end but never overshoot past either segment.
        let clamped: CGFloat
        if dragStartMode == .search {
            clamped = min(max(translationX, 0), travel)
        } else {
            clamped = max(min(translationX, 0), -travel)
        }
        indicator.transform = CGAffineTransform(translationX: clamped, y: 0)
    }

    private func endDrag(velocityX: CGFloat) {
        let anchorRestX = dragStartMode == .search ? dragSearchRestX : dragDuckAIRestX
        let indicatorCenterX = anchorRestX + indicator.transform.tx + dragIndicatorWidth / 2
        let midpointX = (dragSearchRestX + dragDuckAIRestX) / 2 + dragIndicatorWidth / 2
        let target = resolveTargetMode(indicatorCenterX: indicatorCenterX, midpointX: midpointX, velocityX: velocityX)
        commitDrag(to: target)
    }

    /// Decides which side the pill should settle on when the drag is released.
    /// A fast flick wins outright; otherwise the nearer side (relative to the midpoint) is chosen.
    func resolveTargetMode(indicatorCenterX: CGFloat, midpointX: CGFloat, velocityX: CGFloat) -> TextEntryMode {
        if abs(velocityX) >= Constants.flickVelocityThreshold {
            return velocityX > 0 ? .aiChat : .search
        }
        return indicatorCenterX < midpointX ? .search : .aiChat
    }

    private func commitDrag(to target: TextEntryMode) {
        let modeChanged = target != selectedMode
        selectedMode = target
        updateIndicator(animated: true)
        guard modeChanged else { return }
        updateButtonAppearance()
        onModeChanged?(target)
    }

    // MARK: - Updates

    private func updateIndicator(animated: Bool) {
        let isSearch = selectedMode == .search
        indicatorToSearch.isActive = isSearch
        indicatorToDuckAI.isActive = !isSearch

        guard animated else {
            indicator.transform = .identity
            layoutIfNeeded()
            return
        }

        UIView.animate(withDuration: Constants.animationDuration, delay: 0, options: .curveEaseInOut) {
            self.indicator.transform = .identity
            self.layoutIfNeeded()
        }
    }

    private func updateButtonAppearance() {
        // Icons are template-rendered so they inherit the text color — no per-state image swap needed.
    }
}
