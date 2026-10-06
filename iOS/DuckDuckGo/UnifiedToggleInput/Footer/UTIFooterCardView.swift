//
//  UTIFooterCardView.swift
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

final class UTIFooterCardView: UIView {

    static let overlap: CGFloat = 44
    static let cornerRadius: CGFloat = 28

    private enum Constants {
        static let contentTopGap: CGFloat = 12
        static let contentBottom: CGFloat = 12
        static let contentLeading: CGFloat = 20
        static let contentTrailing: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconTextGap: CGFloat = 10
        static let textSpacing: CGFloat = 1
        static let actionSpacing: CGFloat = 8
        static let dismissSize: CGFloat = 32
        /// What the dismiss button and its gap take off the trailing edge when the card carries one.
        static let dismissTrailingFootprint: CGFloat = dismissSize + actionSpacing
    }

    var onPrimaryTap: (() -> Void)?
    var onDismissTap: (() -> Void)?
    var onLinkTap: ((URL) -> Void)?

    let contentView = UIView()

    /// A card under another one drops its top gap, so the two read as one block instead of doubling the margin.
    var isBelowAnotherCard = false {
        didSet { contentTopConstraint?.constant = Self.overlap + (isBelowAnotherCard ? 0 : Constants.contentTopGap) }
    }

