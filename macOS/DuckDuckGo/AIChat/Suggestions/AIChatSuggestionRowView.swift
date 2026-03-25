//
//  AIChatSuggestionRowView.swift
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
import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons

// MARK: - Theme Provider Protocol

/// Protocol for providing theme colors to suggestion row views.
/// Enables dependency injection for testability.
protocol SuggestionRowThemeProviding {
    var accentPrimaryColor: NSColor { get }
    var selectedTintColor: NSColor { get }
    var suggestionHighlightCornerRadius: CGFloat { get }
}

/// Default implementation that uses the app's theme manager.
struct DefaultSuggestionRowThemeProvider: SuggestionRowThemeProviding {
    var accentPrimaryColor: NSColor {
        var color: NSColor = .controlAccentColor
        NSAppearance.withAppAppearance {
            color = NSApp.delegateTyped.themeManager.theme.palette.accentPrimary
        }
        return color
    }

    var selectedTintColor: NSColor {
        var color: NSColor = NSColor(designSystemColor: .accentContentPrimary)
        NSAppearance.withAppAppearance {
            color = NSApp.delegateTyped.themeManager.theme.palette.accentContentPrimary
        }
        return color
    }

    var suggestionHighlightCornerRadius: CGFloat {
        NSApp.delegateTyped.themeManager.theme.addressBarStyleProvider.suggestionHighlightCornerRadius
    }
}

// MARK: - AIChatSuggestionRowView

/// A view representing a single AI chat suggestion row.
/// Displays an icon (pinned or recent) and the chat title.
/// Supports hover and selection states for keyboard/mouse navigation.
final class AIChatSuggestionRowView: NSView {

    private enum Constants {
        static let rowHeight: CGFloat = 32
        static let horizontalPadding: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconTitleSpacing: CGFloat = 6

        // Colors matching SuggestionTableCellView
        static let iconColor: NSColor = .suggestionIcon
        static let textColor: NSColor = NSColor(designSystemColor: .textPrimary)
    }

    // MARK: - UI Components

    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        return imageView
    }()

    private let titleLabel: NoIntrinsicWidthTextField = {
        let label = NoIntrinsicWidthTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = NSColor(designSystemColor: .textPrimary)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        return label
    }()

    private let deleteButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.image = DesignSystemImages.Glyphs.Size16.trash
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        button.highlight(false)
        button.toolTip = UserText.removeRecentChatSuggestionTooltip
        button.isHidden = true
        button.setAccessibilityLabel(UserText.removeRecentChatSuggestionTooltip)
        return button
    }()

    private let backgroundLayer = CALayer()

    // MARK: - Properties

    private let suggestion: AIChatSuggestion
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

    var canDelete: Bool = false
    var onClick: (() -> Void)?
    var onDelete: (() -> Void)?
    var onMouseMoved: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var isKeyboardNavigating: Bool = false

    // MARK: - Initialization

    init(suggestion: AIChatSuggestion, themeProvider: SuggestionRowThemeProviding = DefaultSuggestionRowThemeProvider()) {
        self.suggestion = suggestion
        self.themeProvider = themeProvider
        super.init(frame: .zero)
        setupView()
        configure(with: suggestion)
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

        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonClicked)

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.rowHeight),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Constants.iconTitleSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -Constants.iconTitleSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            deleteButton.heightAnchor.constraint(equalToConstant: Constants.iconSize),
        ])

        updateAppearance()
    }

    private func configure(with suggestion: AIChatSuggestion) {
        titleLabel.stringValue = suggestion.title

        let icon = suggestion.isPinned
            ? DesignSystemImages.Glyphs.Size16.pin
            : DesignSystemImages.Glyphs.Size16.chat
        iconImageView.image = icon
        iconImageView.contentTintColor = Constants.iconColor
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    // MARK: - Appearance

    private func updateAppearance() {
        // Disable implicit animations for immediate state changes
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let isHighlighted = isSelected || isHovered
        if isHighlighted {
            let tintColor = themeProvider.selectedTintColor
            backgroundLayer.backgroundColor = themeProvider.accentPrimaryColor.cgColor
            titleLabel.textColor = tintColor
            iconImageView.contentTintColor = tintColor
            deleteButton.contentTintColor = tintColor
        } else {
            backgroundLayer.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = Constants.textColor
            iconImageView.contentTintColor = Constants.iconColor
            deleteButton.contentTintColor = Constants.iconColor
        }

        deleteButton.isHidden = !canDelete || !isHighlighted

        CATransaction.commit()
    }

    @objc private func deleteButtonClicked() {
        onDelete?()
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
        // Don't show hover state if keyboard navigation is active
        guard !isKeyboardNavigating else { return }
        isHovered = true
        onHoverChanged?(true)
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        // Notify that mouse moved - this re-enables mouse hover (only if needed)
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
        // Visual feedback on mouse down
        isSelected = true
    }

    override func mouseUp(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        let locationInDeleteButton = deleteButton.convert(event.locationInWindow, from: nil)
        let isDeleteButtonClick = !deleteButton.isHidden && deleteButton.bounds.contains(locationInDeleteButton)
        if bounds.contains(locationInView) && !isDeleteButtonClick {
            onClick?()
        }
        // Reset selection state after click (the view will likely be dismissed)
        isSelected = false
    }

}

// MARK: - NoIntrinsicWidthTextField

/// NSTextField subclass that doesn't report intrinsic width, preventing it from affecting parent layout.
/// Useful when you want a text field to fill available space without expanding its container.
private final class NoIntrinsicWidthTextField: NSTextField {
    override var intrinsicContentSize: NSSize {
        // Return no intrinsic width to prevent affecting parent's width calculation
        // Height is still calculated normally for proper vertical sizing
        let size = super.intrinsicContentSize
        return NSSize(width: NSView.noIntrinsicMetric, height: size.height)
    }
}
