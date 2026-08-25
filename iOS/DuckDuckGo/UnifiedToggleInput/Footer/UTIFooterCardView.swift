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
        static let contentLeading: CGFloat = 16
        static let contentTrailing: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconTextGap: CGFloat = 10
        static let textSpacing: CGFloat = 1
        static let actionSpacing: CGFloat = 8
        static let dismissSize: CGFloat = 32
    }

    var onPrimaryTap: (() -> Void)?
    var onDismissTap: (() -> Void)?

    /// The toolbar's model-picker menu, reused so the card offers the same list. UIKit presents it
    /// from the chevron, which is what anchors the menu to the control the user tapped.
    var modelPickerMenu: UIMenu? {
        didSet { actionButton.modelPickerMenu = modelPickerMenu }
    }

    let contentView = UIView()

    private let usageRing = UTIFooterUsageRingView()
    private let alertIcon = UIImageView(image: DesignSystemImages.Glyphs.Size16.alertRecolorable)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UTIFooterActionButton()
    private let dismissButton = UIButton(type: .system)

    private var actionCollapsedWidthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: UTIFooterMessage, animateIcon: Bool) {
        switch message.icon {
        case .usageRing(let progress):
            usageRing.isHidden = false
            alertIcon.isHidden = true
            usageRing.setProgress(progress, animated: animateIcon)
        case .alert:
            usageRing.isHidden = true
            alertIcon.isHidden = false
        }

        titleLabel.text = message.title
        subtitleLabel.text = message.subtitle
        subtitleLabel.isHidden = message.subtitle?.isEmpty ?? true

        if let primaryAction = message.primaryAction {
            actionButton.isHidden = false
            actionButton.configure(title: primaryAction.title, showsModelPicker: primaryAction.showsModelPicker)
        } else {
            actionButton.isHidden = true
        }
        // Hidden views still take part in Auto Layout, so the footprint collapses explicitly.
        actionCollapsedWidthConstraint?.isActive = message.primaryAction == nil

        dismissButton.isHidden = !message.isDismissible
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
}

// MARK: - Setup

private extension UTIFooterCardView {

    func setupUI() {
        layer.cornerRadius = Constants.cornerRadius
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        clipsToBounds = true

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        [usageRing, alertIcon].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentHuggingPriority(.required, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
            contentView.addSubview($0)
        }
        alertIcon.contentMode = .scaleAspectFit
        alertIcon.isHidden = true

        for label in [titleLabel, subtitleLabel] {
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.adjustsFontForContentSizeCategory = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        titleLabel.font = .daxFootnoteSemibold()
        subtitleLabel.font = .daxCaption1()

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = Constants.textSpacing
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textStack)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.onPrimaryTap = { [weak self] in self?.onPrimaryTap?() }
        contentView.addSubview(actionButton)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.setImage(DesignSystemImages.Glyphs.Size16.close, for: .normal)
        dismissButton.accessibilityLabel = UserText.utiDuckAIWarningsDismissAccessibilityLabel
        dismissButton.setContentHuggingPriority(.required, for: .horizontal)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .primaryActionTriggered)
        contentView.addSubview(dismissButton)

        let contentTop = contentView.topAnchor.constraint(equalTo: topAnchor, constant: Self.overlap + Constants.contentTopGap)
        contentTop.priority = .defaultHigh

        let actionCollapsedWidth = actionButton.widthAnchor.constraint(equalToConstant: 0)
        actionCollapsedWidthConstraint = actionCollapsedWidth

        NSLayoutConstraint.activate([
            contentTop,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.contentLeading),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.contentTrailing),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.contentBottom),

            usageRing.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            usageRing.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            usageRing.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            usageRing.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            alertIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            alertIcon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            alertIcon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            alertIcon.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            textStack.leadingAnchor.constraint(equalTo: usageRing.trailingAnchor, constant: Constants.iconTextGap),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            textStack.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -Constants.actionSpacing),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -Constants.actionSpacing),
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
        dismissButton.tintColor = UIColor(designSystemColor: .iconsSecondary)
        actionButton.applyColors()
    }
}

