//
//  AIChatContextChipView.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

#if os(iOS)
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

// MARK: - View

/// A chip view displaying page context information with favicon, title, subtitle, remove button,
/// and an info row with separator.
public final class AIChatContextChipView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let chipWidth: CGFloat = 240
        /// Shared by the attached pill and the placeholder button so they never differ in height.
        static let height: CGFloat = 44
        /// The design's rounded pill variant.
        static let cornerRadius: CGFloat = 24
        static let borderWidth: CGFloat = 1
        static let placeholderBorderWidth: CGFloat = 1.5

        static let faviconSize: CGFloat = 28
        /// The design's rounded variant shows a circular favicon, but its asset is a circle with its
        /// own padding. Real site favicons are square and full-bleed, so a circular mask crops them.
        static let faviconCornerRadius: CGFloat = 6
        static let faviconLeading: CGFloat = 10

        static let removeButtonSize: CGFloat = 32
        static let removeButtonTrailing: CGFloat = 10

        static let contentSpacing: CGFloat = 8

        /// The design's `Page Context Placekeeper`: content-sized, 12pt padding, 24pt Ai-Chat glyph,
        /// bold 14 text and a 1.5pt hairline.
        static let placeholderHorizontalPadding: CGFloat = 12
        static let placeholderIconSize: CGFloat = 24
        static let placeholderFontSize: CGFloat = 14
    }

    // MARK: - State

    public enum State {
        case placeholder
        case attached(title: String, favicon: UIImage?)
    }

    private var currentState: State = .placeholder

    /// Bold 14 from the design, scaled so it still honours Dynamic Type.
    private static let placeholderFont = UIFontMetrics(forTextStyle: .footnote)
        .scaledFont(for: .systemFont(ofSize: Constants.placeholderFontSize, weight: .bold))

    private var fixedWidthConstraint: NSLayoutConstraint!
    private var faviconLeadingConstraint: NSLayoutConstraint!
    private var faviconWidthConstraint: NSLayoutConstraint!
    private var faviconHeightConstraint: NSLayoutConstraint!
    private var titleTrailingToRemoveButtonConstraint: NSLayoutConstraint!
    private var titleTrailingToEdgeConstraint: NSLayoutConstraint!

    // MARK: - Properties

    /// Callback invoked when the remove button is tapped.
    public var onRemove: (() -> Void)?

    /// Callback invoked when the chip itself is tapped, which in the placeholder state means the user
    /// is asking for the page to be attached again.
    public var onTap: (() -> Void)?

    // MARK: - UI Components

    private lazy var mainStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var chipContentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var faviconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor(designSystemColor: .textSecondary)
        imageView.backgroundColor = UIColor(designSystemColor: .surface)
        imageView.layer.cornerRadius = Constants.faviconCornerRadius
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxSubheadSemibold()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textTertiary)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size16.close.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = UIColor(designSystemColor: .textSecondary)
        button.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The single writer of the corner radius. It is derived from the laid-out height rather than taken
    /// literally, because the design's 24 exceeds half of the 44pt height and would render as a pointed
    /// kink instead of clamping to a capsule.
    public override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(Constants.cornerRadius, bounds.height / 2)
    }

    // MARK: - Configuration

    /// Configures the chip with the given state.
    ///
    /// - Parameter state: The state to display (placeholder or attached with title/favicon).
    public func configure(state: State) {
        currentState = state
        updateUI(for: state)
    }

    /// Configures the chip with the given title and optional favicon (attached state).
    ///
    /// - Parameters:
    ///   - title: The page title to display.
    ///   - favicon: The favicon image. If nil, a placeholder is shown.
    public func configure(title: String, favicon: UIImage?) {
        configure(state: .attached(title: title, favicon: favicon))
    }

    /// Updates the chip content, preserving the existing favicon if the new one is nil.
    ///
    /// - Parameters:
    ///   - title: The new page title to display.
    ///   - favicon: The new favicon image. If nil, the existing favicon is preserved.
    public func update(title: String, favicon: UIImage?) {
        guard case .attached = currentState else { return }
        titleLabel.text = title
        if let favicon {
            faviconView.image = favicon
        }
        accessibilityLabel = title
    }
}

// MARK: - Private Setup

private extension AIChatContextChipView {