    private let usageRing = UTIFooterUsageRingView()
    private let alertIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.alertRecolorable)
    private let infoIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.info)
    private let modelSwitchIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.importExport)
    private let shieldIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.shieldCheck)
    private let giftIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.gift)
    private let titleLabel = UILabel()
    private let linkTextView = UTIFooterLinkTextView()
    private let subtitleLabel = UILabel()
    private let actionButton = UTIFooterActionButton()
    private let dismissButton = UIButton(type: .system)

    private var contentTopConstraint: NSLayoutConstraint?
    private var actionCollapsedWidthConstraint: NSLayoutConstraint?
    private var actionTrailingConstraint: NSLayoutConstraint?
    private var iconSlotWidthConstraint: NSLayoutConstraint?
    private var iconTextGapConstraint: NSLayoutConstraint?
    private var formattedTitleMessage: UTIFooterMessage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: UTIFooterMessage, animateIcon: Bool) {
        let visibleIcon: UIView?
        switch message.icon {
        case .none:
            visibleIcon = nil
        case .usageRing(let progress, let severity):
            visibleIcon = usageRing
            usageRing.setProgress(progress, severity: severity, animated: animateIcon)
        case .alert:
            visibleIcon = alertIcon
        case .info:
            visibleIcon = infoIcon
        case .modelSwitch:
            visibleIcon = modelSwitchIcon
        case .shield:
            visibleIcon = shieldIcon
        case .gift:
            visibleIcon = giftIcon
        }
        allIcons.forEach { $0.isHidden = $0 !== visibleIcon }
        let hasIcon = message.icon != UTIFooterMessage.Icon.none
        iconSlotWidthConstraint?.constant = hasIcon ? Constants.iconSize : 0
        iconTextGapConstraint?.constant = hasIcon ? Constants.iconTextGap : 0

        if message.titleFormatting != nil {
            formattedTitleMessage = message
            applyFormattedTitle()
        } else {
            if formattedTitleMessage != nil {
                titleLabel.attributedText = nil
                titleLabel.accessibilityLabel = nil
                formattedTitleMessage = nil
            }
            // A title above a reset line is a headline; a standalone one is body copy.
            let isStandaloneCopy = message.subtitle == nil
            titleLabel.font = isStandaloneCopy ? .daxFootnoteRegular() : .daxFootnoteSemibold()
            titleLabel.text = message.title
        }
        // A label can't take a tap on part of its text, so copy carrying a link renders in the text view.
        titleLabel.isHidden = message.link != nil
        linkTextView.isHidden = message.link == nil
        if let link = message.link {
            linkTextView.configure(text: message.title, link: link)
        }

        subtitleLabel.numberOfLines = message.icon == .modelSwitch ? 3 : (message.primaryAction == nil ? 2 : 1)
        subtitleLabel.text = message.subtitle
        subtitleLabel.isHidden = message.subtitle?.isEmpty ?? true

        if let primaryAction = message.primaryAction {
            actionButton.isHidden = false
            actionButton.configure(title: primaryAction.title)
        } else {
            actionButton.isHidden = true
        }
        // Hidden views still take part in Auto Layout, so the footprint collapses explicitly.
        actionCollapsedWidthConstraint?.isActive = message.primaryAction == nil

        dismissButton.isHidden = !message.isDismissible
        // Otherwise the CTA stops short of the trailing edge by the width of a close button that
        // isn't there.
        actionTrailingConstraint?.constant = message.isDismissible ? -Constants.dismissTrailingFootprint : 0
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let colorAppearanceChanged = traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection)
        if colorAppearanceChanged {
            applyColors()
        }
        if formattedTitleMessage != nil,
           colorAppearanceChanged || traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            applyFormattedTitle()
        }
    }

    @objc private func dismissTapped() {
        onDismissTap?()
    }

    private var allIcons: [UIView] {
        [usageRing, alertIcon, infoIcon, modelSwitchIcon, shieldIcon, giftIcon]
    }

    private func applyFormattedTitle() {
        guard let message = formattedTitleMessage, let formatting = message.titleFormatting else { return }
        let font: UIFont = message.subtitle == nil ? .daxFootnoteRegular() : .daxFootnoteSemibold()
        titleLabel.font = font

        let title = NSMutableAttributedString(string: message.title, attributes: [.font: font])
        let emphasisRange = (title.string as NSString).range(of: formatting.emphasizedText)
        if emphasisRange.location != NSNotFound, emphasisRange.length > 0 {
            title.addAttribute(.font, value: UIFont.daxFootnoteSemibold(), range: emphasisRange)
        }
        let iconRange = (title.string as NSString).range(of: formatting.attachmentPlaceholder)
        if iconRange.location != NSNotFound {
            let attachment = NSTextAttachment()
            attachment.image = DesignSystemImages.Glyphs.Size16.attach.withTintColor(
                UIColor(designSystemColor: .textPrimary).resolvedColor(with: traitCollection), renderingMode: .alwaysOriginal)
            let size = UIFontMetrics(forTextStyle: .footnote).scaledValue(for: Constants.iconSize, compatibleWith: traitCollection)
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - size) / 2, width: size, height: size)
            title.replaceCharacters(in: iconRange, with: NSAttributedString(attachment: attachment))
        }
        titleLabel.attributedText = title
        titleLabel.accessibilityLabel = message.title.replacingOccurrences(of: formatting.attachmentPlaceholder,
                                                                           with: formatting.attachmentAccessibilityLabel)
    }

}

// MARK: - Setup

private extension UTIFooterCardView {

