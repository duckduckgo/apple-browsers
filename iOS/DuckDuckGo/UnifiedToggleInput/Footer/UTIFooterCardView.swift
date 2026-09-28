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

    private enum Constants {
        static let cornerRadius: CGFloat = 28
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

    private let usageRing = UTIFooterUsageRingView()
    private let alertIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.alertRecolorable)
    private let infoIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.info)
    private let modelSwitchIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.importExport)
    private let shieldIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.shieldCheck)
    private let titleLabel = UILabel()
    private let linkTextView = UTIFooterLinkTextView()
    private let subtitleLabel = UILabel()
    private let actionButton = UTIFooterActionButton()
    private let dismissButton = UIButton(type: .system)

    private var actionCollapsedWidthConstraint: NSLayoutConstraint?
    private var actionTrailingConstraint: NSLayoutConstraint?
    private var iconSlotWidthConstraint: NSLayoutConstraint?
    private var iconTextGapConstraint: NSLayoutConstraint?

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
        }
        allIcons.forEach { $0.isHidden = $0 !== visibleIcon }
        let hasIcon = message.icon != UTIFooterMessage.Icon.none
        iconSlotWidthConstraint?.constant = hasIcon ? Constants.iconSize : 0
        iconTextGapConstraint?.constant = hasIcon ? Constants.iconTextGap : 0

        // A title above a reset line is a headline; a standalone one is body copy.
        let isStandaloneCopy = message.subtitle == nil
        titleLabel.font = isStandaloneCopy ? .daxFootnoteRegular() : .daxFootnoteSemibold()
        titleLabel.text = message.title
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
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }

    @objc private func dismissTapped() {
        onDismissTap?()
    }

    private var allIcons: [UIView] {
        [usageRing, alertIcon, infoIcon, modelSwitchIcon, shieldIcon]
    }

}

// MARK: - Setup

private extension UTIFooterCardView {

    func setupUI() {
        layer.cornerRadius = Constants.cornerRadius
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
        [alertIcon, infoIcon, modelSwitchIcon, shieldIcon].forEach {
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
        contentTop.priority = .defaultHigh

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

            iconTextGap,
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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
        infoIcon.tintColor = UIColor(designSystemColor: .icons)
        modelSwitchIcon.tintColor = UIColor(designSystemColor: .icons)
        shieldIcon.tintColor = UIColor(designSystemColor: .iconsSecondary)
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

/// Body copy with one tappable phrase. A text view rather than a label, so only the phrase takes the
/// tap and VoiceOver can reach it as a link; every other touch falls through to the card.
final class UTIFooterLinkTextView: UITextView {

    private enum Constants {
        /// Widens the phrase's hit area past its glyphs, which are only as tall as the footnote font.
        static let hitSlop: CGFloat = 8
    }

    var onLinkTap: ((URL) -> Void)?

    private var content: (text: String, link: UTIFooterMessage.Link)?

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        // Links only respond in a selectable text view; `point(inside:)` keeps selection off the rest.
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

    func configure(text: String, link: UTIFooterMessage.Link) {
        content = (text, link)
        applyColors()
    }

    /// Rebuilds the copy, since the colors are baked into the attributed string.
    func applyColors() {
        guard let content else { return }
        let attributed = NSMutableAttributedString(string: content.text, attributes: [
            .font: UIFont.daxFootnoteRegular(),
            .foregroundColor: UIColor(designSystemColor: .textSecondary)
        ])
        let linkRange = (content.text as NSString).range(of: content.link.text)
        if linkRange.location != NSNotFound {
            attributed.addAttribute(.link, value: content.link.url, range: linkRange)
        }
        attributedText = attributed
        linkTextAttributes = [.foregroundColor: UIColor(designSystemColor: .accentTextPrimary)]
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) && link(near: point) != nil
    }

    private func link(near point: CGPoint) -> URL? {
        guard let position = closestPosition(to: point),
              let range = tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: .storage(.forward))
                ?? tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: .storage(.backward)),
              firstRect(for: range).insetBy(dx: -Constants.hitSlop, dy: -Constants.hitSlop).contains(point) else { return nil }
        let index = offset(from: beginningOfDocument, to: range.start)
        guard index >= 0, index < attributedText.length else { return nil }
        return attributedText.attribute(.link, at: index, effectiveRange: nil) as? URL
    }
}

extension UTIFooterLinkTextView: UITextViewDelegate {

    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return nil }
        return UIAction { [weak self] _ in self?.onLinkTap?(url) }
    }

    /// No long-press menu: its "Open Link" would leave the app for Safari.
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
