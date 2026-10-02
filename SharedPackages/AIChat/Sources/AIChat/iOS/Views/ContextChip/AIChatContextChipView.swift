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
        /// Shared by every state so they never differ in height.
        static let height: CGFloat = 44
        /// The design's rounded pill variant.
        static let cornerRadius: CGFloat = 24
        static let borderWidth: CGFloat = 1
        /// The offer reads as provisional, so its outline is heavier and broken rather than solid.
        static let suggestedBorderWidth: CGFloat = 1.5
        static let suggestedFillAlpha: CGFloat = 0.4
        static let suggestedBorderAlpha: CGFloat = 0.16
        static let suggestedDashPattern: [NSNumber] = [5, 7]

        static let faviconSize: CGFloat = 28
        static let stripFaviconSize: CGFloat = 20
        static let stripFaviconFrameSize: CGFloat = 24
        static let stripFaviconCornerRadius: CGFloat = 4
        /// The design's rounded variant shows a circular favicon, but its asset is a circle with its
        /// own padding. Real site favicons are square and full-bleed, so a circular mask crops them.
        static let faviconCornerRadius: CGFloat = 6
        static let faviconLeading: CGFloat = 10

        static let removeButtonSize: CGFloat = 32
        static let removeButtonTrailing: CGFloat = 10
        static let removeButtonHitTarget: CGFloat = 44
        static let stripRemoveButtonSize: CGFloat = 28
        static let stripRemoveButtonTrailing: CGFloat = 8

        static let contentSpacing: CGFloat = 8
        static let compactHorizontalPadding: CGFloat = 6
        static let compactContentSpacing: CGFloat = 4
    }

    public enum Style {
        case standalone
        case attachmentStrip
    }

    private let style: Style
    private let faviconLayoutGuide = UILayoutGuide()

    private var faviconSize: CGFloat {
        style == .attachmentStrip ? Constants.stripFaviconSize : Constants.faviconSize
    }

    private var faviconFrameSize: CGFloat {
        style == .attachmentStrip ? Constants.stripFaviconFrameSize : Constants.faviconSize
    }

    // MARK: - State

    public enum State {
        case suggested(title: String, favicon: UIImage?)
        case attached(title: String, favicon: UIImage?)
        case loading
    }

    private var currentState: State?
    private var loadingView: AIChatSuggestionsLoadingView?

    private lazy var chipTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(chipTapped))
        recognizer.delegate = self
        return recognizer
    }()

    /// `layer.borderWidth` cannot dash, so the suggested state draws its own outline.
    private lazy var dashedBorderLayer: CAShapeLayer = {
        let border = CAShapeLayer()
        border.fillColor = UIColor.clear.cgColor
        border.lineWidth = Constants.suggestedBorderWidth
        border.lineDashPattern = Constants.suggestedDashPattern
        border.isHidden = true
        return border
    }()

    private var fixedWidthConstraint: NSLayoutConstraint!
    private var titleTrailingToRemoveButtonConstraint: NSLayoutConstraint!
    private var faviconLeadingConstraint: NSLayoutConstraint!
    private var titleLeadingConstraint: NSLayoutConstraint!
    private var removeButtonTrailingConstraint: NSLayoutConstraint!
    private var removeButtonWidthConstraint: NSLayoutConstraint!
    private var removeButtonHeightConstraint: NSLayoutConstraint!

    // MARK: - Properties

    /// Callback invoked when the remove button is tapped.
    public var onRemove: (() -> Void)?

    /// Callback invoked when the chip itself is tapped, which in the suggested state means the user
    /// is asking for the page to be attached.
    public var onTap: (() -> Void)?

    /// Hosts can override the default width, including the loading state.
    public var preferredWidth: CGFloat? {
        didSet {
            guard preferredWidth != oldValue else { return }
            updateLayout()
        }
    }

    /// Minimum attachment-strip width that keeps the first character, ellipsis and title gaps readable.
    public var minimumContentWidth: CGFloat {
        let title = titleLabel.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let compactTitle = String(title.prefix(1)) + "…"
        let font = titleLabel.font ?? .daxSubheadSemibold()
        let titleWidth = ceil((compactTitle as NSString).size(withAttributes: [.font: font]).width) + 1
        return Constants.compactHorizontalPadding + Constants.stripRemoveButtonTrailing + faviconFrameSize + titleWidth
            + 2 * Constants.compactContentSpacing + Constants.stripRemoveButtonSize
    }

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
        imageView.layer.cornerRadius = style == .attachmentStrip ? Constants.stripFaviconCornerRadius : Constants.faviconCornerRadius
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

    private lazy var removeButton: ExpandedHitTargetButton = {
        let button = ExpandedHitTargetButton(type: .system)
        button.minimumHitTarget = Constants.removeButtonHitTarget
        button.setImage(DesignSystemImages.Glyphs.Size16.close.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = UIColor(designSystemColor: .textSecondary)
        button.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = Constants.removeButtonSize / 2
        return button
    }()

    // MARK: - Initialization

    public override convenience init(frame: CGRect) {
        self.init(style: .standalone, frame: frame)
    }

    public init(style: Style, frame: CGRect = .zero) {
        self.style = style
        super.init(frame: frame)
        setupUI()
        updateLayout()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Clamped to a capsule: the design's 24 exceeds half the 44pt height and would kink.
    public override func layoutSubviews() {
        updateContentSpacing()
        super.layoutSubviews()
        layer.cornerRadius = min(Constants.cornerRadius, bounds.height / 2)

        dashedBorderLayer.frame = bounds
        let inset = Constants.suggestedBorderWidth / 2
        dashedBorderLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            cornerRadius: layer.cornerRadius - inset
        ).cgPath
    }

    // MARK: - Configuration

    /// Configures the chip with the given state.
    ///
    /// - Parameter state: The state to display (suggested, attached or loading).
    public func configure(state: State) {
        currentState = state
        updateUI(for: state)
    }

    /// Configures the chip with the given title and optional favicon (attached state).
    ///
    /// - Parameters:
    ///   - title: The page title to display.
    ///   - favicon: The favicon image. If nil, a fallback glyph is shown.
    public func configure(title: String, favicon: UIImage?) {
        configure(state: .attached(title: title, favicon: favicon))
    }

    /// Updates the chip content, preserving the existing favicon if the new one is nil.
    ///
    /// - Parameters:
    ///   - title: The new page title to display.
    ///   - favicon: The new favicon image. If nil, the existing favicon is preserved.
    public func update(title: String, favicon: UIImage?) {
        guard case .attached? = currentState else { return }
        titleLabel.text = title
        if let favicon {
            faviconView.image = favicon
        }
        accessibilityLabel = title
    }

    /// Without this the recogniser, which spans the pill, would swallow taps on the remove button.
    func shouldReceiveChipTap(at point: CGPoint) -> Bool {
        !removeButtonHitRect.contains(point)
    }

    private var removeButtonHitRect: CGRect {
        let frame = removeButton.convert(removeButton.bounds, to: self)
        let outset = max(0, (Constants.removeButtonHitTarget - frame.width) / 2)
        return frame.insetBy(dx: -outset, dy: -outset)
    }

    /// VoiceOver activation mirrors a tap, so the offer can be accepted without sighted pointing.
    public override func accessibilityActivate() -> Bool {
        guard case .suggested = currentState else { return false }
        onTap?()
        return true
    }
}

