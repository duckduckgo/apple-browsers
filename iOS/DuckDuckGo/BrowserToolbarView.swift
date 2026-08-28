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

enum FloatingOmnibarSwipeDirection: Equatable {
    case left
    case right
}

enum FloatingOmnibarSwipeGeometry {

    static let fieldSpacing: CGFloat = 32

    static func visibleRects(bounds: CGRect,
                             progress: CGFloat,
                             direction: FloatingOmnibarSwipeDirection) -> (outgoing: CGRect, incoming: CGRect) {
        let progress = max(0, min(progress, 1))
        let spacingRampIn = max(0, min((progress - 0.2) / 0.1, 1))
        let spacingRampOut = 1 - max(0, min((progress - 0.9) / 0.1, 1))
        let spacing = fieldSpacing * min(spacingRampIn, spacingRampOut)
        let outgoingWidth = max(bounds.width * (1 - progress) - spacing / 2, 0)
        let incomingWidth = max(bounds.width * progress - spacing / 2, 0)

        switch direction {
        case .left:
            return (
                CGRect(x: 0, y: 0, width: outgoingWidth, height: bounds.height),
                CGRect(x: bounds.width - incomingWidth, y: 0, width: incomingWidth, height: bounds.height)
            )
        case .right:
            return (
                CGRect(x: bounds.width - outgoingWidth, y: 0, width: outgoingWidth, height: bounds.height),
                CGRect(x: 0, y: 0, width: incomingWidth, height: bounds.height)
            )
        }
    }

    static func trailingTranslationX(bounds: CGRect, visibleRect: CGRect) -> CGFloat {
        visibleRect.maxX - bounds.maxX
    }

    static func leadingTranslationX(bounds: CGRect, visibleRect: CGRect) -> CGFloat {
        visibleRect.minX - bounds.minX
    }
}

struct FloatingOmnibarSwipeMorph {

    let incomingBarAlpha: CGFloat
    let outgoingTextAlpha: CGFloat
    let incomingTextAlpha: CGFloat

    static func values(progress: CGFloat) -> FloatingOmnibarSwipeMorph {
        let progress = max(0, min(progress, 1))
        let incomingBarAlpha = normalized(progress, from: 0.2, to: 0.32)
        let outgoingTextAlpha = 1 - normalized(progress, from: 0.2, to: 0.5)
        let incomingTextAlpha = normalized(progress, from: 0.35, to: 0.55)

        return FloatingOmnibarSwipeMorph(
            incomingBarAlpha: incomingBarAlpha,
            outgoingTextAlpha: outgoingTextAlpha,
            incomingTextAlpha: incomingTextAlpha
        )
    }

    private static func normalized(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        max(0, min((value - start) / (end - start), 1))
    }
}

/// Custom bottom toolbar container (replaces `UIToolbar`) with widened touch targets matching legacy `HitTestingToolbar` behavior.
final class BrowserToolbarView: UIView {

    static let extendedHitWidth: CGFloat = 45
    static let floatingButtonsHeight: CGFloat = 62
    /// Button row height when the address field is hosted in the bottom floating chrome.
    static let floatingEmbeddedButtonsHeight: CGFloat = 44
    static let buttonRowCollapseScaleAmount: CGFloat = 0.2
    static let buttonRowCollapseTranslationY: CGFloat = 8

    /// Non-floating (legacy) buttons-only bar height, matching the original `UIToolbar` on `main`.
    /// The floating style uses the taller `buttonsHeight`.
    static let legacyButtonsHeight: CGFloat = 49

    static let omnibarHorizontalInset: CGFloat = -8
    private static let horizontalEdgePadding: CGFloat = 8
    /// Extra horizontal inset for the button row in the non-floating (legacy) style so the outer
    /// buttons sit where the production `UIToolbar` placed them. Tuned to match production's
    /// end-button centres; the floating style keeps the tighter `horizontalEdgePadding`.
    private static let legacyButtonRowHorizontalPadding: CGFloat = 20
    /// Inset for the combined (bottom) floating button row so the outer buttons' centres line up
    /// with the embedded omnibar's leading/trailing icons. Separate from `horizontalEdgePadding`
    /// so tuning it doesn't shift the omnibar field.
    static let floatingEmbeddedButtonRowHorizontalPadding: CGFloat = 16
    /// Inner side inset of the standalone (top address bar) floating toolbar.
    static let floatingStandaloneButtonRowHorizontalPadding: CGFloat = 16
    // This is only used in floating UI
    private static let floatingUICornerRadius: CGFloat = 40

