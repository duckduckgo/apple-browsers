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

    /// The module's own `messagePreview` is unlocalized and debug-log-only, so the card renders
    /// its copy from `UserText` instead. Kept pure so it can be tested without a view.
    var localizedHeadline: String {
        switch message {
        case .approaching:
            switch window {
            case .daily: return UserText.aiChatUsageWarningsDailyUsage(percent: percent)
            case .weekly: return UserText.aiChatUsageWarningsWeeklyUsage(percent: percent)
            }
        case .dailyLimitReached:
            return UserText.aiChatUsageWarningsDailyLimitReached
        case .weeklyLimitReached:
            return UserText.aiChatUsageWarningsWeeklyLimitReached
        case .advancedModelsLimitReached:
            return UserText.aiChatUsageWarningsAdvancedModelsLimitReached
        }
    }

    var localizedResetsIn: String {
        UserText.aiChatUsageWarningsResetsIn(resetsIn.shortDescription)
    }

    /// `nil` hides the button. `.startUsingWeeklyLimit` has no native route yet — the resolver
    /// still produces it so the decision stays visible in the log, but a button that does nothing
    /// is worse than no button, so that message renders without one.
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
            return nil
        }
    }
}

// MARK: - Card

/// The Duck.ai usage-limit message: a card below the omnibar panel, detached from its chrome.
///
/// Rendered from `DuckAiUsageWarning`, which already decided what to say, whether it can be
/// dismissed and what to offer — this view only lays it out and reports clicks back.
final class AIChatUsageWarningCardView: NSView {

    enum Constants {
        /// The band that actually shows below the panel, and all the height a host has to reserve.
        /// Hosts reserve panel height from this, so it lives here rather than at the call site.
        static let contentHeight: CGFloat = 44
        static let horizontalPadding: CGFloat = 14
        static let iconSize: CGFloat = 16
        static let iconTitleSpacing: CGFloat = 8
        static let titleActionSpacing: CGFloat = 12
        static let actionCloseSpacing: CGFloat = 4
        static let closeButtonSize: CGFloat = 24
        static let fontSize: CGFloat = 13
        /// High enough to stay bright over a dark page, low enough to still read as translucent.
        static let tintAlpha: CGFloat = 0.75
    }

    // MARK: - UI Components