// MARK: - Action button

/// The card's CTA: a pill with the primary action, and optionally a divider and the chevron that
/// opens the model picker.
///
/// Two hit regions because the view model exposes them separately — the title applies the suggested
/// model, the chevron offers the whole list.
final class UTIFooterActionButton: UIView {

    private enum Constants {
        static let height: CGFloat = 34
        static let titleHorizontalPadding: CGFloat = 14
        static let chevronRegionWidth: CGFloat = 28
        static let chevronSize: CGFloat = 16
        static let dividerWidth: CGFloat = 1
        static let dividerVerticalInset: CGFloat = 8
        static let strokeWidth: CGFloat = 0.5
    }

    var onPrimaryTap: (() -> Void)?

    /// The chevron stays down without a menu to show: a control that opens nothing is worse than none.
    var modelPickerMenu: UIMenu? {
        didSet {
            pickerButton.menu = modelPickerMenu
            pickerButton.showsMenuAsPrimaryAction = modelPickerMenu != nil
            applyPickerVisibility()
        }
    }

    private let primaryButton = UIButton(type: .system)
    private let pickerButton = UIButton(type: .system)
    private let dividerView = UIView()

    private var showsModelPicker = false

    private var dividerWidthConstraint: NSLayoutConstraint?
    private var pickerRegionWidthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, showsModelPicker: Bool) {
        primaryButton.configuration?.title = title
        self.showsModelPicker = showsModelPicker
        applyPickerVisibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func applyColors() {
        backgroundColor = UIColor(designSystemColor: .surfaceCanvas)
        layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        dividerView.backgroundColor = UIColor(designSystemColor: .lines)
        primaryButton.configuration?.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        pickerButton.tintColor = UIColor(designSystemColor: .textPrimary)
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
        layer.borderWidth = Constants.strokeWidth

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.configuration = Self.makePrimaryConfiguration()
        // The label gives before the pill does, so a zero-width collapse can't break the layout.
        primaryButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .primaryActionTriggered)
        addSubview(primaryButton)

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dividerView)

        pickerButton.translatesAutoresizingMaskIntoConstraints = false
        pickerButton.setImage(DesignSystemImages.Glyphs.Size16.chevronDownMedium, for: .normal)
        pickerButton.accessibilityLabel = UserText.utiDuckAIWarningsModelPickerAccessibilityLabel
        addSubview(pickerButton)

        let dividerWidth = dividerView.widthAnchor.constraint(equalToConstant: Constants.dividerWidth)
        dividerWidthConstraint = dividerWidth
        let pickerRegionWidth = pickerButton.widthAnchor.constraint(equalToConstant: Constants.chevronRegionWidth)
        pickerRegionWidthConstraint = pickerRegionWidth

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.height),

            primaryButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            primaryButton.topAnchor.constraint(equalTo: topAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            dividerView.leadingAnchor.constraint(equalTo: primaryButton.trailingAnchor),
            dividerWidth,
            dividerView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.dividerVerticalInset),
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.dividerVerticalInset),

            pickerButton.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            pickerButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            pickerButton.topAnchor.constraint(equalTo: topAnchor),
            pickerButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            pickerRegionWidth
        ])

        applyPickerVisibility()
        applyColors()
    }

    /// The chevron needs both an offer and a menu; the trailing padding grows back without it, so a
    /// plain pill keeps its symmetry.
    private func applyPickerVisibility() {
        let isVisible = showsModelPicker && modelPickerMenu != nil
        dividerView.isHidden = !isVisible
        pickerButton.isHidden = !isVisible
        dividerWidthConstraint?.constant = isVisible ? Constants.dividerWidth : 0
        pickerRegionWidthConstraint?.constant = isVisible ? Constants.chevronRegionWidth : 0
        primaryButton.configuration?.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: Constants.titleHorizontalPadding,
            bottom: 0,
            trailing: isVisible ? Constants.titleHorizontalPadding - Constants.chevronRegionWidth / 2 : Constants.titleHorizontalPadding
        )
    }

    private static func makePrimaryConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
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
