//
//  AIChatQuickActionChipView.swift
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
import UIKit

// MARK: - View

/// A pill-shaped chip view displaying a quick action with icon and label.
public final class AIChatQuickActionChipView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let height: CGFloat = 36
        static let cornerRadius: CGFloat = 12
        static let iconLeadingPadding: CGFloat = 8
        static let trailingPadding: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconLabelSpacing: CGFloat = 6
        static let borderWidth: CGFloat = 1
        static let highlightAlpha: CGFloat = 0.1

        // Glass appearance, per the contextual floating-input design.
        static let glassFontSize: CGFloat = 17
        static let glassShadowOpacity: Float = 0.02
        static let glassShadowRadius: CGFloat = 15
        static let glassShadowOffsetY: CGFloat = 8
        /// Darkens the glass so the pills separate from the page behind them. iOS 26 only — the
        /// earlier blur fallback has no tint to carry it.
        static let glassTintAlphaLight: CGFloat = 0.06
        static let glassTintAlphaDark: CGFloat = 0.14
        /// Outer 8 plus the label group's inner 6, per the design.
        static let glassIconLeadingPadding: CGFloat = 14
        static let glassIconLabelSpacing: CGFloat = 8
        static let glassTrailingPadding: CGFloat = 14
    }

    /// `.translucent` is the sheet's flat fill; `.glass` is the contextual floating input over live page content.
    public enum BackgroundStyle {
        case translucent
        case glass
    }

    // MARK: - Properties

    var onTap: (() -> Void)?

    var backgroundStyle: BackgroundStyle = .translucent {
        didSet { applyBackgroundStyle() }
    }

    private var heightConstraint: NSLayoutConstraint?
    private var contentConstraints: [NSLayoutConstraint] = []
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var iconLabelSpacingConstraint: NSLayoutConstraint?
    private var labelTrailingConstraint: NSLayoutConstraint?
    private var glassBackgroundView: UIVisualEffectView?
    /// Tint the live glass effect was built for, so an unchanged appearance skips the rebuild.
    private var appliedGlassTintAlpha: CGFloat?

    // MARK: - UI Components

    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor(designSystemColor: .textPrimary)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var label: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxButton()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var highlightOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(Constants.highlightAlpha)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGesture()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    public func configure<Action: AIChatQuickActionType>(with action: Action) {
        label.text = action.title
        iconView.image = action.icon?.withRenderingMode(.alwaysTemplate)
        iconView.isHidden = action.icon == nil
        accessibilityLabel = action.title
        accessibilityIdentifier = action.id
    }
}

// MARK: - Private Setup

private extension AIChatQuickActionChipView {

    func applyBackgroundStyle() {
        switch backgroundStyle {
        case .translucent:
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            // The next `.glass` pass builds a bare effect view, so the remembered tint no longer applies.
            appliedGlassTintAlpha = nil
            hostContent(in: self)
            backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
            layer.borderWidth = Constants.borderWidth
            layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor
            layer.shadowOpacity = 0
            applyCornerRadius(Constants.cornerRadius)
            heightConstraint?.constant = Constants.height
            label.font = UIFont.daxButton()
            applyHorizontalPadding(leading: Constants.iconLeadingPadding,
                                   iconToLabel: Constants.iconLabelSpacing,
                                   trailing: Constants.trailingPadding)
        case .glass:
            // The glass is the background: nothing of ours behind it. It adapts to the page it sits over,
            // darkened by its own tint so the pills read against light page content.
            backgroundColor = .clear
            // No border: it lives on this layer, so it can't scale with the glass's interactive
            // expansion and would sit inside the enlarged pill on touch.
            layer.borderWidth = 0
            let glass = installGlassBackgroundIfNeeded()
            applyGlassTint(on: glass)
            hostContent(in: glass.contentView)
            applyGlassShadow()
            applyCornerRadius(Constants.height / 2)
            heightConstraint?.constant = Constants.height
            label.font = .systemFont(ofSize: Constants.glassFontSize, weight: .medium)
            applyHorizontalPadding(leading: Constants.glassIconLeadingPadding,
                                   iconToLabel: Constants.glassIconLabelSpacing,
                                   trailing: Constants.glassTrailingPadding)
        }
    }

    func applyHorizontalPadding(leading: CGFloat, iconToLabel: CGFloat, trailing: CGFloat) {
        iconLeadingConstraint?.constant = leading
        iconLabelSpacingConstraint?.constant = iconToLabel
        labelTrailingConstraint?.constant = -trailing
    }

