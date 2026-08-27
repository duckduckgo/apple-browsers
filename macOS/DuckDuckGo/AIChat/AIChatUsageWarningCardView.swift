//
//  AIChatUsageWarningCardView.swift
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

import AIChat
import AppKit
import DesignResourcesKit
import DesignResourcesKitIcons

// MARK: - Localized copy

extension DuckAiUsageWarning {

    /// The module's `messagePreview` is unlocalized and debug-only, so copy comes from `UserText`.
    var localizedHeadline: String {
        switch message {
        case .approaching:
            switch window {
            case .daily: return UserText.aiChatUsageWarningsDailyUsage(percent: percent)
            case .weekly: return UserText.aiChatUsageWarningsWeeklyUsage(percent: percent)
            }
        case .dailyReached:
            return UserText.aiChatUsageWarningsDailyLimitReached
        case .weeklyReached:
            return UserText.aiChatUsageWarningsWeeklyLimitReached
        case .weeklyReachedDegraded:
            return UserText.aiChatUsageWarningsAdvancedModelsLimitReached
        case .freeReached:
            // Web sends one id for a free user whichever window ran out, so the window picks the noun.
            switch window {
            case .daily: return UserText.aiChatUsageWarningsDailyLimitReached
            case .weekly: return UserText.aiChatUsageWarningsWeeklyLimitReached
            }
        }
    }

    var localizedResetsIn: String {
        UserText.aiChatUsageWarningsResetsIn(resetsIn.shortDescription)
    }

    /// Only a model switch takes the swap glyph, matching Windows: there is nothing to swap for an
    /// upsell or a hand-off to another window.
    var actionSwapsModel: Bool {
        switch action {
        case .switchToModel, .switchToFreeModel: return true
        case .tryForFree, .startUsingWeeklyLimit, .none: return false
        }
    }

    /// `nil` hides the button, which is also how a switch with nothing usable to switch to renders.
    var localizedActionTitle: String? {
        guard let action else { return nil }

        switch action {
        case .switchToModel(let suggestion):
            return suggestion.modelShortName.map(UserText.aiChatUsageWarningsSwitchToModel)
                ?? UserText.aiChatUsageWarningsSwitchModel
        case .switchToFreeModel:
            return UserText.aiChatUsageWarningsSwitchToFreeModel
        case .tryForFree(let isTrialEligible):
            return isTrialEligible ? UserText.aiChatUsageWarningsTryForFree : UserText.aiChatUsageWarningsSubscribe
        case .startUsingWeeklyLimit:
            return UserText.aiChatUsageWarningsStartUsingWeeklyLimit
        }
    }
}

// MARK: - Card

/// The Duck.ai usage-limit message, shown in a band below the omnibar panel.
///
/// `DuckAiUsageWarning` has already decided what to say and what to offer; this only lays it out.
final class AIChatUsageWarningCardView: NSView {

    enum Constants {
        /// The band that shows below the panel, and all the height a host has to reserve.
        static let contentHeight: CGFloat = 44
        static let horizontalPadding: CGFloat = 14
        static let iconSize: CGFloat = 16
        static let iconTitleSpacing: CGFloat = 8
        static let titleActionSpacing: CGFloat = 12
        static let actionCloseSpacing: CGFloat = 4
        static let closeButtonSize: CGFloat = 24
        static let fontSize: CGFloat = 13
        /// Bright enough over a dark page, low enough to still read as translucent.
        static let tintAlpha: CGFloat = 0.75
    }

    // MARK: - UI Components

