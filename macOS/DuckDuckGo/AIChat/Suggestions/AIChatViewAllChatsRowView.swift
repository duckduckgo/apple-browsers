//
//  AIChatViewAllChatsRowView.swift
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

import AppKit
import DesignResourcesKit
import DesignResourcesKitIcons

// MARK: - AIChatViewAllChatsRowView

/// A footer row view displayed at the bottom of the AI chat suggestions list.
/// Tapping it navigates to the full Duck.ai chat history page.
/// Supports hover and selection states for keyboard/mouse navigation.
final class AIChatViewAllChatsRowView: NSView {

    private enum Constants {
        static let rowHeight: CGFloat = 32
        static let horizontalPadding: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconTitleSpacing: CGFloat = 6
        static let trailingSpacing: CGFloat = 6

        static let iconColor: NSColor = .suggestionIcon
        static let textColor: NSColor = NSColor(designSystemColor: .textPrimary)
    }

    // MARK: - UI Components

    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = DesignSystemImages.Glyphs.Size16.aiChatHistory
        imageView.contentTintColor = Constants.iconColor
        return imageView
    }()

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: UserText.aiChatViewAllChats)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = Constants.textColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        return label
    }()

    private let keyboardShortcutView: KeyboardShortcutView = {
        let view = KeyboardShortcutView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: ["⌃", "⏎"])
        return view
    }()

    private let openDuckAILabel: NSTextField = {
        let label = NSTextField(labelWithString: UserText.aiChatOpenDuckAI)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .controlAccentColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }()

    private let arrowImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = NSImage(named: "Arrow-Right-12")
        imageView.contentTintColor = Constants.iconColor
        return imageView
    }()

    private let backgroundLayer = CALayer()

    // MARK: - Properties

    private let themeProvider: SuggestionRowThemeProviding
    private var trackingArea: NSTrackingArea?

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    var isHovered: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    var isKeyboardNavigating: Bool = false

    var onClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onMouseMoved: (() -> Void)?

    // MARK: - Initialization

    init(themeProvider: SuggestionRowThemeProviding = DefaultSuggestionRowThemeProvider()) {
        self.themeProvider = themeProvider
        super.init(frame: .zero)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true

        backgroundLayer.cornerRadius = themeProvider.suggestionHighlightCornerRadius
        layer?.insertSublayer(backgroundLayer, at: 0)

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(keyboardShortcutView)
        addSubview(openDuckAILabel)
        addSubview(arrowImageView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.rowHeight),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Constants.iconTitleSpacing),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: keyboardShortcutView.leadingAnchor, constant: -Constants.trailingSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            arrowImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            arrowImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowImageView.widthAnchor.constraint(equalToConstant: 9),
            arrowImageView.heightAnchor.constraint(equalToConstant: 9),

            openDuckAILabel.trailingAnchor.constraint(equalTo: arrowImageView.leadingAnchor, constant: -Constants.trailingSpacing),
            openDuckAILabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            keyboardShortcutView.trailingAnchor.constraint(equalTo: openDuckAILabel.leadingAnchor, constant: -Constants.trailingSpacing),
            keyboardShortcutView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    // MARK: - Appearance

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let isHighlighted = isSelected || isHovered
        if isHighlighted {
            let tintColor = themeProvider.selectedTintColor
            backgroundLayer.backgroundColor = themeProvider.accentPrimaryColor.cgColor
            titleLabel.textColor = tintColor
            openDuckAILabel.textColor = tintColor
            iconImageView.contentTintColor = tintColor
            arrowImageView.contentTintColor = tintColor
            keyboardShortcutView.isHighlighted = true
        } else {
            backgroundLayer.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = Constants.textColor
            openDuckAILabel.textColor = themeProvider.accentPrimaryColor
            iconImageView.contentTintColor = Constants.iconColor
            arrowImageView.contentTintColor = themeProvider.accentPrimaryColor
            keyboardShortcutView.isHighlighted = false
        }

        CATransaction.commit()
    }

    // MARK: - Mouse Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingTrackingArea = trackingArea {
            removeTrackingArea(existingTrackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isKeyboardNavigating else { return }
        isHovered = true
        onHoverChanged?(true)
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        if isKeyboardNavigating {
            onMouseMoved?()
            isKeyboardNavigating = false
        }
        if !isHovered {
            isHovered = true
            onHoverChanged?(true)
        }
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        isSelected = true
    }

    override func mouseUp(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        if bounds.contains(locationInView) {
            onClick?()
        }
        isSelected = false
    }

}