    func setupUI() {
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        clipsToBounds = true
        accessibilityIdentifier = "AIChat.Footer.Card"

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        allIcons.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentHuggingPriority(.required, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
            contentView.addSubview($0)
        }
        usageRing.accessibilityIdentifier = "AIChat.Footer.Icon.UsageRing"
        alertIcon.accessibilityIdentifier = "AIChat.Footer.Icon.Alert"
        infoIcon.accessibilityIdentifier = "AIChat.Footer.Icon.Info"
        modelSwitchIcon.accessibilityIdentifier = "AIChat.Footer.Icon.ModelSwitch"
        shieldIcon.accessibilityIdentifier = "AIChat.Footer.Icon.Shield"
        giftIcon.accessibilityIdentifier = "AIChat.Footer.Icon.Gift"
        [alertIcon, infoIcon, modelSwitchIcon, shieldIcon, giftIcon].forEach {
            $0.contentMode = .scaleAspectFit
            $0.isHidden = true
        }

        for label in [titleLabel, subtitleLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        // The title carries the message, so it wraps; the reset line under it is short enough
        // to stay on one line.
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = .daxFootnoteSemibold()
        titleLabel.accessibilityIdentifier = "AIChat.Footer.Label.Title"
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .daxCaption1()
        subtitleLabel.accessibilityIdentifier = "AIChat.Footer.Label.Subtitle"

        linkTextView.accessibilityIdentifier = "AIChat.Footer.Label.Link"
        linkTextView.isHidden = true
        linkTextView.onLinkTap = { [weak self] url in self?.onLinkTap?(url) }

        let textStack = UIStackView(arrangedSubviews: [titleLabel, linkTextView, subtitleLabel])
        textStack.axis = .vertical
        // `.fill`, not `.leading`: a leading-aligned label keeps the width its own content was last
        // measured at, and this card is measured at the flanked width too, where there is no room.
        textStack.alignment = .fill
        textStack.spacing = Constants.textSpacing
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textStack)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.onPrimaryTap = { [weak self] in self?.onPrimaryTap?() }
        contentView.addSubview(actionButton)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.setImage(DesignSystemImages.Glyphs.Size16.close, for: .normal)
        dismissButton.accessibilityLabel = UserText.utiDuckAIWarningsDismissAccessibilityLabel
        dismissButton.accessibilityIdentifier = "AIChat.Footer.Button.Dismiss"
        dismissButton.setContentHuggingPriority(.required, for: .horizontal)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .primaryActionTriggered)
        contentView.addSubview(dismissButton)

        let contentTop = contentView.topAnchor.constraint(equalTo: topAnchor, constant: Self.overlap + Constants.contentTopGap)
        contentTopConstraint = contentTop

        let actionCollapsedWidth = actionButton.widthAnchor.constraint(equalToConstant: 0)
        actionCollapsedWidthConstraint = actionCollapsedWidth

        // Pinned to the content rather than to the dismiss button, so a hidden dismiss button leaves
        // no gap behind it.
        let actionTrailing = actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                                   constant: -Constants.dismissTrailingFootprint)
        actionTrailingConstraint = actionTrailing

        let iconSlotWidth = usageRing.widthAnchor.constraint(equalToConstant: Constants.iconSize)
        iconSlotWidthConstraint = iconSlotWidth
        let iconTextGap = textStack.leadingAnchor.constraint(equalTo: usageRing.trailingAnchor,
                                                            constant: Constants.iconTextGap)
        iconTextGapConstraint = iconTextGap

        NSLayoutConstraint.activate([
            contentTop,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.contentLeading),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.contentTrailing),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.contentBottom),

            usageRing.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            usageRing.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            iconSlotWidth,
            usageRing.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            alertIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            alertIcon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            alertIcon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            alertIcon.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            infoIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            infoIcon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            infoIcon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            infoIcon.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            modelSwitchIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            modelSwitchIcon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            modelSwitchIcon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            modelSwitchIcon.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            shieldIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shieldIcon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            shieldIcon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            shieldIcon.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            giftIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            giftIcon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            giftIcon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            giftIcon.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            iconTextGap,
            // Centered rather than stretched: the controls keep the content at least their height even
            // when hidden, and a text view stretched to that draws its one line at the top.
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor).withPriority(.defaultLow),

            textStack.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -Constants.actionSpacing),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionTrailing,
            actionButton.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            actionButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),

            dismissButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dismissButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            dismissButton.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            dismissButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: Constants.dismissSize),
            dismissButton.heightAnchor.constraint(equalToConstant: Constants.dismissSize),
        ])

        applyColors()
    }

    func applyColors() {
        backgroundColor = UIColor(designSystemColor: .surfaceSecondary)
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
        subtitleLabel.textColor = UIColor(designSystemColor: .textSecondary)
        alertIcon.tintColor = UIColor(designSystemColor: .icons)
        infoIcon.tintColor = UIColor(designSystemColor: .iconsSecondary)
        modelSwitchIcon.tintColor = UIColor(designSystemColor: .icons)
        shieldIcon.tintColor = UIColor(designSystemColor: .iconsSecondary)
        giftIcon.tintColor = UIColor(designSystemColor: .iconsSecondary)
        linkTextView.applyColors()
        dismissButton.tintColor = UIColor(designSystemColor: .iconsSecondary)
        actionButton.applyColors()
    }
}