    /// Frosted, not filled: in the panel's own colour it reads as one more section of the panel.
    /// `.hudWindow` is a dark material, and `.withinWindow` because the web view sits behind it.
    private let backgroundView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer?.masksToBounds = true
        return view
    }()

    /// The blur alone tracks the page too closely — a dark image dragged the whole card down with
    /// it. Semi-transparent, so a hint still shows through.
    private let tintView: ColorView = {
        let view = ColorView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.roundedCorners = [.bottomLeft, .bottomRight]
        return view
    }()

    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = DesignSystemImages.Glyphs.Size16.alertRecolorable
        return imageView
    }()

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        return label
    }()

    private let actionButton = AIChatUsageWarningActionButton()

    private let closeButton: PointingHandButton = {
        let button = PointingHandButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.title = ""
        button.image = DesignSystemImages.Glyphs.Size16.close
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(UserText.aiChatUsageWarningsDismissAccessibilityLabel)
        button.toolTip = UserText.aiChatUsageWarningsDismissAccessibilityLabel
        return button
    }()

    /// Content centres on the visible band, not the card, whose top runs up behind the panel.
    private let contentGuide = NSLayoutGuide()

    /// Hidden views still take part in Auto Layout, so footprints collapse explicitly.
    private var closeButtonWidthConstraint: NSLayoutConstraint?
    private var actionCloseSpacingConstraint: NSLayoutConstraint?

    // MARK: - Background style

    /// How the card fills itself, which depends on what sits above it.
    enum BackgroundStyle {
        /// Its own surface, distinct from the opaque panel it tucks under.
        case ownSurface
        /// No fill: the host already paints one surface, and a second blur over it never matches,
        /// because each samples the desktop at its own position and the seam reads as a gradient.
        case hostPaintsSurface
    }

    private var backgroundStyle: BackgroundStyle = .ownSurface

    func apply(_ style: BackgroundStyle) {
        backgroundStyle = style
        switch style {
        case .ownSurface:
            backgroundView.isHidden = false
            backgroundView.material = .popover
            backgroundView.blendingMode = .withinWindow
            tintView.isHidden = false
        case .hostPaintsSurface:
            backgroundView.isHidden = true
            tintView.isHidden = true
        }
    }

    // MARK: - Callbacks

    var onAction: (() -> Void)?
    var onOpenModelPicker: (() -> Void)?
    var onDismiss: (() -> Void)?

    /// The `>`, so a menu opens against the control the user actually clicked.
    var modelPickerAnchor: NSView { actionButton.pickerAnchor }

    // MARK: - Initialization

    init() {
        super.init(frame: .zero)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.onAction = { [weak self] in self?.onAction?() }
        actionButton.onOpenModelPicker = { [weak self] in self?.onOpenModelPicker?() }

        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)

        addSubview(backgroundView)
        addSubview(tintView)
        addLayoutGuide(contentGuide)
        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(actionButton)
        addSubview(closeButton)

        let closeWidth = closeButton.widthAnchor.constraint(equalToConstant: Constants.closeButtonSize)
        closeButtonWidthConstraint = closeWidth

        let actionCloseSpacing = closeButton.leadingAnchor.constraint(equalTo: actionButton.trailingAnchor,
                                                                     constant: Constants.actionCloseSpacing)
        actionCloseSpacingConstraint = actionCloseSpacing

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            tintView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            tintView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            contentGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentGuide.heightAnchor.constraint(equalToConstant: Constants.contentHeight),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            iconImageView.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Constants.iconTitleSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),

            actionButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor,
                                                  constant: Constants.titleActionSpacing),
            actionButton.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),

            actionCloseSpacing,
            closeWidth,
            closeButton.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: Constants.closeButtonSize),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding)
        ])

        // The headline is what gives when space runs short; the CTA is fixed copy that must not.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        applyTheme()
    }

    @objc private func closeButtonClicked() {
        onDismiss?()
    }

    // MARK: - Content

    /// Lays the row out for `warning`. Whether the card shows at all is the host's call.
    func update(with warning: DuckAiUsageWarning) {
        titleLabel.attributedStringValue = Self.attributedTitle(headline: warning.localizedHeadline,
                                                                resetsIn: warning.localizedResetsIn)
        titleLabel.setAccessibilityLabel("\(warning.localizedHeadline). \(warning.localizedResetsIn)")

        let actionTitle = warning.localizedActionTitle
        actionButton.isHidden = actionTitle == nil
        if let actionTitle {
            actionButton.configure(title: actionTitle,
                                   offersModelPicker: warning.offersModelPicker,
                                   showsSwapIcon: warning.actionSwapsModel)
        } else {
            actionButton.collapse()
        }

        closeButton.isHidden = !warning.isDismissible
        closeButtonWidthConstraint?.constant = warning.isDismissible ? Constants.closeButtonSize : 0
        // Otherwise the CTA sits a spacing off the trailing edge on a message with no close button.
        actionCloseSpacingConstraint?.constant = warning.isDismissible ? Constants.actionCloseSpacing : 0
    }

    /// Bold headline, regular reset detail, one string so the two can never wrap apart.
    private static func attributedTitle(headline: String, resetsIn: String) -> NSAttributedString {
        let textColor = NSColor(designSystemColor: .textPrimary)
        let result = NSMutableAttributedString(
            string: headline,
            attributes: [.font: NSFont.systemFont(ofSize: Constants.fontSize, weight: .semibold),
                         .foregroundColor: textColor]
        )
        result.append(NSAttributedString(
            string: " · \(resetsIn)",
            attributes: [.font: NSFont.systemFont(ofSize: Constants.fontSize, weight: .regular),
                         .foregroundColor: textColor]
        ))
        return result
    }

    // MARK: - Appearance

    /// Borderless by design: a stroke along the top edge would draw a line across the seam.
    private func applyTheme() {
        NSAppearance.withAppearance(appearance) {
            tintView.backgroundColor = NSColor(designSystemColor: .surfacePrimary)
                .withAlphaComponent(Constants.tintAlpha)
        }
        // Re-assert last, or an appearance change repaints a fill the style had hidden.
        apply(backgroundStyle)
    }

    /// Matched to the panel's, so the silhouettes agree where the card emerges.
    func applyPanelCornerRadius(_ radius: CGFloat) {
        backgroundView.layer?.cornerRadius = radius
        tintView.cornerRadius = radius
    }

    func applyThemeStyle() {
        applyTheme()
        actionButton.refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }
}