// MARK: - Private Setup

private extension AIChatContextChipView {

    func setupUI() {
        backgroundColor = .clear
        // Never varies by state; the radius itself is set in `layoutSubviews`, which owns it.
        layer.cornerCurve = .continuous
        clipsToBounds = true

        layer.addSublayer(dashedBorderLayer)
        addSubview(mainStackView)

        chipContentView.addLayoutGuide(faviconLayoutGuide)
        chipContentView.addSubview(faviconView)
        chipContentView.addSubview(titleLabel)
        chipContentView.addSubview(removeButton)
        mainStackView.addArrangedSubview(chipContentView)

        addGestureRecognizer(chipTapRecognizer)

        setupConstraints()
        setupAccessibility()
    }

    func updateUI(for state: State) {
        hideLoadingView()
        faviconView.isHidden = false
        titleLabel.isHidden = false
        // Everything the suggested state adds, undone: it is the only state that draws them, and a
        // chip is reused across states rather than rebuilt.
        removeButton.backgroundColor = .clear
        dashedBorderLayer.isHidden = true
        accessibilityCustomActions = nil

        switch state {
        case .loading:
            isHidden = false
            faviconView.isHidden = true
            titleLabel.isHidden = true
            removeButton.isHidden = true
            backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
            applyBorder(color: UIColor(designSystemColor: .lines))
            fixedWidthConstraint.isActive = preferredWidth != nil
            titleTrailingToRemoveButtonConstraint.isActive = false
            showLoadingView()
            isUserInteractionEnabled = false
            chipTapRecognizer.isEnabled = false
            isAccessibilityElement = true
            accessibilityIdentifier = "AIChat.ContextChip.Loading"
            accessibilityLabel = UserText.askAboutPage
            accessibilityTraits = .none

        case .suggested(let title, let favicon):
            let offer = UserText.askAboutPage(title: title)
            isHidden = false
            titleLabel.text = offer
            titleLabel.accessibilityIdentifier = "AIChat.ContextChip.SuggestedTitle"
            titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
            titleLabel.accessibilityLabel = nil
            titleLabel.accessibilityTraits = .none
            applyPillLayout()
            removeButton.isHidden = false
            removeButton.tintColor = UIColor(designSystemColor: .icons)
            faviconView.tintColor = UIColor(designSystemColor: .accentPrimary)
            faviconView.image = favicon ?? fallbackFavicon()
            faviconView.backgroundColor = .clear
            faviconView.layer.borderWidth = 0
            faviconView.layer.borderColor = nil
            backgroundColor = UIColor(designSystemColor: .accentAltGlowPrimary)
                .withAlphaComponent(Constants.suggestedFillAlpha)
            // The chip itself is the button, so VoiceOver activate accepts the offer (a UILabel marked
            // as a button cannot be activated). Making the chip an element hides the X, so dismissal is
            // offered as a custom action instead.
            isAccessibilityElement = true
            accessibilityIdentifier = "AIChat.ContextChip.Suggested"
            accessibilityLabel = offer
            accessibilityTraits = .button
            accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: removeButton.accessibilityLabel ?? "Remove") { [weak self] _ in
                    self?.onRemove?()
                    return true
                }
            ]
            applyDashedBorder(color: UIColor(designSystemColor: .accentPrimary)
                .withAlphaComponent(Constants.suggestedBorderAlpha))
            isUserInteractionEnabled = true
            chipTapRecognizer.isEnabled = true