    func setupUI() {
        backgroundColor = .clear
        // Never varies by state; the radius itself is set in `layoutSubviews`, which owns it.
        layer.cornerCurve = .continuous
        clipsToBounds = true

        addSubview(mainStackView)

        chipContentView.addSubview(faviconView)
        chipContentView.addSubview(titleLabel)
        chipContentView.addSubview(removeButton)
        mainStackView.addArrangedSubview(chipContentView)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chipTapped)))

        setupConstraints()
        setupAccessibility()
    }

    func updateUI(for state: State) {
        switch state {
        case .placeholder:
            // Reads as a button, since tapping it re-attaches the page the user removed. Keeping it in
            // the strip means removing and re-attaching never changes the input's height.
            titleLabel.text = UserText.askAboutPage
            titleLabel.accessibilityIdentifier = "AIChat.ContextChip.Placeholder"
            titleLabel.textColor = UIColor(designSystemColor: .textSecondary)
            titleLabel.font = Self.placeholderFont
            faviconView.image = DesignSystemImages.Glyphs.Size24.aiChat.withRenderingMode(.alwaysTemplate)
            faviconView.tintColor = UIColor(designSystemColor: .iconsTertiary)
            faviconView.backgroundColor = .clear
            faviconView.layer.borderWidth = 0
            faviconView.layer.borderColor = nil
            isHidden = false
            backgroundColor = .clear
            removeButton.isHidden = true
            accessibilityLabel = UserText.askAboutPage
            accessibilityTraits = .button
            applyBorder(width: Constants.placeholderBorderWidth)
            applyLayout(hugsContent: true)
            isUserInteractionEnabled = true

        case .attached(let title, let favicon):
            isHidden = false
            titleLabel.text = title
            titleLabel.accessibilityIdentifier = "AIChat.ContextChip.AttachedTitle"
            titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
            titleLabel.font = UIFont.daxSubheadSemibold()
            applyLayout(hugsContent: false)
            removeButton.isHidden = false
            faviconView.tintColor = UIColor(designSystemColor: .textSecondary)
            faviconView.image = favicon ?? placeholderFavicon()
            faviconView.backgroundColor = .clear
            faviconView.layer.borderWidth = 0
            faviconView.layer.borderColor = nil
            backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
            accessibilityLabel = title
            applyBorder(width: Constants.borderWidth)
            isUserInteractionEnabled = true
        }
    }

    /// The placeholder button hugs its label with 12pt padding and a 24pt glyph; the attached pill is a
    /// fixed width with its label running up to the remove button.
    func applyLayout(hugsContent: Bool) {
        fixedWidthConstraint.isActive = !hugsContent
        titleTrailingToRemoveButtonConstraint.isActive = !hugsContent
        titleTrailingToEdgeConstraint.isActive = hugsContent
        faviconLeadingConstraint.constant = hugsContent ? Constants.placeholderHorizontalPadding : Constants.faviconLeading
        let iconSize = hugsContent ? Constants.placeholderIconSize : Constants.faviconSize
        faviconWidthConstraint.constant = iconSize
        faviconHeightConstraint.constant = iconSize
    }

    /// `lines` rather than `decorationPrimary`: the design calls for black at 9%, which `lines` matches
    /// and `decorationPrimary` does not — it is 30%.
    func applyBorder(width: CGFloat) {
        layer.borderWidth = width
        layer.borderColor = UIColor(designSystemColor: .lines).cgColor
    }

    func setupConstraints() {
        // One height for every state, so swapping the icon size between the attached pill and the
        // placeholder button can't change how tall the chip is. Centred contents rather than
        // top-and-bottom padding, which would otherwise pin the height to the icon's size.
        //
        // The host can collapse the chip via an external `height == 0` constraint while it's hidden,
        // so this stays below required priority to break gracefully when that happens.
        let height = heightAnchor.constraint(equalToConstant: Constants.height)
        height.priority = .defaultHigh

        let width = widthAnchor.constraint(equalToConstant: Constants.chipWidth)
        fixedWidthConstraint = width

        let faviconLeading = faviconView.leadingAnchor.constraint(equalTo: chipContentView.leadingAnchor, constant: Constants.faviconLeading)
        faviconLeadingConstraint = faviconLeading
        let faviconWidth = faviconView.widthAnchor.constraint(equalToConstant: Constants.faviconSize)
        faviconWidthConstraint = faviconWidth
        let faviconHeight = faviconView.heightAnchor.constraint(equalToConstant: Constants.faviconSize)
        faviconHeightConstraint = faviconHeight

        // Only one of these is active at a time: the remove button is absent in the placeholder state,
        // so the label runs to the chip's own edge instead.
        titleTrailingToRemoveButtonConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -Constants.contentSpacing)
        titleTrailingToEdgeConstraint = titleLabel.trailingAnchor.constraint(equalTo: chipContentView.trailingAnchor, constant: -Constants.placeholderHorizontalPadding)

        NSLayoutConstraint.activate([
            width,

            mainStackView.topAnchor.constraint(equalTo: topAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            height,

            faviconLeading,
            faviconView.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor),
            faviconWidth,
            faviconHeight,

            titleLabel.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: Constants.contentSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor),
            titleTrailingToRemoveButtonConstraint,

            removeButton.trailingAnchor.constraint(equalTo: chipContentView.trailingAnchor, constant: -Constants.removeButtonTrailing),
            removeButton.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize),
        ])
    }

    func setupAccessibility() {
        isAccessibilityElement = false
        removeButton.accessibilityLabel = "Remove"
        removeButton.accessibilityIdentifier = "AIChat.ContextChip.RemoveButton"
        removeButton.accessibilityTraits = .button
    }

    func placeholderFavicon() -> UIImage? {
        return DesignSystemImages.Glyphs.Size24.globe.withRenderingMode(.alwaysTemplate)
    }

    @objc func removeButtonTapped() {
        onRemove?()
    }

    /// Only the placeholder is a button. In the attached state a tap anywhere but the X means nothing,
    /// so the gesture must not reach `onTap` — its one consumer asks for the page to be re-attached.
    @objc func chipTapped() {
        guard case .placeholder = currentState else { return }
        onTap?()
    }
}

// MARK: - Trait Changes

extension AIChatContextChipView {

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.borderColor = UIColor(designSystemColor: .lines).cgColor
            backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
            // Update favicon border color for dark mode (placeholder state only)
            if faviconView.layer.borderWidth > 0 {
                faviconView.layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor
            }
        }
    }
}
#endif