// MARK: - Action button

/// The card's CTA: a pill with the primary action, optionally a divider and the `>` model picker.
///
/// Two hit regions because the view model exposes them separately — the label applies the suggested
/// model, the chevron opens the picker. Both are invisible `NSButton`s over the pill.
final class AIChatUsageWarningActionButton: NSView {

    private enum Constants {
        static let height: CGFloat = 28
        static let cornerRadius: CGFloat = 14
        static let horizontalPadding: CGFloat = 12
        static let fontSize: CGFloat = 12
        static let iconSize: CGFloat = 12
        static let iconTitleSpacing: CGFloat = 6
        static let chevronSize: CGFloat = 16
        static let chevronRegionWidth: CGFloat = 26
        static let dividerWidth: CGFloat = 1
        static let dividerVerticalInset: CGFloat = 6
    }

    private let backgroundLayer = CALayer()

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Constants.fontSize, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let dividerView: ColorView = {
        let view = ColorView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Only a model switch shows it, matching Windows: there is nothing to swap for an upsell or a
    /// hand-off to another window.
    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = DesignSystemImages.Glyphs.Size12.swap
        return imageView
    }()

    private let chevronImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = DesignSystemImages.Glyphs.Size16.chevronDownMedium
        return imageView
    }()

    private let primaryHitButton = AIChatUsageWarningActionButton.makeHitButton()
    private let pickerHitButton = AIChatUsageWarningActionButton.makeHitButton()

    private var dividerWidthConstraint: NSLayoutConstraint?
    private var pickerRegionWidthConstraint: NSLayoutConstraint?
    private var leadingPaddingConstraint: NSLayoutConstraint?
    private var dividerLeadingConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconTitleSpacingConstraint: NSLayoutConstraint?

    var onAction: (() -> Void)?
    var onOpenModelPicker: (() -> Void)?

    /// What a menu popped from the `>` positions itself against.
    var pickerAnchor: NSView { pickerHitButton }

    private var offersModelPicker = false
    private var showsSwapIcon = false
    private var isCollapsed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeHitButton() -> PointingHandButton {
        let button = PointingHandButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.title = ""
        button.isTransparent = true
        return button
    }

    private func setupView() {
        wantsLayer = true
        backgroundLayer.cornerRadius = Constants.cornerRadius
        layer?.insertSublayer(backgroundLayer, at: 0)

        primaryHitButton.target = self
        primaryHitButton.action = #selector(primaryClicked)
        pickerHitButton.target = self
        pickerHitButton.action = #selector(pickerClicked)
        pickerHitButton.setAccessibilityLabel(UserText.aiChatUsageWarningsModelPickerAccessibilityLabel)

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(dividerView)
        addSubview(chevronImageView)
        addSubview(primaryHitButton)
        addSubview(pickerHitButton)

        let dividerWidth = dividerView.widthAnchor.constraint(equalToConstant: Constants.dividerWidth)
        dividerWidthConstraint = dividerWidth
        let pickerRegionWidth = pickerHitButton.widthAnchor.constraint(equalToConstant: Constants.chevronRegionWidth)
        pickerRegionWidthConstraint = pickerRegionWidth
        // The icon leads, and the label hangs off it: with no icon both its width and the spacing
        // collapse, which leaves the label exactly where it sat before.
        let leadingPadding = iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                                    constant: Constants.horizontalPadding)
        leadingPaddingConstraint = leadingPadding
        let iconWidth = iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize)
        iconWidthConstraint = iconWidth
        let iconTitleSpacing = titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor,
                                                                  constant: Constants.iconTitleSpacing)
        iconTitleSpacingConstraint = iconTitleSpacing
        let dividerLeading = dividerView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor,
                                                                 constant: Constants.horizontalPadding)
        dividerLeadingConstraint = dividerLeading

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.height),

            leadingPadding,
            iconWidth,
            iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconTitleSpacing,
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            dividerLeading,
            dividerWidth,
            dividerView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.dividerVerticalInset),
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.dividerVerticalInset),

            chevronImageView.centerXAnchor.constraint(equalTo: pickerHitButton.centerXAnchor),
            chevronImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: Constants.chevronSize),
            chevronImageView.heightAnchor.constraint(equalToConstant: Constants.chevronSize),

            primaryHitButton.topAnchor.constraint(equalTo: topAnchor),
            primaryHitButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            primaryHitButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            primaryHitButton.trailingAnchor.constraint(equalTo: dividerView.leadingAnchor),

            pickerHitButton.topAnchor.constraint(equalTo: topAnchor),
            pickerHitButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            pickerHitButton.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            pickerHitButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            pickerRegionWidth
        ])

        refreshAppearance()
        updateTrackingAreas()
    }

    /// - Parameter offersModelPicker: when false the divider and `>` collapse, leaving a plain pill.
    /// - Parameter showsSwapIcon: the swap glyph before a "Switch to …" label.
    func configure(title: String, offersModelPicker: Bool, showsSwapIcon: Bool) {
        titleLabel.stringValue = title
        self.offersModelPicker = offersModelPicker
        self.showsSwapIcon = showsSwapIcon
        isCollapsed = false
        leadingPaddingConstraint?.constant = Constants.horizontalPadding
        dividerLeadingConstraint?.constant = Constants.horizontalPadding

        iconImageView.isHidden = !showsSwapIcon
        iconWidthConstraint?.constant = showsSwapIcon ? Constants.iconSize : 0
        iconTitleSpacingConstraint?.constant = showsSwapIcon ? Constants.iconTitleSpacing : 0

        dividerView.isHidden = !offersModelPicker
        chevronImageView.isHidden = !offersModelPicker
        pickerHitButton.isHidden = !offersModelPicker
        dividerWidthConstraint?.constant = offersModelPicker ? Constants.dividerWidth : 0
        pickerRegionWidthConstraint?.constant = offersModelPicker ? Constants.chevronRegionWidth : 0

        invalidateIntrinsicContentSize()
    }

    /// Collapses to no width, so a message with no CTA leaves no gap at the trailing edge. The
    /// paddings have to go too, or the label's own chain still reserves them.
    func collapse() {
        isCollapsed = true
        showsSwapIcon = false
        titleLabel.stringValue = ""
        iconImageView.isHidden = true
        iconWidthConstraint?.constant = 0
        iconTitleSpacingConstraint?.constant = 0
        leadingPaddingConstraint?.constant = 0
        dividerLeadingConstraint?.constant = 0
        dividerWidthConstraint?.constant = 0
        pickerRegionWidthConstraint?.constant = 0
        invalidateIntrinsicContentSize()
    }

    /// Padding, label, then the same padding plus the divider and chevron when a picker is offered.
    override var intrinsicContentSize: NSSize {
        guard !isCollapsed else { return NSSize(width: 0, height: Constants.height) }

        var width = Constants.horizontalPadding + titleLabel.intrinsicContentSize.width + Constants.horizontalPadding
        if showsSwapIcon {
            width += Constants.iconSize + Constants.iconTitleSpacing
        }
        if offersModelPicker {
            width += Constants.dividerWidth + Constants.chevronRegionWidth
        }
        return NSSize(width: width, height: Constants.height)
    }

    @objc private func primaryClicked() {
        onAction?()
    }

    @objc private func pickerClicked() {
        onOpenModelPicker?()
    }

    // MARK: - Appearance

    private var isHovered = false {
        didSet { refreshAppearance() }
    }

    func refreshAppearance() {
        let fill = isHovered
            ? NSColor(designSystemColor: .controlsFillSecondary)
            : NSColor(designSystemColor: .controlsFillPrimary)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundLayer.backgroundColor = fill.cgColor
            dividerView.backgroundColor = NSColor(designSystemColor: .lines)
            titleLabel.textColor = NSColor(designSystemColor: .textPrimary)
            iconImageView.contentTintColor = NSColor(designSystemColor: .textPrimary)
            chevronImageView.contentTintColor = NSColor(designSystemColor: .textPrimary)
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    // MARK: - Hover tracking

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
}