    static let floatingEmbeddedHorizontalInset: CGFloat = 16
    static let floatingEmbeddedConcentricInset: CGFloat = 20
    /// Outer side inset of the standalone top-address-bar toolbar.
    static let floatingStandaloneHorizontalInset: CGFloat = 24
    /// Extra inset of the custom glass inside the concentric layout-guide pin. Used by the
    /// standalone (split, top-address-bar) pill so it matches iOS 26 `UIToolbar` glass padding.
    /// Combined bottom chrome instead keeps its own equal rest-state inset on every edge.
    static let floatingConcentricGlassInset: CGFloat = 20
    private static let floatingConcentricGlassInsets = UIEdgeInsets(top: 0, left: floatingConcentricGlassInset, bottom: 0, right: floatingConcentricGlassInset)
    private static let floatingEmbeddedBarOuterInsets = UIEdgeInsets(top: 0, left: floatingEmbeddedHorizontalInset, bottom: 0, right: floatingEmbeddedHorizontalInset)
    private static let floatingStandaloneBarOuterInsets = UIEdgeInsets(top: 0, left: floatingStandaloneHorizontalInset, bottom: 0, right: floatingStandaloneHorizontalInset)
    private static let legacyBarOuterInsets = UIEdgeInsets.zero

    /// In the floating style the toolbar is laid out against the safe-area bottom (so the chrome
    /// hide/show math stays valid), but the capsule should float this close to the physical device
    /// bottom. The glass is shifted down into the home-indicator region by the difference.
    static let floatingEmbeddedBottomMargin: CGFloat = 16
    static let floatingStandaloneBottomMargin: CGFloat = 21