    /// Frosted rather than filled. An opaque card in the panel's own colour reads as one more
    /// section of the panel; letting the page blur through is what separates the two surfaces.
    /// `.popover` rather than `.hudWindow`: the latter is a dark material that reads as a grey
    /// slab in light mode. `.withinWindow` because what sits behind the card is the web view.
    private let backgroundView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        // Bottom corners only — the top edge is behind the panel, and rounding it would notch
        // the seam. AppKit layers are unflipped, so MinY is the bottom.
        view.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer?.masksToBounds = true
        return view
    }()

    /// Sits over the blur to keep the card bright and mostly independent of whatever is behind it.
    /// The blur alone tracks the page too closely — a dark hero image dragged the whole card down
    /// with it. Semi-transparent, so a hint of the page still shows and it doesn't read as opaque.
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
        imageView.image = DesignSystemImages.Color.Size16.exclamation
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

    /// The band below the panel. Content centres on this rather than on the card, whose top runs
    /// up behind the panel and would pull everything off-centre.
    private let contentGuide = NSLayoutGuide()

    /// Hidden views still take part in Auto Layout, so each optional element's footprint is
    /// collapsed explicitly rather than left to `isHidden`.
    private var closeButtonWidthConstraint: NSLayoutConstraint?
    private var actionCloseSpacingConstraint: NSLayoutConstraint?

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

    /// Lays out for `warning`. Whether the card is on screen at all is the host's call; this only
    /// has to make the row match the message.
    func update(with warning: DuckAiUsageWarning) {
        titleLabel.attributedStringValue = Self.attributedTitle(headline: warning.localizedHeadline,
                                                                resetsIn: warning.localizedResetsIn)
        titleLabel.setAccessibilityLabel("\(warning.localizedHeadline). \(warning.localizedResetsIn)")

        let actionTitle = warning.localizedActionTitle
        actionButton.isHidden = actionTitle == nil
        if let actionTitle {
            actionButton.configure(title: actionTitle, offersModelPicker: warning.offersModelPicker)
        } else {
            actionButton.collapse()
        }

        closeButton.isHidden = !warning.isDismissible
        closeButtonWidthConstraint?.constant = warning.isDismissible ? Constants.closeButtonSize : 0
        // Without this the CTA would sit a spacing's width off the trailing edge on a sticky message.
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

    /// Deliberately borderless: the design separates the card from the page with the shadow alone,
    /// and a stroke along the top edge would draw a line across the seam with the panel.
    private func applyTheme() {
        NSAppearance.withAppearance(appearance) {
            tintView.backgroundColor = NSColor(designSystemColor: .surfacePrimary)
                .withAlphaComponent(Constants.tintAlpha)
        }
    }

    /// Matched to the panel's, so the two silhouettes agree where the card emerges from under it.
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

/// The card's CTA: a pill carrying the primary action, optionally followed by a divider and the
/// `>` that opens the native model picker.
///
/// Two hit regions rather than one, because the view model exposes them separately — the label
/// applies the suggested model, the chevron lets the user pick a different one. The regions are
/// invisible `NSButton`s constrained to the label and chevron areas, so neither the hit test nor
/// the accessibility tree has to do pointer arithmetic.
final class AIChatUsageWarningActionButton: NSView {

    private enum Constants {
        static let height: CGFloat = 28
        static let cornerRadius: CGFloat = 14
        static let horizontalPadding: CGFloat = 12
        static let fontSize: CGFloat = 12
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

    var onAction: (() -> Void)?
    var onOpenModelPicker: (() -> Void)?

    /// What a menu popped from the `>` positions itself against.
    var pickerAnchor: NSView { pickerHitButton }

    private var offersModelPicker = false
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
        // Transparent: the pill behind it is the visible control.
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

        addSubview(titleLabel)
        addSubview(dividerView)
        addSubview(chevronImageView)
        addSubview(primaryHitButton)
        addSubview(pickerHitButton)

        let dividerWidth = dividerView.widthAnchor.constraint(equalToConstant: Constants.dividerWidth)
        dividerWidthConstraint = dividerWidth
        let pickerRegionWidth = pickerHitButton.widthAnchor.constraint(equalToConstant: Constants.chevronRegionWidth)
        pickerRegionWidthConstraint = pickerRegionWidth

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.height),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            dividerView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: Constants.horizontalPadding),
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

    /// - Parameter offersModelPicker: when false the divider and `>` collapse to nothing, leaving
    ///   a plain pill whose whole surface performs the primary action.
    func configure(title: String, offersModelPicker: Bool) {
        titleLabel.stringValue = title
        self.offersModelPicker = offersModelPicker
        isCollapsed = false

        dividerView.isHidden = !offersModelPicker
        chevronImageView.isHidden = !offersModelPicker
        pickerHitButton.isHidden = !offersModelPicker
        dividerWidthConstraint?.constant = offersModelPicker ? Constants.dividerWidth : 0
        pickerRegionWidthConstraint?.constant = offersModelPicker ? Constants.chevronRegionWidth : 0

        invalidateIntrinsicContentSize()
    }

    /// Takes no width at all while collapsed, so a message with no CTA doesn't leave a gap where
    /// the pill would have been. Expressed here rather than as a zero-width constraint, which the
    /// required compression resistance would fight.
    func collapse() {
        isCollapsed = true
        invalidateIntrinsicContentSize()
    }

    /// Leading padding, the label, then the trailing region — which is the same padding again plus
    /// the divider and chevron when the picker is offered.
    override var intrinsicContentSize: NSSize {
        guard !isCollapsed else { return NSSize(width: 0, height: Constants.height) }

        var width = Constants.horizontalPadding + titleLabel.intrinsicContentSize.width + Constants.horizontalPadding
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