    func applyCornerRadius(_ radius: CGFloat) {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        highlightOverlay.layer.cornerRadius = radius
        if #unavailable(iOS 26.0) {
            glassBackgroundView?.layer.cornerRadius = radius
        }
    }

    /// Shaped via `cornerConfiguration` — a layer `cornerRadius` leaves the effect rectangular behind it.
    @discardableResult
    func installGlassBackgroundIfNeeded() -> UIVisualEffectView {
        if let glassBackgroundView { return glassBackgroundView }

        let effectView = UIVisualEffectView()
        if #available(iOS 26.0, *) {
            effectView.cornerConfiguration = .capsule()
        } else {
            effectView.effect = UIBlurEffect(style: .systemThinMaterial)
            effectView.clipsToBounds = true
            effectView.layer.cornerCurve = .continuous
        }

        effectView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(effectView, at: 0)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        glassBackgroundView = effectView
        return effectView
    }

    /// `UIGlassEffect`'s tint is fixed at init, so a theme flip needs a fresh effect. Skipped when the
    /// tint hasn't moved — assigning `effect` rebuilds the backdrop chain.
    func applyGlassTint(on glass: UIVisualEffectView) {
        guard #available(iOS 26.0, *) else { return }

        let alpha = glassTintAlpha
        guard appliedGlassTintAlpha != alpha else { return }
        appliedGlassTintAlpha = alpha

        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        effect.tintColor = UIColor.black.withAlphaComponent(alpha)
        glass.effect = effect
    }

    /// Dark glass carries more tint: it sits over darker content, so the same value would barely read.
    var glassTintAlpha: CGFloat {
        traitCollection.userInterfaceStyle == .dark
            ? Constants.glassTintAlphaDark
            : Constants.glassTintAlphaLight
    }

    func applyGlassShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Constants.glassShadowOpacity
        layer.shadowRadius = Constants.glassShadowRadius
        layer.shadowOffset = CGSize(width: 0, height: Constants.glassShadowOffsetY)
        layer.masksToBounds = false
    }

    func setupUI() {
        layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor

        // The icon and label are parented by `hostContent`, which moves them between this view and the
        // glass effect's content view.
        addSubview(highlightOverlay)

        setupConstraints()
        applyBackgroundStyle()
        setupAccessibility()
    }

    func setupConstraints() {
        let height = heightAnchor.constraint(equalToConstant: Constants.height)
        heightConstraint = height

        NSLayoutConstraint.activate([
            height,

            iconView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            highlightOverlay.topAnchor.constraint(equalTo: topAnchor),
            highlightOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            highlightOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlightOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    /// Glass only applies its legibility treatment to content in its `contentView`; the translucent
    /// style has no effect view, so there the chip hosts its own.
    func hostContent(in host: UIView) {
        guard iconView.superview !== host else { return }

        contentConstraints.forEach { $0.isActive = false }
        host.addSubview(iconView)
        host.addSubview(label)
        // The overlay tints the content, so it has to stay above whatever was just re-parented.
        bringSubviewToFront(highlightOverlay)

        let iconLeading = iconView.leadingAnchor.constraint(equalTo: host.leadingAnchor,
                                                           constant: iconLeadingConstraint?.constant ?? Constants.iconLeadingPadding)
        let iconLabelSpacing = label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor,
                                                             constant: iconLabelSpacingConstraint?.constant ?? Constants.iconLabelSpacing)
        let labelTrailing = label.trailingAnchor.constraint(equalTo: host.trailingAnchor,
                                                           constant: labelTrailingConstraint?.constant ?? -Constants.trailingPadding)
        iconLeadingConstraint = iconLeading
        iconLabelSpacingConstraint = iconLabelSpacing
        labelTrailingConstraint = labelTrailing

        contentConstraints = [
            iconLeading,
            iconView.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            iconLabelSpacing,
            label.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            labelTrailing,
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }

    func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    func setupGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
    }

    @objc func handleTap() {
        onTap?()
    }
}

// MARK: - Touch Handling

extension AIChatQuickActionChipView {

    /// Without an explicit path the shadow follows the layer's opaque content, which for the clear
    /// glass chip renders as a rectangular halo instead of hugging the capsule.
    public override func layoutSubviews() {
        super.layoutSubviews()
        guard backgroundStyle == .glass else { return }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // Interactive glass supplies its own touch response, so a second overlay would double it.
        guard backgroundStyle != .glass else { return }
        highlightOverlay.isHidden = false
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        highlightOverlay.isHidden = true
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        highlightOverlay.isHidden = true
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyBackgroundStyle()
        }
    }
}
#endif
