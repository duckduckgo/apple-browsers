//
//  BrowserToolbarView.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import UIKit

/// Custom bottom toolbar container (replaces `UIToolbar`) with widened touch targets matching legacy `HitTestingToolbar` behavior.
final class BrowserToolbarView: UIView {

    static let extendedHitWidth: CGFloat = 45
    static let floatingButtonsHeight: CGFloat = 62

    /// Non-floating (legacy) buttons-only bar height, matching the original `UIToolbar` on `main`.
    /// The floating style uses the taller `buttonsHeight`.
    static let legacyButtonsHeight: CGFloat = 49

    static let omnibarHorizontalInset: CGFloat = -8
    private static let horizontalEdgePadding: CGFloat = 8
    /// Extra horizontal inset for the button row in the non-floating (legacy) style so the outer
    /// buttons sit where the production `UIToolbar` placed them. Tuned to match production's
    /// end-button centres; the floating style keeps the tighter `horizontalEdgePadding`.
    private static let legacyButtonRowHorizontalPadding: CGFloat = 20
    /// Inset for the floating button row so the outer buttons' centres line up with the embedded
    /// omnibar's leading/trailing icons (loupe/shield ↔ back, AI chat ↔ menu). Separate from
    /// `horizontalEdgePadding` so tuning it doesn't shift the omnibar field.
    private static let floatingButtonRowHorizontalPadding: CGFloat = 16

    // This is only used in floating UI
    private static let floatingUICornerRadius: CGFloat = 40

    private static let floatingBarOuterInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
    private static let legacyBarOuterInsets = UIEdgeInsets.zero

    /// In the floating style the toolbar is laid out against the safe-area bottom (so the chrome
    /// hide/show math stays valid), but the capsule should float this close to the physical device
    /// bottom. The glass is shifted down into the home-indicator region by the difference.
    private static let floatingBottomMarginWithEmbedded: CGFloat = 16
    private static let floatingBottomMarginStandalone: CGFloat = 21

    private static let verticalContentPadding: CGFloat = 2
    private static let omnibarToButtonsSpacing: CGFloat = 2
    private static let expandedContentToOmnibarSpacing: CGFloat = 8
    private static let expandedButtonsBottomPadding: CGFloat = 10
    private static let expandedContentTopPadding: CGFloat = 8
    private static let expandedContentBottomPadding: CGFloat = 4
    private static let expandAnimationDuration: TimeInterval = 0.36
    private static let collapseAnimationDuration: TimeInterval = 0.24
    private static let contentFadeDuration: TimeInterval = 0.18