        case .attached(let title, let favicon):
            isHidden = false
            titleLabel.text = title
            titleLabel.accessibilityIdentifier = "AIChat.ContextChip.AttachedTitle"
            titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
            titleLabel.accessibilityLabel = nil
            titleLabel.accessibilityTraits = .none
            applyPillLayout()
            removeButton.isHidden = false
            removeButton.tintColor = UIColor(designSystemColor: .textSecondary)
            faviconView.tintColor = UIColor(designSystemColor: .textSecondary)
            faviconView.image = favicon ?? fallbackFavicon()
            faviconView.backgroundColor = .clear
            faviconView.layer.borderWidth = 0
            faviconView.layer.borderColor = nil
            backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
            // The title and the remove button are the elements here, not the chip itself.
            isAccessibilityElement = false
            accessibilityIdentifier = nil
            accessibilityLabel = title
            accessibilityTraits = .none
            applyBorder(color: UIColor(designSystemColor: .lines))
            isUserInteractionEnabled = true
            chipTapRecognizer.isEnabled = false
        }
        updateLayout()
    }

    /// `.loading` drops the fixed geometry, so the pill states have to put it back.
    func applyPillLayout() {
        fixedWidthConstraint.isActive = true
        titleTrailingToRemoveButtonConstraint.isActive = true
    }

    func updateLayout() {
        fixedWidthConstraint.constant = preferredWidth ?? Constants.chipWidth
        updateRemoveButtonAppearance()
        updateContentSpacing()

        if case .loading? = currentState {
            fixedWidthConstraint.isActive = preferredWidth != nil
        } else {
            fixedWidthConstraint.isActive = true
        }
    }

    func updateRemoveButtonAppearance() {
        let size: CGFloat
        let trailingInset: CGFloat
        switch style {
        case .standalone:
            size = Constants.removeButtonSize
            trailingInset = Constants.removeButtonTrailing
            removeButton.backgroundColor = .clear
        case .attachmentStrip:
            size = Constants.stripRemoveButtonSize
            trailingInset = Constants.stripRemoveButtonTrailing
            removeButton.backgroundColor = UIColor(designSystemColor: .controlsRaisedFillPrimary)
        }
        if case .suggested? = currentState {
            removeButton.backgroundColor = UIColor(designSystemColor: .controlsRaisedFillPrimary)
        }
        removeButtonWidthConstraint.constant = size
        removeButtonHeightConstraint.constant = size
        removeButtonTrailingConstraint.constant = -trailingInset
        removeButton.layer.cornerRadius = size / 2
    }

    func updateContentSpacing() {
        guard style == .attachmentStrip else {
            faviconLeadingConstraint.constant = Constants.faviconLeading
            titleLeadingConstraint.constant = Constants.contentSpacing
            titleTrailingToRemoveButtonConstraint.constant = -Constants.contentSpacing
            return
        }

        let leadingExpansion = Constants.faviconLeading - Constants.compactHorizontalPadding
        let spacingExpansion = Constants.contentSpacing - Constants.compactContentSpacing
        let totalExpansion = leadingExpansion + 2 * spacingExpansion
        let width = preferredWidth ?? Constants.chipWidth
        let fraction = min(1, max(0, (width - minimumContentWidth) / totalExpansion))
        faviconLeadingConstraint.constant = Constants.compactHorizontalPadding + leadingExpansion * fraction
        titleLeadingConstraint.constant = Constants.compactContentSpacing + spacingExpansion * fraction
        titleTrailingToRemoveButtonConstraint.constant = -(Constants.compactContentSpacing + spacingExpansion * fraction)
    }

    func applyDashedBorder(color: UIColor) {
        layer.borderWidth = 0
        dashedBorderLayer.isHidden = false
        dashedBorderLayer.strokeColor = color.cgColor
        setNeedsLayout()
    }

    func applyBorder(color: UIColor) {
        layer.borderWidth = Constants.borderWidth
        layer.borderColor = color.cgColor
    }

    func setupConstraints() {
        // One height for every state, so swapping icon sizes can't resize the chip. Below required
        // priority so the host's external `height == 0` collapse can break it.
        let height = heightAnchor.constraint(equalToConstant: Constants.height)
        height.priority = .defaultHigh

        let width = widthAnchor.constraint(equalToConstant: Constants.chipWidth)
        fixedWidthConstraint = width

        faviconLeadingConstraint = faviconLayoutGuide.leadingAnchor.constraint(equalTo: chipContentView.leadingAnchor, constant: Constants.faviconLeading)
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: faviconLayoutGuide.trailingAnchor, constant: Constants.contentSpacing)
        removeButtonTrailingConstraint = removeButton.trailingAnchor.constraint(equalTo: chipContentView.trailingAnchor, constant: -Constants.removeButtonTrailing)
        removeButtonWidthConstraint = removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize)
        removeButtonHeightConstraint = removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize)

        // Dropped by `.loading`, which hugs its spinner instead.
        titleTrailingToRemoveButtonConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -Constants.contentSpacing)

        NSLayoutConstraint.activate([
            width,

            mainStackView.topAnchor.constraint(equalTo: topAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            height,

            faviconLeadingConstraint,
            faviconLayoutGuide.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor),
            faviconLayoutGuide.widthAnchor.constraint(equalToConstant: faviconFrameSize),
            faviconLayoutGuide.heightAnchor.constraint(equalToConstant: faviconFrameSize),
            faviconView.centerXAnchor.constraint(equalTo: faviconLayoutGuide.centerXAnchor),
            faviconView.centerYAnchor.constraint(equalTo: faviconLayoutGuide.centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: faviconSize),
            faviconView.heightAnchor.constraint(equalToConstant: faviconSize),

            titleLeadingConstraint,
            titleLabel.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor),
            titleTrailingToRemoveButtonConstraint,

            removeButtonTrailingConstraint,
            removeButton.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor),
            removeButtonWidthConstraint,
            removeButtonHeightConstraint,
        ])
    }

    func setupAccessibility() {
        removeButton.accessibilityLabel = "Remove"
        removeButton.accessibilityIdentifier = "AIChat.ContextChip.RemoveButton"
        removeButton.accessibilityTraits = .button
    }

    func fallbackFavicon() -> UIImage? {
        if style == .attachmentStrip {
            return DesignSystemImages.Glyphs.Size16.globe.withRenderingMode(.alwaysTemplate)
        }
        return DesignSystemImages.Glyphs.Size24.globe.withRenderingMode(.alwaysTemplate)
    }

    func showLoadingView() {
        guard loadingView == nil else { return }
        let view = AIChatSuggestionsLoadingView()
        view.backgroundColor = .clear
        view.layer.borderWidth = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        chipContentView.addSubview(view)
        let leading = view.leadingAnchor.constraint(equalTo: chipContentView.leadingAnchor)
        let trailing = view.trailingAnchor.constraint(equalTo: chipContentView.trailingAnchor)
        leading.priority = .defaultHigh
        trailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            leading,
            trailing,
            view.centerXAnchor.constraint(equalTo: chipContentView.centerXAnchor),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: chipContentView.leadingAnchor),
            view.trailingAnchor.constraint(lessThanOrEqualTo: chipContentView.trailingAnchor),
            view.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor)
        ])
        loadingView = view
    }

    func hideLoadingView() {
        loadingView?.removeFromSuperview()
        loadingView = nil
    }

    @objc func removeButtonTapped() {
        onRemove?()
    }

    @objc func chipTapped() {
        onTap?()
    }
}

// MARK: - Gesture Delegate

extension AIChatContextChipView: UIGestureRecognizerDelegate {

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        shouldReceiveChipTap(at: touch.location(in: self))
    }
}

// MARK: - Trait Changes

extension AIChatContextChipView {

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
           let currentState {
            updateUI(for: currentState)
        }
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            setNeedsLayout()
        }
    }
}

// MARK: - Expanded Hit Target

private final class ExpandedHitTargetButton: UIButton {

    var minimumHitTarget: CGFloat = 0

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let dx = min(0, (bounds.width - minimumHitTarget) / 2)
        let dy = min(0, (bounds.height - minimumHitTarget) / 2)
        return bounds.insetBy(dx: dx, dy: dy).contains(point)
    }
}
#endif