// MARK: - Action button

/// The card's CTA: a plain pill. The model picker lives in the toolbar, not here.
final class UTIFooterActionButton: UIView {

    private enum Constants {
        static let height: CGFloat = 34
        static let titleHorizontalPadding: CGFloat = 14
    }

    var onPrimaryTap: (() -> Void)?

    private let primaryButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        primaryButton.configuration?.title = title
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func applyColors() {
        backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        primaryButton.configuration?.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }

    private func setupUI() {
        clipsToBounds = true
        layer.cornerCurve = .continuous

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.accessibilityIdentifier = "AIChat.Footer.Button.Primary"
        primaryButton.configuration = Self.makePrimaryConfiguration()
        // The label gives before the pill does, so a zero-width collapse can't break the layout.
        primaryButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        // Hugging the title makes the text stack's width the remainder rather than the losing side
        // of a tie between two default priorities.
        primaryButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .primaryActionTriggered)
        addSubview(primaryButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.height),

            primaryButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            primaryButton.topAnchor.constraint(equalTo: topAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        applyColors()
    }

    private static func makePrimaryConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                              leading: Constants.titleHorizontalPadding,
                                                              bottom: 0,
                                                              trailing: Constants.titleHorizontalPadding)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .daxFootnoteRegular()
            return outgoing
        }
        return configuration
    }

    @objc private func primaryTapped() {
        onPrimaryTap?()
    }
}

// MARK: - Link text

/// Uses the text view's rendered link rectangles for touch routing, including wrapped and RTL text.
final class UTIFooterLinkTextView: UITextView {
    private static let hitSlop: CGFloat = 8
    var onLinkTap: ((URL) -> Void)?
    private var content: (text: String, link: UTIFooterMessage.Link)?
    private var linkRange: NSRange?

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        adjustsFontForContentSizeCategory = true
        textDragInteraction?.isEnabled = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool { false }

    func configure(text: String, link: UTIFooterMessage.Link) {
        content = (text, link)
        applyColors()
    }

    func applyColors() {
        guard let content else { return }
        let attributed = NSMutableAttributedString(string: content.text, attributes: [
            .font: UIFont.daxFootnoteRegular(),
            .foregroundColor: UIColor(designSystemColor: .textPrimary)
        ])
        let range = (content.text as NSString).range(of: content.link.text, options: .backwards)
        linkRange = range.location == NSNotFound ? nil : range
        if let linkRange {
            attributed.addAttribute(.link, value: content.link.url, range: linkRange)
        }
        attributedText = attributed
        linkTextAttributes = [.foregroundColor: UIColor(designSystemColor: .accentTextPrimary)]
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) ||
            traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            applyColors()
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event), let linkRange,
              let start = position(from: beginningOfDocument, offset: linkRange.location),
              let end = position(from: start, offset: linkRange.length),
              let range = textRange(from: start, to: end) else { return false }
        return selectionRects(for: range).contains {
            !$0.rect.isEmpty && $0.rect.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point)
        }
    }
}

extension UTIFooterLinkTextView: UITextViewDelegate {
    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return nil }
        return UIAction { [weak self] _ in self?.onLinkTap?(url) }
    }

    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        nil
    }

    @available(iOS, deprecated: 17.0)
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if interaction == .invokeDefaultAction {
            onLinkTap?(URL)
        }
        return false
    }
}