    static func floatingOuterHorizontalInset(for addressBarPosition: AddressBarPosition) -> CGFloat {
        if #available(iOS 26.0, *), addressBarPosition.isBottom {
            return floatingEmbeddedConcentricInset
        }
        return addressBarPosition.isBottom ? floatingEmbeddedHorizontalInset : floatingStandaloneHorizontalInset
    }

    /// Extra inset inside the corner-adapted guide so combined bottom chrome sits
    /// `floatingEmbeddedConcentricInset` from the physical screen edges. Zero when the guide is
    /// already larger (landscape Dynamic Island) so the glass never leaves the toolbar.
    static func embeddedRestStateInnerInset(guideInset: CGFloat) -> CGFloat {
        max(0, floatingEmbeddedConcentricInset - max(0, guideInset))
    }

    static func floatingBottomMargin(for addressBarPosition: AddressBarPosition) -> CGFloat {
        if #available(iOS 26.0, *), addressBarPosition.isBottom {
            return floatingEmbeddedConcentricInset
        }
        return addressBarPosition.isBottom ? floatingEmbeddedBottomMargin : floatingStandaloneBottomMargin
    }

    /// Inner padding of the combined bottom floating chrome (address field + buttons). The standalone
    /// floating toolbar used in top-address-bar mode keeps the original 2pt padding.
    private static let floatingEmbeddedVerticalContentPadding: CGFloat = 12
    private static let floatingEmbeddedOmnibarToButtonsSpacing: CGFloat = 12
    private static let defaultVerticalContentPadding: CGFloat = 2
    private static let defaultOmnibarToButtonsSpacing: CGFloat = 2
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
    private var materialInterfaceStyle: UIUserInterfaceStyle?

    private let buttonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalCentering
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: BrowserToolbarView.horizontalEdgePadding, bottom: 0, right: BrowserToolbarView.horizontalEdgePadding)
        stack.clipsToBounds = true
        stack.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.distribution = .fill
        stack.spacing = defaultOmnibarToButtonsSpacing
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
    
    private lazy var omnibarHeightConstraint: NSLayoutConstraint = {
        let constraint = omnibarContainer.heightAnchor.constraint(equalToConstant: 0)
        omnibarContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        omnibarContainer.setContentHuggingPriority(.required, for: .vertical)
        return constraint
    }()
    /// Hosts the glass so the home-indicator shift can be applied to a plain view. Transforming
    /// `UIVisualEffectView` itself makes Liquid Glass interpolate independently of `contentView`.
    private let chromeContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    /// Icons sit here as a sibling of the glass, not inside `UIVisualEffectView.contentView`. Nested
    /// glass interpolates on a different clock from `contentView` descendants when the pill moves.
    private let chromeContentHost: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        return view
    }()
    private lazy var buttonsHeightConstraint = chromeContainer.heightAnchor.constraint(equalToConstant: Self.legacyButtonsHeight)
    private lazy var buttonRowHeightConstraint: NSLayoutConstraint = {
        let constraint = buttonStack.heightAnchor.constraint(equalToConstant: 0)
        constraint.isActive = false
        return constraint
    }()
    private lazy var expandedContentHeightConstraint = expandedContentContainer.heightAnchor.constraint(equalToConstant: 0)
    private lazy var materialBackgroundTopConstraint = chromeContainer.topAnchor.constraint(equalTo: topAnchor)
    private lazy var contentStackTopConstraint = contentStack.topAnchor.constraint(equalTo: chromeContentHost.topAnchor, constant: Self.defaultVerticalContentPadding)
    private lazy var contentStackBottomConstraint = contentStack.bottomAnchor.constraint(equalTo: chromeContentHost.bottomAnchor, constant: -Self.defaultVerticalContentPadding)
    private var materialBackgroundLeadingConstraint: NSLayoutConstraint!
    private var materialBackgroundTrailingConstraint: NSLayoutConstraint!
    private var materialBackgroundBottomConstraint: NSLayoutConstraint!
    private var contentStackLeadingConstraint: NSLayoutConstraint!
    private var contentStackTrailingConstraint: NSLayoutConstraint!
    private weak var hostedOmnibarView: UIView?
    private weak var swipeIncomingOmnibarView: UIView?
    private var swipeIncomingOmnibarConstraints: [NSLayoutConstraint] = []
    private var isOmnibarMorphing = false
    private let outgoingSwipeMask = CAShapeLayer()
    private let incomingSwipeMask = CAShapeLayer()
    private weak var hostedExpandedContentView: UIView?
    private var isFloatingStyleEnabled = false
    /// How far the glass capsule is shifted down from its safe-area-anchored layout position so it
    /// floats near the device bottom (see `floatingBottomMargin`). Kept in sync with the host's
    /// safe-area inset in `layoutSubviews`; also widens the hit-test region.
    private var floatingBottomOffset: CGFloat = 0
    /// Extra translation applied while the split (top address bar) pill hides. The layout slot stays
    /// put so we can slide a plain container instead of moving `UIVisualEffectView` via Auto Layout.
    private var standaloneHideProgress: CGFloat = 0
    /// 0 = button row fully in layout, 1 = button row and field-to-buttons gap collapsed out of layout
    /// so the address field keeps its height while the chrome shrinks around it.
    private var buttonRowCollapseProgress: CGFloat = 0
    /// The tab switcher reuses this bar purely for button-position parity with the browser, but
    /// paints its own backdrop — so in the non-floating style its own background must stay clear.
    private var isLegacyBackgroundTransparent = false
    private var toolbarButtonViews: [UIView] = []
    
    private var hasEmbeddedOmnibar: Bool {
        omnibarHeightConstraint.constant > 0
    }

    private var hasExpandedContent: Bool {
        expandedContentHeightConstraint.constant > 0
    }

    private var usesStandaloneFloatingChrome: Bool {
        isFloatingStyleEnabled && !hasEmbeddedOmnibar
    }

    private var usesCombinedBottomChromeGeometry: Bool {
        isFloatingStyleEnabled && (hasEmbeddedOmnibar || isOmnibarMorphing)
    }

    private var currentBarOuterInsets: UIEdgeInsets {
        guard isFloatingStyleEnabled else { return Self.legacyBarOuterInsets }
        if #available(iOS 26.0, *) {
            return usesCombinedBottomChromeGeometry ? embeddedRestStateOuterInsets : Self.floatingConcentricGlassInsets
        }
        return usesEmbeddedBottomChromeMetrics ? Self.floatingEmbeddedBarOuterInsets : Self.floatingStandaloneBarOuterInsets
    }

    /// Horizontal compensation for the combined bottom chrome. Its host is pinned to the
    /// corner-adapted guide, so this keeps the glass at the same physical inset on every edge
    /// unless the guide already exceeds that inset.
    @available(iOS 26.0, *)
    private var embeddedRestStateOuterInsets: UIEdgeInsets {
        guard let host = superview, host.bounds.width > 0 else {
            return UIEdgeInsets(
                top: 0,
                left: Self.floatingEmbeddedConcentricInset,
                bottom: 0,
                right: Self.floatingEmbeddedConcentricInset)
        }
        let guide = host.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
        let guideInset = max(0, guide.layoutFrame.minX)
        let inner = Self.embeddedRestStateInnerInset(guideInset: guideInset)
        return UIEdgeInsets(top: 0, left: inner, bottom: 0, right: inner)
    }

    private var currentButtonRowHorizontalPadding: CGFloat {
        guard isFloatingStyleEnabled else { return Self.legacyButtonRowHorizontalPadding }
        return usesEmbeddedBottomChromeMetrics
            ? Self.floatingEmbeddedButtonRowHorizontalPadding
            : Self.floatingStandaloneButtonRowHorizontalPadding
    }

    private var currentContentStackHorizontalInset: CGFloat {
        usesStandaloneFloatingChrome ? 0 : Self.horizontalEdgePadding
    }

    /// Buttons-only bar height for the current style. Floating standalone (top address bar) keeps the
    /// original 62pt row; the non-floating style matches the original `UIToolbar` height.
    private var buttonsOnlyHeight: CGFloat {
        isFloatingStyleEnabled ? Self.floatingButtonsHeight : Self.legacyButtonsHeight
    }

    private var usesEmbeddedBottomChromeMetrics: Bool {
        isFloatingStyleEnabled && hasEmbeddedOmnibar
    }

    private var currentVerticalContentPadding: CGFloat {
        usesEmbeddedBottomChromeMetrics ? Self.floatingEmbeddedVerticalContentPadding : Self.defaultVerticalContentPadding
    }

    private var currentOmnibarToButtonsSpacing: CGFloat {
        usesEmbeddedBottomChromeMetrics ? Self.floatingEmbeddedOmnibarToButtonsSpacing : Self.defaultOmnibarToButtonsSpacing
    }

    static func totalHeight(withOmnibarHeight omnibarHeight: CGFloat, isFloating: Bool) -> CGFloat {
        guard omnibarHeight > 0 else {
            return isFloating ? floatingButtonsHeight : legacyButtonsHeight
        }
        if isFloating {
            return (floatingEmbeddedVerticalContentPadding * 2)
                + floatingEmbeddedButtonsHeight
                + omnibarHeight
                + floatingEmbeddedOmnibarToButtonsSpacing
        }
        return (defaultVerticalContentPadding * 2) + legacyButtonsHeight + omnibarHeight + defaultOmnibarToButtonsSpacing
    }

    static func singleRowHeight(withOmnibarHeight omnibarHeight: CGFloat) -> CGFloat {
        (floatingEmbeddedVerticalContentPadding * 2) + omnibarHeight
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        addSubview(chromeContainer)
        chromeContainer.addSubview(materialBackgroundView)
        chromeContainer.addSubview(chromeContentHost)
        chromeContentHost.addSubview(contentStack)
        contentStack.addArrangedSubview(expandedContentContainer)
        contentStack.addArrangedSubview(omnibarContainer)
        contentStack.addArrangedSubview(buttonStack)

        chromeContainer.clipsToBounds = false
        materialBackgroundView.clipsToBounds = false
        expandedContentContainer.isHidden = true

        materialBackgroundView.contentView.layer.cornerCurve = .continuous

        materialBackgroundView.contentView.clipsToBounds = true
        materialBackgroundView.layer.shadowColor = UIColor.black.cgColor
        materialBackgroundView.layer.shadowOpacity = 0.12
        materialBackgroundView.layer.shadowRadius = 10
        materialBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 4)

        materialBackgroundLeadingConstraint = chromeContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.legacyBarOuterInsets.left)
        materialBackgroundTrailingConstraint = chromeContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.legacyBarOuterInsets.right)
        materialBackgroundBottomConstraint = chromeContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.legacyBarOuterInsets.bottom)
        contentStackLeadingConstraint = contentStack.leadingAnchor.constraint(equalTo: chromeContentHost.leadingAnchor, constant: Self.horizontalEdgePadding)
        contentStackTrailingConstraint = contentStack.trailingAnchor.constraint(equalTo: chromeContentHost.trailingAnchor, constant: -Self.horizontalEdgePadding)

        NSLayoutConstraint.activate([
            materialBackgroundView.topAnchor.constraint(equalTo: chromeContainer.topAnchor),
            materialBackgroundView.leadingAnchor.constraint(equalTo: chromeContainer.leadingAnchor),
            materialBackgroundView.trailingAnchor.constraint(equalTo: chromeContainer.trailingAnchor),
            materialBackgroundView.bottomAnchor.constraint(equalTo: chromeContainer.bottomAnchor),
            chromeContentHost.topAnchor.constraint(equalTo: chromeContainer.topAnchor),
            chromeContentHost.leadingAnchor.constraint(equalTo: chromeContainer.leadingAnchor),
            chromeContentHost.trailingAnchor.constraint(equalTo: chromeContainer.trailingAnchor),
            chromeContentHost.bottomAnchor.constraint(equalTo: chromeContainer.bottomAnchor),
            materialBackgroundLeadingConstraint,
            materialBackgroundTrailingConstraint,
            materialBackgroundTopConstraint,
            materialBackgroundBottomConstraint,
            buttonsHeightConstraint,
            contentStackLeadingConstraint,
            contentStackTrailingConstraint,
            contentStackTopConstraint,
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
        toolbarButtonViews
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
        toolbarButtonViews = views
        rebuildButtonRow()
    }

    private func rebuildButtonRow() {
        buttonStack.arrangedSubviews.forEach {
            buttonStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        buttonStack.distribution = .equalCentering
        toolbarButtonViews.forEach { view in
            view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            buttonStack.addArrangedSubview(view)
        }
    }

    private func applyContentStackMetrics() {
        contentStackTopConstraint.constant = currentVerticalContentPadding
        if !hasExpandedContent {
            contentStackBottomConstraint.constant = -currentVerticalContentPadding
        }
        let collapse = usesEmbeddedBottomChromeMetrics ? buttonRowCollapseProgress.clamped(to: 0...1) : 0
        contentStack.spacing = currentOmnibarToButtonsSpacing * (1 - collapse)
        if usesEmbeddedBottomChromeMetrics {
            buttonRowHeightConstraint.constant = Self.floatingEmbeddedButtonsHeight * (1 - collapse)
            buttonRowHeightConstraint.isActive = true
        } else {
            buttonRowHeightConstraint.isActive = false
        }
        applyHorizontalChromeMetrics()
    }

    private func applyHorizontalChromeMetrics() {
        let insets = currentBarOuterInsets
        materialBackgroundLeadingConstraint.constant = insets.left
        materialBackgroundTrailingConstraint.constant = -insets.right
        if !hasExpandedContent {
            materialBackgroundTopConstraint.constant = insets.top
        }
        materialBackgroundBottomConstraint.constant = -insets.bottom
        contentStackLeadingConstraint.constant = currentContentStackHorizontalInset
        contentStackTrailingConstraint.constant = -currentContentStackHorizontalInset
        let buttonRowPadding = currentButtonRowHorizontalPadding
        buttonStack.layoutMargins = UIEdgeInsets(top: 0, left: buttonRowPadding, bottom: 0, right: buttonRowPadding)
    }

    func setOmnibarView(_ view: UIView?, height: CGFloat) {
        endOmnibarSwipe()
        hostedOmnibarView?.removeFromSuperview()
        hostedOmnibarView = nil
        isOmnibarMorphing = false
        buttonRowCollapseProgress = 0
        
        guard let view else {
            applyOmnibarDetachmentPose()
            return
        }
        
        omnibarHeightConstraint.constant = height
        buttonsHeightConstraint.constant = Self.totalHeight(withOmnibarHeight: height, isFloating: isFloatingStyleEnabled)
        applyContentStackMetrics()
        rebuildButtonRow()
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
        scheduleHostedOmnibarMaterialRefresh()
    }

    func prepareForOmnibarDetachment() {
        endOmnibarSwipe()
        hostedOmnibarView?.removeFromSuperview()
        hostedOmnibarView = nil
        isOmnibarMorphing = true
        updateCornerStyle()
    }

    func applyOmnibarDetachmentPose() {
        buttonRowCollapseProgress = 0
        omnibarHeightConstraint.constant = 0
        buttonsHeightConstraint.constant = buttonsOnlyHeight
        applyContentStackMetrics()
        rebuildButtonRow()
        updateCornerStyle()
    }

    func prepareForOmnibarAttachment(height: CGFloat) {
        guard isFloatingStyleEnabled, hostedOmnibarView == nil else { return }
        isOmnibarMorphing = true
        buttonRowCollapseProgress = 0
        omnibarHeightConstraint.constant = height
        buttonsHeightConstraint.constant = Self.totalHeight(withOmnibarHeight: height, isFloating: true)
        applyContentStackMetrics()
        rebuildButtonRow()
        updateCornerStyle()
    }

    func refreshMaterialAppearance(interfaceStyle: UIUserInterfaceStyle) {
        guard isFloatingStyleEnabled else { return }
        materialInterfaceStyle = interfaceStyle
        UIView.performWithoutAnimation {
            materialBackgroundView.overrideUserInterfaceStyle = interfaceStyle
            materialBackgroundView.effect = nil
            materialBackgroundView.effect = materialEffect()
            materialBackgroundView.layoutIfNeeded()
        }
        scheduleHostedOmnibarMaterialRefresh()
    }

    private func scheduleHostedOmnibarMaterialRefresh() {
        guard isFloatingStyleEnabled else { return }
        let omnibarView = hostedOmnibarView as? DefaultOmniBarView
        let interfaceStyle = materialInterfaceStyle
        DispatchQueue.main.async { [weak self, weak omnibarView] in
            guard let self, let omnibarView, hostedOmnibarView === omnibarView else { return }
            omnibarView.refreshMaterialAppearance(interfaceStyle: interfaceStyle)
        }
    }

    func isHostingOmnibarView(_ view: UIView) -> Bool {
        hostedOmnibarView === view
    }

    func beginOmnibarSwipe(with incomingView: UIView) {
        endOmnibarSwipe()
        guard hostedOmnibarView != nil else { return }

        incomingView.translatesAutoresizingMaskIntoConstraints = false
        incomingView.isUserInteractionEnabled = false
        (incomingView as? DefaultOmniBarView)?.safeAreaManagedByContainer = false
        omnibarContainer.addSubview(incomingView)
        swipeIncomingOmnibarView = incomingView
        swipeIncomingOmnibarConstraints = [
            incomingView.leadingAnchor.constraint(equalTo: omnibarContainer.leadingAnchor, constant: Self.omnibarHorizontalInset),
            incomingView.trailingAnchor.constraint(equalTo: omnibarContainer.trailingAnchor, constant: -Self.omnibarHorizontalInset),
            incomingView.topAnchor.constraint(equalTo: omnibarContainer.topAnchor),
            incomingView.bottomAnchor.constraint(equalTo: omnibarContainer.bottomAnchor),
        ]
        NSLayoutConstraint.activate(swipeIncomingOmnibarConstraints)
        layoutIfNeeded()
        updateOmnibarSwipe(progress: 0, direction: .left)
    }

    func updateOmnibarSwipe(progress: CGFloat, direction: FloatingOmnibarSwipeDirection) {
        guard let outgoingView = hostedOmnibarView, let incomingView = swipeIncomingOmnibarView else { return }

        let outgoingMaskTarget = swipeMaskTarget(for: outgoingView)
        let incomingMaskTarget = swipeMaskTarget(for: incomingView)
        let outgoingRect = FloatingOmnibarSwipeGeometry.visibleRects(
            bounds: outgoingMaskTarget.bounds,
            progress: progress,
            direction: direction
        ).outgoing
        let incomingRect = FloatingOmnibarSwipeGeometry.visibleRects(
            bounds: incomingMaskTarget.bounds,
            progress: progress,
            direction: direction
        ).incoming

        let outgoingCorners: UIRectCorner
        let incomingCorners: UIRectCorner
        switch direction {
        case .left:
            outgoingCorners = [.topRight, .bottomRight]
            incomingCorners = [.topLeft, .bottomLeft]
        case .right:
            outgoingCorners = [.topLeft, .bottomLeft]
            incomingCorners = [.topRight, .bottomRight]
        }

        applySwipeMask(
            outgoingSwipeMask,
            to: outgoingMaskTarget,
            visibleRect: outgoingRect,
            roundedCorners: outgoingCorners
        )
        applySwipeMask(
            incomingSwipeMask,
            to: incomingMaskTarget,
            visibleRect: incomingRect,
            roundedCorners: incomingCorners
        )

        let morph = FloatingOmnibarSwipeMorph.values(progress: progress)
        incomingView.alpha = morph.incomingBarAlpha
        if let outgoingTextField = (outgoingView as? DefaultOmniBarView)?.textField {
            outgoingTextField.alpha = morph.outgoingTextAlpha
            let translationX: CGFloat
            if direction == .left {
                translationX = FloatingOmnibarSwipeGeometry.trailingTranslationX(
                    bounds: outgoingMaskTarget.bounds,
                    visibleRect: outgoingRect
                )
            } else {
                translationX = FloatingOmnibarSwipeGeometry.leadingTranslationX(
                    bounds: outgoingMaskTarget.bounds,
                    visibleRect: outgoingRect
                )
            }
            outgoingTextField.transform = CGAffineTransform(
                translationX: translationX,
                y: 0
            )
        }
        if let incomingTextField = (incomingView as? DefaultOmniBarView)?.textField {
            incomingTextField.alpha = morph.incomingTextAlpha
            let translationX: CGFloat
            if direction == .left {
                translationX = FloatingOmnibarSwipeGeometry.leadingTranslationX(
                    bounds: incomingMaskTarget.bounds,
                    visibleRect: incomingRect
                )
            } else {
                translationX = FloatingOmnibarSwipeGeometry.trailingTranslationX(
                    bounds: incomingMaskTarget.bounds,
                    visibleRect: incomingRect
                )
            }
            incomingTextField.transform = CGAffineTransform(
                translationX: translationX,
                y: 0
            )
        }
    }

    func endOmnibarSwipe() {
        if let outgoingTextField = (hostedOmnibarView as? DefaultOmniBarView)?.textField {
            outgoingTextField.alpha = 1
            outgoingTextField.transform = .identity
        }
        if let incomingTextField = (swipeIncomingOmnibarView as? DefaultOmniBarView)?.textField {
            incomingTextField.alpha = 1
            incomingTextField.transform = .identity
        }
        swipeIncomingOmnibarView?.alpha = 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let hostedOmnibarView {
            swipeMaskTarget(for: hostedOmnibarView).layer.mask = nil
        }
        if let swipeIncomingOmnibarView {
            swipeMaskTarget(for: swipeIncomingOmnibarView).layer.mask = nil
        }
        CATransaction.commit()
        NSLayoutConstraint.deactivate(swipeIncomingOmnibarConstraints)
        swipeIncomingOmnibarConstraints = []
        swipeIncomingOmnibarView?.removeFromSuperview()
        swipeIncomingOmnibarView = nil
    }

    private func applySwipeMask(_ mask: CAShapeLayer,
                                to view: UIView,
                                visibleRect: CGRect,
                                roundedCorners: UIRectCorner) {
        let cornerRadius = min(visibleRect.width, visibleRect.height) / 2
        let path = UIBezierPath(
            roundedRect: visibleRect,
            byRoundingCorners: roundedCorners,
            cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
        ).cgPath

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = view.bounds
        mask.path = path
        if view.layer.mask !== mask {
            view.layer.mask = mask
        }
        CATransaction.commit()
    }

    private func swipeMaskTarget(for view: UIView) -> UIView {
        (view as? DefaultOmniBarView)?.searchContainer ?? view
    }

    func setExpandedContentView(_ view: UIView?, height: CGFloat, animated: Bool) {
        guard let view else {
            let existingExpandedView = hostedExpandedContentView
            let collapseLayout = {
                self.expandedContentHeightConstraint.constant = 0
                self.contentStack.setCustomSpacing(0, after: self.expandedContentContainer)
                self.contentStackBottomConstraint.constant = -self.currentVerticalContentPadding
                self.materialBackgroundTopConstraint.constant = self.currentBarOuterInsets.top
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
        contentStackBottomConstraint.constant = -(currentVerticalContentPadding + Self.expandedButtonsBottomPadding)
        materialBackgroundTopConstraint.constant = currentBarOuterInsets.top - expandedContainerHeight - Self.expandedContentToOmnibarSpacing

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
        applyHorizontalChromeMetrics()
        super.layoutSubviews()
        updateFloatingBottomOffset()
        updateCornerStyle()
    }

    var floatingBottomMargin: CGFloat {
        if #available(iOS 26.0, *), usesCombinedBottomChromeGeometry {
            return Self.floatingEmbeddedConcentricInset
        }
        return hasEmbeddedOmnibar ? Self.floatingEmbeddedBottomMargin : Self.floatingStandaloneBottomMargin
    }

    var visibleCapsuleRect: CGRect {
        guard isFloatingStyleEnabled else { return bounds }
        let shadowSpill = materialBackgroundView.layer.shadowRadius + materialBackgroundView.layer.shadowOffset.height
        return bounds.union(chromeContainer.frame.insetBy(dx: -shadowSpill, dy: -shadowSpill))
    }

    /// Floating style only; returns `.zero` otherwise.
    func restingCapsuleFrame(in view: UIView) -> CGRect {
        guard isFloatingStyleEnabled else { return .zero }
        let bounds = view.bounds
        let height = hasEmbeddedOmnibar
            ? Self.singleRowHeight(withOmnibarHeight: omnibarHeightConstraint.constant)
            : buttonsHeightConstraint.constant

        let left: CGFloat
        let right: CGFloat
        let bottom: CGFloat
        if #available(iOS 26.0, *) {
            if usesCombinedBottomChromeGeometry {
                let horizontalGuide = view.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
                let leftGuideInset = max(0, horizontalGuide.layoutFrame.minX)
                let rightGuideInset = max(0, bounds.maxX - horizontalGuide.layoutFrame.maxX)
                let inner = Self.embeddedRestStateInnerInset(guideInset: leftGuideInset)
                left = leftGuideInset + inner
                right = rightGuideInset + inner
                bottom = bounds.maxY - Self.floatingEmbeddedConcentricInset
            } else {
                let horizontalGuide = view.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
                let verticalGuide = view.layoutGuide(for: .safeArea(cornerAdaptation: .vertical))
                let glassInset = currentBarOuterInsets.left
                left = max(0, horizontalGuide.layoutFrame.minX) + glassInset
                right = max(0, bounds.maxX - horizontalGuide.layoutFrame.maxX) + glassInset
                bottom = verticalGuide.layoutFrame.maxY
            }
        } else {
            let insets = currentBarOuterInsets
            left = insets.left
            right = insets.right
            let safeBottom = view.safeAreaInsets.bottom
            let offset = max(0, safeBottom - floatingBottomMargin)
            bottom = bounds.maxY - safeBottom + offset
        }

        let width = bounds.width - left - right
        return CGRect(x: bounds.minX + left, y: bottom - height, width: width, height: height)
    }

    @discardableResult
    func setButtonRowCollapseProgress(_ collapseProgress: CGFloat, reduceMotion: Bool) -> CGFloat {
        let fullHeight = Self.totalHeight(withOmnibarHeight: omnibarHeightConstraint.constant, isFloating: isFloatingStyleEnabled)

        guard isFloatingStyleEnabled, hasEmbeddedOmnibar, !hasExpandedContent, !reduceMotion else {
            buttonRowCollapseProgress = 0
            buttonStack.alpha = 1
            buttonStack.transform = .identity
            buttonsHeightConstraint.constant = fullHeight
            applyContentStackMetrics()
            return fullHeight
        }

        let progress = collapseProgress.clamped(to: 0...1)
        buttonRowCollapseProgress = progress
        applyContentStackMetrics()
        buttonStack.alpha = 1 - progress
        let scale = 1 - Self.buttonRowCollapseScaleAmount * progress
        buttonStack.transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: 0, y: Self.buttonRowCollapseTranslationY * progress))

        let singleRowHeight = Self.singleRowHeight(withOmnibarHeight: omnibarHeightConstraint.constant)
        let height = fullHeight - (fullHeight - singleRowHeight) * progress
        buttonsHeightConstraint.constant = height
        updateCornerStyle()
        return height
    }

    func setStandaloneCollapseProgress(_ progress: CGFloat, reduceMotion: Bool) {
        standaloneHideProgress = reduceMotion ? 0 : progress.clamped(to: 0...1)
        applyMaterialBackgroundTransform()
    }

    private var standaloneHideTranslation: CGFloat {
        let slideDistance = bounds.height + (superview?.safeAreaInsets.bottom ?? 0)
        return slideDistance * standaloneHideProgress
    }

    private func applyMaterialBackgroundTransform() {
        chromeContainer.transform = CGAffineTransform(translationX: 0, y: floatingBottomOffset + standaloneHideTranslation)
    }

    /// On iOS 26 the host pins this bar to the concentric vertical guide. Split (standalone) chrome
    /// stays there. Combined bottom chrome is shifted down to keep the same physical inset on every
    /// edge. Below iOS 26 the layout slot sits on the safe area and the glass is shifted down toward
    /// the device bottom, leaving `floatingBottomMargin`.
    private func updateFloatingBottomOffset() {
        let target: CGFloat
        if #available(iOS 26.0, *), isFloatingStyleEnabled {
            if usesCombinedBottomChromeGeometry, let host = superview, host.bounds.height > 0 {
                let verticalGuide = host.layoutGuide(for: .safeArea(cornerAdaptation: .vertical))
                let guideBottomGap = max(0, host.bounds.maxY - verticalGuide.layoutFrame.maxY)
                target = max(0, guideBottomGap - Self.floatingEmbeddedConcentricInset)
            } else {
                target = 0
            }
        } else {
            let hostBottomInset = superview?.safeAreaInsets.bottom ?? 0
            target = isFloatingStyleEnabled ? hostBottomInset - floatingBottomMargin : 0
        }
        guard target != floatingBottomOffset else { return }
        floatingBottomOffset = target
        applyMaterialBackgroundTransform()
    }

    private func updateCornerStyle() {
        guard isFloatingStyleEnabled else {
            materialBackgroundView.contentView.layer.cornerRadius = 0
            chromeContentHost.layer.cornerRadius = 0
            return
        }

        let usesRestStateCorners = isOmnibarMorphing || hasEmbeddedOmnibar || hasExpandedContent

        if #available(iOS 26, *) {
            if usesRestStateCorners {
                let configuration = UICornerConfiguration.corners(
                    radius: .containerConcentric(minimum: Self.floatingUICornerRadius))
                materialBackgroundView.cornerConfiguration = configuration
                chromeContentHost.cornerConfiguration = configuration
            } else {
                materialBackgroundView.cornerConfiguration = .capsule()
                chromeContentHost.cornerConfiguration = .capsule()
            }
            return
        }

        let radius = usesRestStateCorners
            ? Self.floatingUICornerRadius
            : max(chromeContentHost.bounds.height, materialBackgroundView.bounds.height) / 2
        chromeContentHost.layer.cornerRadius = radius
        materialBackgroundView.contentView.layer.cornerRadius = radius
    }

    private func applyCurrentStyle(animated: Bool) {
        let legacyBackgroundColor: UIColor = isLegacyBackgroundTransparent ? .clear : ThemeManager.shared.currentTheme.barBackgroundColor
        let updates = {
            self.materialBackgroundView.layer.shadowOpacity = self.isFloatingStyleEnabled ? 0.12 : 0
            self.materialBackgroundView.effect = self.isFloatingStyleEnabled ? self.materialEffect() : nil
            self.materialBackgroundView.backgroundColor = self.isFloatingStyleEnabled ? .clear : legacyBackgroundColor
            self.materialBackgroundView.contentView.backgroundColor = self.isFloatingStyleEnabled ? .clear : legacyBackgroundColor
            self.applyContentStackMetrics()
            self.rebuildButtonRow()
            // Keep the buttons-only height in sync with the style (49 legacy / 62 floating standalone).
            // The embedded-omnibar height is floating-only and owned by `setOmnibarView`, so leave it.
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

    /// Rebuilds the glass so it re-resolves against whatever is now behind the capsule. Swapping the
    /// surface under the bar (web page <-> new tab page) doesn't invalidate the effect on its own, so
    /// a light page's material survives into a dark NTP and the capsule reads lighter than its backdrop.
    func refreshMaterialBackdrop() {
        guard isFloatingStyleEnabled else { return }
        UIView.performWithoutAnimation {
            materialBackgroundView.effect = nil
            materialBackgroundView.effect = materialEffect()
            materialBackgroundView.layoutIfNeeded()
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
        let interactiveRect = bounds.offsetBy(dx: 0, dy: floatingBottomOffset + standaloneHideTranslation)
        if interactiveRect.contains(point) {
            return true
        }

        guard hasExpandedContent else { return false }
        let expandedRect = interactiveRect.insetBy(dx: 0, dy: -expandedContentHeightConstraint.constant)
        return expandedRect.contains(point)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            scheduleHostedOmnibarMaterialRefresh()
        }
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

        for subview in toolbarButtonViews {
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