    private let materialBackgroundView: UIVisualEffectView = {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            let view = UIVisualEffectView(effect: effect)
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } else {
            let effect = UIBlurEffect(style: .systemThinMaterial)
            let view = UIVisualEffectView(effect: effect)
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }
    }()

    private let buttonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        // Equal center-to-center spacing (not equal gaps) so a wider button — e.g. the tab-count
        // control — doesn't shift the other columns. With equal-width end buttons this keeps the
        // centre (fire) button at the bar's midpoint, matching the tab switcher's bottom bar so the
        // buttons stay put across the tab-switcher transition.
        stack.distribution = .equalCentering
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: BrowserToolbarView.horizontalEdgePadding, bottom: 0, right: BrowserToolbarView.horizontalEdgePadding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.distribution = .fill
        stack.spacing = omnibarToButtonsSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let omnibarContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let expandedContentContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var omnibarHeightConstraint = omnibarContainer.heightAnchor.constraint(equalToConstant: 0)
    private lazy var buttonsHeightConstraint = materialBackgroundView.heightAnchor.constraint(equalToConstant: Self.legacyButtonsHeight)
    private lazy var expandedContentHeightConstraint = expandedContentContainer.heightAnchor.constraint(equalToConstant: 0)
    private lazy var materialBackgroundTopConstraint = materialBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: Self.barOuterInsets.top)
    private lazy var contentStackBottomConstraint = contentStack.bottomAnchor.constraint(equalTo: materialBackgroundView.contentView.bottomAnchor, constant: -Self.verticalContentPadding)
    private var materialBackgroundLeadingConstraint: NSLayoutConstraint!
    private var materialBackgroundTrailingConstraint: NSLayoutConstraint!
    private var materialBackgroundBottomConstraint: NSLayoutConstraint!
    private weak var hostedOmnibarView: UIView?
    private weak var hostedExpandedContentView: UIView?
    private var isFloatingStyleEnabled = false
    /// How far the glass capsule is shifted down from its safe-area-anchored layout position so it
    /// floats near the device bottom (see `floatingBottomMargin`). Kept in sync with the host's
    /// safe-area inset in `layoutSubviews`; also widens the hit-test region.
    private var floatingBottomOffset: CGFloat = 0
    /// The tab switcher reuses this bar purely for button-position parity with the browser, but
    /// paints its own backdrop — so in the non-floating style its own background must stay clear.
    private var isLegacyBackgroundTransparent = false
    private static var barOuterInsets: UIEdgeInsets {
        floatingBarOuterInsets
    }
    
    private var hasEmbeddedOmnibar: Bool {
        omnibarHeightConstraint.constant > 0
    }

    private var hasExpandedContent: Bool {
        expandedContentHeightConstraint.constant > 0
    }

    /// Buttons-only bar height for the current style. Floating uses the taller `buttonsHeight`; the
    /// non-floating style matches the original `UIToolbar` height so flag-off chrome is unchanged.
    private var buttonsOnlyHeight: CGFloat {
        isFloatingStyleEnabled ? Self.floatingButtonsHeight : Self.legacyButtonsHeight
    }

    static func totalHeight(withOmnibarHeight omnibarHeight: CGFloat, isFloating: Bool) -> CGFloat {
        let targetHeight = isFloating ? floatingButtonsHeight : legacyButtonsHeight
        guard omnibarHeight > 0 else {
            return targetHeight
        }
        return (verticalContentPadding * 2) + targetHeight + omnibarHeight + omnibarToButtonsSpacing
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        addSubview(materialBackgroundView)
        materialBackgroundView.contentView.addSubview(contentStack)
        contentStack.addArrangedSubview(expandedContentContainer)
        contentStack.addArrangedSubview(omnibarContainer)
        contentStack.addArrangedSubview(buttonStack)

        materialBackgroundView.clipsToBounds = false
        expandedContentContainer.isHidden = true

        materialBackgroundView.contentView.layer.cornerCurve = .continuous

        materialBackgroundView.contentView.clipsToBounds = true
        materialBackgroundView.layer.shadowColor = UIColor.black.cgColor
        materialBackgroundView.layer.shadowOpacity = 0.12
        materialBackgroundView.layer.shadowRadius = 10
        materialBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 4)

        materialBackgroundLeadingConstraint = materialBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.legacyBarOuterInsets.left)
        materialBackgroundTrailingConstraint = materialBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.legacyBarOuterInsets.right)
        materialBackgroundBottomConstraint = materialBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.legacyBarOuterInsets.bottom)

        NSLayoutConstraint.activate([
            materialBackgroundLeadingConstraint,
            materialBackgroundTrailingConstraint,
            materialBackgroundTopConstraint,
            materialBackgroundBottomConstraint,
            buttonsHeightConstraint,
            contentStack.leadingAnchor.constraint(equalTo: materialBackgroundView.contentView.leadingAnchor, constant: Self.horizontalEdgePadding),
            contentStack.trailingAnchor.constraint(equalTo: materialBackgroundView.contentView.trailingAnchor, constant: -Self.horizontalEdgePadding),
            contentStack.topAnchor.constraint(equalTo: materialBackgroundView.contentView.topAnchor, constant: Self.verticalContentPadding),
            contentStackBottomConstraint,
            expandedContentHeightConstraint,
            omnibarHeightConstraint,
        ])
        
        applyCurrentStyle(animated: false)
        updateCornerStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var arrangedToolbarButtonViews: [UIView] {
        buttonStack.arrangedSubviews
    }

    func setFloatingStyleEnabled(_ enabled: Bool, animated: Bool = false) {
        guard isFloatingStyleEnabled != enabled else { return }
        isFloatingStyleEnabled = enabled
        applyCurrentStyle(animated: animated)
    }

    /// Keeps the bar's own background clear in the non-floating style (used by the tab switcher,
    /// which provides its own backdrop). No-op for the floating style, which is always clear.
    func setLegacyBackgroundTransparent(_ transparent: Bool) {
        guard isLegacyBackgroundTransparent != transparent else { return }
        isLegacyBackgroundTransparent = transparent
        applyCurrentStyle(animated: false)
    }

    func setToolbarButtons(_ views: [UIView]) {
        buttonStack.arrangedSubviews.forEach {
            buttonStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for view in views {
            buttonStack.addArrangedSubview(view)
        }
    }
    
    func setOmnibarView(_ view: UIView?, height: CGFloat) {
        hostedOmnibarView?.removeFromSuperview()
        hostedOmnibarView = nil
        
        guard let view else {
            omnibarHeightConstraint.constant = 0
            buttonsHeightConstraint.constant = buttonsOnlyHeight
            updateCornerStyle()
            return
        }
        
        omnibarHeightConstraint.constant = height
        buttonsHeightConstraint.constant = Self.totalHeight(withOmnibarHeight: height, isFloating: isFloatingStyleEnabled)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        (view as? DefaultOmniBarView)?.safeAreaManagedByContainer = false
        omnibarContainer.addSubview(view)
        hostedOmnibarView = view
        
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: omnibarContainer.leadingAnchor, constant: Self.omnibarHorizontalInset),
            view.trailingAnchor.constraint(equalTo: omnibarContainer.trailingAnchor, constant: -Self.omnibarHorizontalInset),
            view.topAnchor.constraint(equalTo: omnibarContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: omnibarContainer.bottomAnchor),
        ])
        
        updateCornerStyle()
    }

    func isHostingOmnibarView(_ view: UIView) -> Bool {
        hostedOmnibarView === view
    }

    func setExpandedContentView(_ view: UIView?, height: CGFloat, animated: Bool) {
        guard let view else {
            let existingExpandedView = hostedExpandedContentView
            let collapseLayout = {
                self.expandedContentHeightConstraint.constant = 0
                self.contentStack.setCustomSpacing(0, after: self.expandedContentContainer)
                self.contentStackBottomConstraint.constant = -Self.verticalContentPadding
                self.materialBackgroundTopConstraint.constant = Self.barOuterInsets.top
                self.layoutIfNeeded()
            }
            if animated {
                UIView.animate(withDuration: Self.contentFadeDuration, delay: 0, options: [.curveEaseInOut], animations: {
                    existingExpandedView?.alpha = 0
                    existingExpandedView?.transform = CGAffineTransform(translationX: 0, y: 8)
                }, completion: { _ in
                    UIView.animate(withDuration: Self.collapseAnimationDuration, delay: 0, options: [.curveEaseInOut], animations: collapseLayout, completion: { _ in
                        existingExpandedView?.removeFromSuperview()
                        self.hostedExpandedContentView = nil
                        self.expandedContentContainer.isHidden = true
                    })
                })
            } else {
                collapseLayout()
                existingExpandedView?.removeFromSuperview()
                hostedExpandedContentView = nil
                expandedContentContainer.isHidden = true
            }
            updateCornerStyle()
            return
        }

        hostedExpandedContentView?.removeFromSuperview()
        hostedExpandedContentView = nil

        let expandedContainerHeight = height + Self.expandedContentTopPadding + Self.expandedContentBottomPadding
        expandedContentHeightConstraint.constant = expandedContainerHeight
        expandedContentContainer.isHidden = false
        contentStack.setCustomSpacing(Self.expandedContentToOmnibarSpacing, after: expandedContentContainer)
        contentStackBottomConstraint.constant = -(Self.verticalContentPadding + Self.expandedButtonsBottomPadding)
        materialBackgroundTopConstraint.constant = Self.barOuterInsets.top - expandedContainerHeight - Self.expandedContentToOmnibarSpacing

        view.translatesAutoresizingMaskIntoConstraints = false
        expandedContentContainer.addSubview(view)
        hostedExpandedContentView = view

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: expandedContentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: expandedContentContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: expandedContentContainer.topAnchor, constant: Self.expandedContentTopPadding),
            view.bottomAnchor.constraint(equalTo: expandedContentContainer.bottomAnchor, constant: -Self.expandedContentBottomPadding)
        ])

        let expandLayout = { self.layoutIfNeeded() }
        if animated {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 6)
            UIView.animate(withDuration: Self.expandAnimationDuration, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2, options: [.curveEaseInOut], animations: {
                expandLayout()
            }, completion: { _ in
                UIView.animate(withDuration: Self.contentFadeDuration, delay: 0, options: [.curveEaseOut], animations: {
                    view.alpha = 1
                    view.transform = .identity
                })
            })
        } else {
            expandLayout()
        }

        updateCornerStyle()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateFloatingBottomOffset()
        updateCornerStyle()
    }

    var floatingBottomMargin: CGFloat {
        hasEmbeddedOmnibar ? Self.floatingBottomMarginWithEmbedded : Self.floatingBottomMarginStandalone
    }

    /// Floating style only; returns `.zero` otherwise.
    func restingCapsuleFrame(in view: UIView) -> CGRect {
        guard isFloatingStyleEnabled else { return .zero }
        let bounds = view.bounds
        let safeBottom = view.safeAreaInsets.bottom
        let insets = Self.floatingBarOuterInsets
        let width = bounds.width - insets.left - insets.right
        let height = buttonsHeightConstraint.constant
        let offset = max(0, safeBottom - floatingBottomMargin)
        let bottom = bounds.maxY - safeBottom + offset
        return CGRect(x: bounds.minX + insets.left, y: bottom - height, width: width, height: height)
    }
    
    /// Shifts the glass capsule down from its safe-area-anchored position toward the device bottom,
    /// leaving `floatingBottomMargin`. Done as a transform (not a constraint change) so it doesn't
    /// disturb the toolbar's layout slot or the runtime chrome hide/show constant logic.
    private func updateFloatingBottomOffset() {
        let hostBottomInset = superview?.safeAreaInsets.bottom ?? 0
        let target = isFloatingStyleEnabled ? max(0, hostBottomInset - floatingBottomMargin) : 0
        guard target != floatingBottomOffset else { return }
        floatingBottomOffset = target
        materialBackgroundView.transform = CGAffineTransform(translationX: 0, y: target)
    }

    private func updateCornerStyle() {
        guard isFloatingStyleEnabled else {
            materialBackgroundView.contentView.layer.cornerRadius = 0
            return
        }

        if #available(iOS 26, *) {
            materialBackgroundView.cornerConfiguration = hasEmbeddedOmnibar || hasExpandedContent
                ? .corners(radius: UICornerRadius.containerConcentric(minimum: Self.floatingUICornerRadius))
                : .capsule()
            return
        }

        materialBackgroundView.contentView.layer.cornerRadius = hasEmbeddedOmnibar || hasExpandedContent
            ? Self.floatingUICornerRadius
            : materialBackgroundView.contentView.bounds.height / 2
    }

    private func applyCurrentStyle(animated: Bool) {
        let insets = isFloatingStyleEnabled ? Self.floatingBarOuterInsets : Self.legacyBarOuterInsets
        let legacyBackgroundColor: UIColor = isLegacyBackgroundTransparent ? .clear : ThemeManager.shared.currentTheme.barBackgroundColor
        let updates = {
            self.materialBackgroundLeadingConstraint.constant = insets.left
            self.materialBackgroundTrailingConstraint.constant = -insets.right
            self.materialBackgroundTopConstraint.constant = insets.top
            self.materialBackgroundBottomConstraint.constant = -insets.bottom
            self.materialBackgroundView.layer.shadowOpacity = self.isFloatingStyleEnabled ? 0.12 : 0
            self.materialBackgroundView.effect = self.isFloatingStyleEnabled ? self.materialEffect() : nil
            self.materialBackgroundView.backgroundColor = self.isFloatingStyleEnabled ? .clear : legacyBackgroundColor
            self.materialBackgroundView.contentView.backgroundColor = self.isFloatingStyleEnabled ? .clear : legacyBackgroundColor
            let buttonRowPadding = self.isFloatingStyleEnabled ? Self.floatingButtonRowHorizontalPadding : Self.legacyButtonRowHorizontalPadding
            self.buttonStack.layoutMargins = UIEdgeInsets(top: 0, left: buttonRowPadding, bottom: 0, right: buttonRowPadding)
            // Keep the buttons-only height in sync with the style (49 legacy / 56 floating). The
            // embedded-omnibar height is floating-only and owned by `setOmnibarView`, so leave it.
            if !self.hasEmbeddedOmnibar {
                self.buttonsHeightConstraint.constant = self.buttonsOnlyHeight
            }
            self.updateCornerStyle()
            self.layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: updates)
        } else {
            updates()
        }
    }

    private func materialEffect() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            UIGlassEffect(style: .regular)
        } else {
            UIBlurEffect(style: .systemThinMaterial)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, alpha >= 0.01, isUserInteractionEnabled else { return false }

        // The glass is shifted down by `floatingBottomOffset`, so the interactive region is the
        // bounds offset by the same amount (this also lets the now-empty strip above the capsule
        // pass touches through to the content behind it).
        let interactiveRect = bounds.offsetBy(dx: 0, dy: floatingBottomOffset)
        if interactiveRect.contains(point) {
            return true
        }

        guard hasExpandedContent else { return false }
        let expandedRect = interactiveRect.insetBy(dx: 0, dy: -expandedContentHeightConstraint.constant)
        return expandedRect.contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Mirror UIKit's standard hit-test preconditions so hidden/disabled toolbar states
        // (e.g. minimal chrome) don't leak taps to child controls.
        guard !isHidden, alpha >= 0.01, isUserInteractionEnabled else { return nil }

        if let omnibarView = hostedOmnibarView {
            let location = convert(point, to: omnibarView)
            if let hit = omnibarView.hitTest(location, with: event) {
                return hit
            }
        }

        if hasExpandedContent, let expandedContentView = hostedExpandedContentView {
            let location = convert(point, to: expandedContentView)
            if let hit = expandedContentView.hitTest(location, with: event) {
                return hit
            }
        }

        for subview in buttonStack.arrangedSubviews {
            let location = convert(point, to: subview)
            if let hit = subview.hitTest(location, with: event) {
                return hit
            }
            let extra = max(0, Self.extendedHitWidth - subview.bounds.width)
            if location.x >= -extra && location.x <= Self.extendedHitWidth
                && location.y > 0 && location.y <= subview.bounds.height {
                return subview
            }
        }
        return super.hitTest(point, with: event)
    }
}
