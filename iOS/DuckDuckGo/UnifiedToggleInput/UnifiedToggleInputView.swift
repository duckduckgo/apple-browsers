//
//  UnifiedToggleInputView.swift
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

import AIChat
import Combine
import DesignResourcesKit
import UIComponents
import UIKit

// MARK: - Delegate Protocol

/// Delegate protocol for handling interactions with the unified toggle input composite view.
protocol UnifiedToggleInputViewDelegate: AnyObject {
    func unifiedToggleInputViewDidTapWhileCollapsed(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidSubmitText(_ view: UnifiedToggleInputView, text: String, mode: TextEntryMode)
    func unifiedToggleInputViewDidChangeText(_ view: UnifiedToggleInputView, text: String)
    func unifiedToggleInputViewDidChangeMode(_ view: UnifiedToggleInputView, mode: TextEntryMode)
    func unifiedToggleInputViewDidTapSearchGoTo(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidClearSelectedTool(_ view: UnifiedToggleInputView)
}

// MARK: - Card Position

/// Controls which corners are rounded and which direction shadows cast when expanded.
enum UnifiedToggleInputCardPosition {
    /// Bottom corners rounded, shadow downward (input at top of screen).
    case top
    /// Top corners rounded, shadow upward (input at bottom of screen, default).
    case bottom
}

// MARK: - View

/// Composite input bar wrapping `SwitchBarTextEntryView` (text core), `UnifiedToggleInputToggleView`,
/// and `UnifiedToggleInputToolbarView`. Using `SwitchBarTextEntryView` directly ensures improvements
/// to the omnibar text input are automatically inherited here.
///
/// Supports collapsed (single-line) and expanded (text + tools toolbar) layout states.
final class UnifiedToggleInputView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let collapsedCardHeight: CGFloat = 44
        static let cardHorizontalMargin: CGFloat = 16
        static let cardVerticalMargin: CGFloat = 8
        static let cardHorizontalMarginBottom: CGFloat = 12
        static let cardVerticalMarginBottom: CGFloat = 8
        static let cardCornerRadiusExpanded: CGFloat = 24
        static let cardCornerRadiusCollapsed: CGFloat = 16
        static let toggleTopPadding: CGFloat = 8
        static let toggleBottomPadding: CGFloat = 4
        static let toggleHeight: CGFloat = 40
        static let toggleHorizontalPadding: CGFloat = 8
        static let animationDuration: TimeInterval = 0.25
        static let toggleDisabledSearchTopPadding: CGFloat = 10
        static let toolbarHeight: CGFloat = 56
        static let expandedBorderWidth: CGFloat = 0.5
        static let inlineDismissSize: CGFloat = 40
        static let inlineDismissTrailingPadding: CGFloat = 8
        static let toggleInlineDismissSpacing: CGFloat = 6
        /// Carves room for the floating X at `.top` when the toggle is disabled.
        static let cardTrailingMarginWithFloatingDismiss: CGFloat = 68

        /// Trailing constant for the toggle when the inline dismiss button shares the top row.
        static var toggleTrailingWithInlineDismiss: CGFloat {
            -(inlineDismissTrailingPadding + inlineDismissSize + toggleInlineDismissSpacing)
        }

        static let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result == self ? nil : result
    }

    // MARK: - Properties

    weak var delegate: UnifiedToggleInputViewDelegate?

    var cardPosition: UnifiedToggleInputCardPosition = .bottom {
        didSet {
            guard cardPosition != oldValue else { return }
            refreshInlineDismissPresentation()
            guard isExpanded else { return }
            cardView.layer.maskedCorners = Constants.allCorners
        }
    }

    var text: String {
        get { handler.currentText }
        set { textEntryView.setQueryText(newValue) }
    }

    var inputMode: TextEntryMode {
        handler.currentToggleState
    }

    private(set) var isExpanded = false

    var isToolbarSubmitHidden: Bool = false {
        didSet { toolsToolbar.isSubmitButtonHidden = isToolbarSubmitHidden }
    }

    var isToolbarAIVoiceChatActive: Bool = false {
        didSet { toolsToolbar.isAIVoiceChatActive = isToolbarAIVoiceChatActive }
    }

    var isGenerating: Bool = false {
        didSet { toolsToolbar.isGenerating = isGenerating }
    }

    var modelName: String {
        get { toolsToolbar.modelName }
        set { toolsToolbar.modelName = newValue }
    }

    var modelPickerMenu: UIMenu? {
        get { toolsToolbar.modelPickerMenu }
        set { toolsToolbar.modelPickerMenu = newValue }
    }

    var toolsMenu: UIMenu? {
        get { toolsToolbar.toolsMenu }
        set { toolsToolbar.toolsMenu = newValue }
    }

    var reasoningPickerMenu: UIMenu? {
        get { toolsToolbar.reasoningPickerMenu }
        set { toolsToolbar.reasoningPickerMenu = newValue }
    }

    var isModelChipHidden: Bool {
        get { toolsToolbar.isModelChipHidden }
        set { toolsToolbar.isModelChipHidden = newValue }
    }

    var selectedTool: AIChatRAGTool? {
        get { toolsToolbar.selectedTool }
        set { toolsToolbar.selectedTool = newValue }
    }

    var selectedReasoningMode: AIChatReasoningMode? {
        get { toolsToolbar.selectedReasoningMode }
        set { toolsToolbar.selectedReasoningMode = newValue }
    }

    var isToolsButtonHidden: Bool {
        get { toolsToolbar.isToolsButtonHidden }
        set { toolsToolbar.isToolsButtonHidden = newValue }
    }

    var isReasoningButtonHidden: Bool {
        get { toolsToolbar.isReasoningButtonHidden }
        set { toolsToolbar.isReasoningButtonHidden = newValue }
    }

    /// Called inside animation blocks when a hierarchy-wide layout pass is needed
    /// so that sibling views (e.g. the content container) animate in sync.
    /// The owning view controller sets this.
    var onNeedsHierarchyLayout: (() -> Void)?
    var onAttachmentsLayoutDidChange: (() -> Void)?

    var isVoiceSearchAvailable = false {
        didSet { handler.isVoiceSearchEnabled = isVoiceSearchAvailable }
    }

    var usesOmnibarMargins: Bool = false
    private(set) var isToggleEnabled: Bool

    var modelSupportsImageAttachments: Bool = true {
        didSet {
            guard modelSupportsImageAttachments != oldValue else { return }
            updateAttachmentsStripLayout()
            layoutIfNeeded()
            onNeedsHierarchyLayout?()
            onAttachmentsLayoutDidChange?()
        }
    }

    var handlerIsTopBarPosition: Bool {
        get { handler.isTopBarPosition }
        set { handler.isTopBarPosition = newValue }
    }

    // MARK: - Attachment Callbacks

    var onAttachTapped: (() -> Void)?
    var onAttachmentRemoved: ((UUID) -> Void)?
    var onInlineDismissTapped: (() -> Void)?

    // MARK: - Attachment API

    var attachButtonView: UIView { toolsToolbar.imageButton }

    var isImageButtonHidden: Bool {
        get { toolsToolbar.isImageButtonHidden }
        set { toolsToolbar.isImageButtonHidden = newValue }
    }

    var isImageButtonEnabled: Bool {
        get { toolsToolbar.isImageButtonEnabled }
        set { toolsToolbar.isImageButtonEnabled = newValue }
    }

    var isAttachmentsFull: Bool {
        attachmentsStrip.isFull
    }

    var currentAttachments: [AIChatImageAttachment] {
        attachmentsStrip.attachments
    }

    func addAttachment(_ attachment: AIChatImageAttachment) {
        attachmentsStrip.addAttachment(attachment)
    }

    func removeAttachment(id: UUID) {
        attachmentsStrip.removeAttachment(id: id)
    }

    func removeAllAttachments() {
        attachmentsStrip.removeAllAttachments()
    }

    // MARK: - Components

    private let handler: UnifiedToggleInputHandler
    private let textEntryView: SwitchBarTextEntryView
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private let cardView = UIView()
    private let toggleView = UnifiedToggleInputToggleView()
    private lazy var inlineDismissButton: UIButton = Self.makeInlineDismissButton()
    private let attachmentsStrip = UnifiedToggleInputAttachmentsStripView()
    private let toolsToolbar = UnifiedToggleInputToolbarView()
    // MARK: - Shadow

    // Pinned to cardView via Auto Layout; CompositeShadowView forwards cornerRadius/backgroundColor to its shadow sub-layers.
    private let expandedShadowView: CompositeShadowView = {
        let view = CompositeShadowView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }()

    // MARK: - Dynamic Colors

    private var cardShadowColor: CGColor {
        UIColor(designSystemColor: .shadowSecondary).cgColor
    }

    private var expandedBorderColor: CGColor {
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12).cgColor
            : UIColor.black.withAlphaComponent(0.16).cgColor
    }

    private var expandedShadows: [CompositeShadowView.Shadow] {
        [
            .init(color: UIColor(designSystemColor: .shadowSecondary),
                  radius: 32,
                  offset: CGSize(width: 0, height: 8)),
            .init(color: UIColor(designSystemColor: .shadowTertiary),
                  radius: 16,
                  offset: CGSize(width: 0, height: 2)),
        ]
    }

    private func cardBackgroundColor(isFireTab: Bool) -> UIColor {
        UIColor(singleUseColor: isFireTab ? .fireModeCardBackground : .unifiedToggleInputCardBackground)
    }

    // MARK: - Constraints

    private var cardTopConstraint: NSLayoutConstraint!
    private var cardLeadingConstraint: NSLayoutConstraint!
    private var cardTrailingConstraint: NSLayoutConstraint!
    private var cardBottomConstraint: NSLayoutConstraint!
    private var cardCollapsedHeightConstraint: NSLayoutConstraint!
    private var toggleTopConstraint: NSLayoutConstraint!
    private var toggleTrailingConstraint: NSLayoutConstraint!
    private var toggleHeightConstraint: NSLayoutConstraint!
    private var inlineDismissHeightConstraint: NSLayoutConstraint!
    private var inputTopConstraint: NSLayoutConstraint!
    private var toolbarBottomConstraint: NSLayoutConstraint!
    private var attachmentsStripHeightConstraint: NSLayoutConstraint!
    private var toolbarHeightConstraint: NSLayoutConstraint!

    // MARK: - Initialization

    init(handler: UnifiedToggleInputHandler, isToggleEnabled: Bool = true) {
        self.handler = handler
        self.isToggleEnabled = isToggleEnabled
        self.textEntryView = SwitchBarTextEntryView(handler: handler)
        super.init(frame: .zero)
        setupUI()
        setupSubscriptions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard isExpanded else { return }
        // Runs inside UIView.animate via layoutIfNeeded so the shadow corners animate with cardView.
        expandedShadowView.layer.cornerRadius = cardView.layer.cornerRadius
        expandedShadowView.layer.maskedCorners = cardView.layer.maskedCorners
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            cardView.layer.shadowColor = cardShadowColor
            if isExpanded {
                cardView.layer.borderColor = expandedBorderColor
            }
        }
    }

    // MARK: - Fire Mode

    func refreshFireMode(fireMode: Bool) {
        applyFireModeAppearance(isFireTab: fireMode)
        textEntryView.refreshFireMode(fireMode: fireMode)
        toolsToolbar.refreshFireMode(fireMode: fireMode)
    }

    private func applyFireModeAppearance(isFireTab: Bool) {
        let background = cardBackgroundColor(isFireTab: isFireTab)
        cardView.backgroundColor = background
        // Shadow silhouette is an opaque fill covered by cardView, so both must share the same background.
        expandedShadowView.backgroundColor = background
        // cardView keeps the OS trait so `fireModeCardBackground` picks its light variant in light OS; content subviews force `.dark` so their dynamic colors resolve against the dark surface.
        let style: UIUserInterfaceStyle = isFireTab ? .dark : .unspecified
        // `toolsToolbar` manages its own subtree's trait so the accent submit button keeps OS trait.
        [toggleView, textEntryView, attachmentsStrip, inlineDismissButton].forEach {
            $0.overrideUserInterfaceStyle = style
        }
    }

    // MARK: - First Responder

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textEntryView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        return textEntryView.resignFirstResponder()
    }

    override var isFirstResponder: Bool {
        return textEntryView.isFirstResponder
    }

    // MARK: - Public Methods

    func selectAllText() {
        textEntryView.selectAllText()
    }

    func updateToggleEnabled(_ enabled: Bool) {
        guard enabled != isToggleEnabled else { return }
        isToggleEnabled = enabled
        if isExpanded {
            setExpanded(false, animated: false)
            setExpanded(true, animated: false)
        }
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool) {
        if handler.currentToggleState != mode {
            handler.setToggleState(mode)
        }
        if isToggleEnabled {
            toggleView.setMode(mode, animated: animated)
        }
        updateToolbarVisibility(for: mode, animated: animated)
        updateToggleDisabledSearchPadding(for: mode)
    }

    private func updateToggleDisabledSearchPadding(for mode: TextEntryMode) {
        guard isExpanded else { return }
        
        if isToggleEnabled {
            inputTopConstraint.constant = Constants.toggleBottomPadding
            toolbarBottomConstraint.constant = 0
        } else {
            let usePadding = mode == .search && cardPosition == .bottom
            let padding = usePadding ? Constants.toggleDisabledSearchTopPadding : 0
            inputTopConstraint.constant = padding
            toolbarBottomConstraint.constant = -padding
        }
    }

    func setExpanded(_ expanded: Bool, showToggle: Bool = true, animated: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        handler.isExpanded = expanded

        let effectiveToggleEnabled = isToggleEnabled && showToggle
        let toggleHeight: CGFloat = (expanded && effectiveToggleEnabled) ? Constants.toggleHeight : 0
        let showToolbar = expanded && effectiveToggleEnabled && toggleView.selectedMode == .aiChat
        // The card reserves space for the inline X whenever it's expanded at `.top`, so the
        // toggle's width is stable across the toggle-hidden transient. Visibility of the X
        // itself is gated on the toggle actually being shown, so the X can fade in together
        // with the toggle via `animateToggleReveal` rather than snapping in on activation.
        let reservesInlineDismissSpace = expanded && cardPosition == .top
        let showInlineDismiss = reservesInlineDismissSpace && effectiveToggleEnabled

        let hLeadingMargin: CGFloat
        let hTrailingMargin: CGFloat
        if expanded && cardPosition == .bottom && !usesOmnibarMargins {
            hLeadingMargin = Constants.cardHorizontalMarginBottom
            hTrailingMargin = Constants.cardHorizontalMarginBottom
        } else {
            hLeadingMargin = Constants.cardHorizontalMargin
            hTrailingMargin = cardTrailingMargin
        }

        let vMargin: CGFloat
        if expanded && !usesOmnibarMargins {
            vMargin = (cardPosition == .bottom) ? Constants.cardVerticalMarginBottom : Constants.cardVerticalMargin
        } else {
            vMargin = Constants.cardVerticalMargin
        }

        textEntryView.isExpandable = expanded

        expandedShadowView.isHidden = !expanded
        cardView.layer.shadowOpacity = expanded ? 0 : 1.0
        cardCollapsedHeightConstraint.constant = Constants.collapsedCardHeight
        cardCollapsedHeightConstraint.isActive = !expanded

        cardView.layer.maskedCorners = Constants.allCorners
        cardView.clipsToBounds = expanded && (usesOmnibarMargins || !isToggleEnabled)

        cardView.layer.borderWidth = showToolbar ? Constants.expandedBorderWidth : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor

        let expandedCornerRadius = effectiveToggleEnabled ? Constants.cardCornerRadiusExpanded : Constants.cardCornerRadiusCollapsed
        let changes = {
            self.cardView.layer.cornerRadius = expanded ? expandedCornerRadius : Constants.cardCornerRadiusCollapsed
            self.cardTopConstraint.constant = vMargin
            self.cardLeadingConstraint.constant = hLeadingMargin
            self.cardTrailingConstraint.constant = -hTrailingMargin
            self.cardBottomConstraint.constant = -vMargin
            self.toggleTopConstraint.constant = (expanded && effectiveToggleEnabled) ? Constants.toggleTopPadding : 0
            self.toggleHeightConstraint.constant = toggleHeight
            self.toggleTrailingConstraint.constant = reservesInlineDismissSpace
                ? Constants.toggleTrailingWithInlineDismiss
                : -Constants.toggleHorizontalPadding
            let toggleDisabledSearchPadding = expanded && !self.isToggleEnabled && showToggle && self.handler.currentToggleState == .search && self.cardPosition == .bottom
            self.inputTopConstraint.constant = expanded && effectiveToggleEnabled ? Constants.toggleBottomPadding : (toggleDisabledSearchPadding ? Constants.toggleDisabledSearchTopPadding : 0)
            self.toolbarBottomConstraint.constant = toggleDisabledSearchPadding ? -Constants.toggleDisabledSearchTopPadding : 0
            self.toggleView.alpha = (expanded && effectiveToggleEnabled) ? 1 : 0
            self.applyInlineDismissVisibility(showInlineDismiss)
            self.toolbarHeightConstraint.constant = showToolbar ? Constants.toolbarHeight : 0
            self.toolsToolbar.alpha = showToolbar ? 1 : 0
            self.updateAttachmentsStripLayout()
        }

        if animated {
            UIView.animate(
                withDuration: Constants.animationDuration,
                delay: 0,
                options: .curveEaseInOut,
                animations: {
                    changes()
                    self.layoutIfNeeded()
                },
                completion: { _ in
                }
            )
        } else {
            changes()
            layoutIfNeeded()
        }
    }

    func setExpandedWithToggleHidden(_ expanded: Bool) {
        setExpanded(expanded, showToggle: false, animated: false)
    }

    func animateToggleReveal(additionalAnimations: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        guard isExpanded, isToggleEnabled else {
            completion?()
            return
        }

        let showToolbar = toggleView.selectedMode == .aiChat

        UIView.animate(
            withDuration: Constants.animationDuration,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                self.cardView.layer.cornerRadius = Constants.cardCornerRadiusExpanded
                self.toggleTopConstraint.constant = Constants.toggleTopPadding
                self.toggleHeightConstraint.constant = Constants.toggleHeight
                self.toggleView.alpha = 1
                self.applyInlineDismissVisibility(self.cardPosition == .top)
                self.inputTopConstraint.constant = Constants.toggleBottomPadding
                self.cardView.layer.borderWidth = showToolbar ? Constants.expandedBorderWidth : 0
                self.cardView.layer.borderColor = showToolbar ? self.expandedBorderColor : UIColor.clear.cgColor
                self.toolbarHeightConstraint.constant = showToolbar ? Constants.toolbarHeight : 0
                self.toolsToolbar.alpha = showToolbar ? 1 : 0
                self.updateAttachmentsStripLayout()
                additionalAnimations?()
                self.layoutIfNeeded()
            },
            completion: { _ in
                completion?()
            }
        )
    }

    func animateToggleHide(additionalAnimations: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        guard isExpanded, isToggleEnabled else {
            completion?()
            return
        }

        UIView.animate(
            withDuration: Constants.animationDuration,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                self.cardView.layer.cornerRadius = Constants.cardCornerRadiusCollapsed
                self.toggleTopConstraint.constant = 0
                self.toggleHeightConstraint.constant = 0
                self.toggleView.alpha = 0
                self.applyInlineDismissVisibility(false)
                self.inputTopConstraint.constant = 0
                self.toolbarHeightConstraint.constant = 0
                self.toolsToolbar.alpha = 0
                additionalAnimations?()
                self.layoutIfNeeded()
            },
            completion: { _ in
                completion?()
            }
        )
    }

    func setInactiveCardAppearance(_ inactive: Bool) {
        guard isExpanded else { return }

        UIView.animate(withDuration: Constants.animationDuration, delay: 0, options: .curveEaseInOut) {
            if inactive {
                self.cardView.layer.maskedCorners = Constants.allCorners
                self.cardTopConstraint.constant = Constants.cardVerticalMargin
                self.cardLeadingConstraint.constant = Constants.cardHorizontalMargin
                self.cardTrailingConstraint.constant = -self.cardTrailingMargin
                self.cardBottomConstraint.constant = -Constants.cardVerticalMargin
                self.toolbarHeightConstraint.constant = 0
                self.toolsToolbar.alpha = 0
            } else {
                self.cardView.layer.maskedCorners = Constants.allCorners
                let leadingMargin: CGFloat
                let trailingMargin: CGFloat
                if !self.usesOmnibarMargins && self.cardPosition == .bottom {
                    leadingMargin = Constants.cardHorizontalMarginBottom
                    trailingMargin = Constants.cardHorizontalMarginBottom
                } else {
                    leadingMargin = Constants.cardHorizontalMargin
                    trailingMargin = self.cardTrailingMargin
                }
                let verticalMargin: CGFloat = (!self.usesOmnibarMargins && self.cardPosition == .bottom)
                    ? Constants.cardVerticalMarginBottom
                    : Constants.cardVerticalMargin
                let showToolbar = self.isToggleEnabled && self.toggleView.selectedMode == .aiChat
                self.cardTopConstraint.constant = verticalMargin
                self.cardLeadingConstraint.constant = leadingMargin
                self.cardTrailingConstraint.constant = -trailingMargin
                self.cardBottomConstraint.constant = -verticalMargin
                self.toolbarHeightConstraint.constant = showToolbar ? Constants.toolbarHeight : 0
                self.toolsToolbar.alpha = showToolbar ? 1 : 0
            }
            self.layoutIfNeeded()
            self.onNeedsHierarchyLayout?()
        }
    }

    // MARK: - Private

    /// Card trailing margin for the current state. Carves out room for the floating X in
    /// the content container when the toggle is disabled at `.top`; otherwise the card
    /// spans the full width to host the inline X.
    private var cardTrailingMargin: CGFloat {
        let needsFloatingDismissCarveOut = isExpanded && cardPosition == .top && !isToggleEnabled
        return needsFloatingDismissCarveOut
            ? Constants.cardTrailingMarginWithFloatingDismiss
            : Constants.cardHorizontalMargin
    }

    private func updateToolbarVisibility(for mode: TextEntryMode, animated: Bool) {
        guard isExpanded else { return }

        let showToolbar = mode == .aiChat
        toolbarHeightConstraint.constant = showToolbar ? Constants.toolbarHeight : 0
        cardView.layer.borderWidth = showToolbar ? Constants.expandedBorderWidth : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor
        updateAttachmentsStripLayout()

        guard animated else {
            toolsToolbar.alpha = showToolbar ? 1 : 0
            attachmentsStrip.alpha = attachmentsStripHeightConstraint.constant > 0 ? 1 : 0
            layoutIfNeeded()
            return
        }

        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.toolsToolbar.alpha = showToolbar ? 1 : 0
            self.attachmentsStrip.alpha = self.attachmentsStripHeightConstraint.constant > 0 ? 1 : 0
            self.layoutIfNeeded()
            self.onNeedsHierarchyLayout?()
        }
    }

    private func updateAttachmentsStripLayout() {
        let hasImages = !attachmentsStrip.attachments.isEmpty
        let showStrip = hasImages && isExpanded && handler.currentToggleState == .aiChat && modelSupportsImageAttachments
        attachmentsStripHeightConstraint.constant = showStrip ? UnifiedToggleInputAttachmentsStripView.Constants.stripHeight : 0
        attachmentsStrip.alpha = showStrip ? 1 : 0
    }
}

// MARK: - Inline Dismiss

private extension UnifiedToggleInputView {

    /// Updates layout and opacity so the toggle either reserves space for the inline dismiss
    /// button or expands to fill the card's top row. Safe to call outside of animation blocks.
    func refreshInlineDismissPresentation() {
        let shouldShow = isExpanded && cardPosition == .top && isToggleEnabled
        toggleTrailingConstraint.constant = shouldShow
            ? Constants.toggleTrailingWithInlineDismiss
            : -Constants.toggleHorizontalPadding
        applyInlineDismissVisibility(shouldShow)
        layoutIfNeeded()
    }

    /// Apply visibility without touching the toggle trailing constraint. Intended for use
    /// inside existing animation blocks so that opacity and layout animate together.
    /// The height collapses to 0 when hidden so the button grows/shrinks alongside the
    /// toggle's own height animation, mirroring its reveal behaviour.
    func applyInlineDismissVisibility(_ visible: Bool) {
        inlineDismissButton.alpha = visible ? 1 : 0
        inlineDismissButton.isUserInteractionEnabled = visible
        inlineDismissHeightConstraint.constant = visible ? Constants.inlineDismissSize : 0
    }

    @objc func handleInlineDismissTap() {
        onInlineDismissTapped?()
    }

    /// Flat, circular button styled to sit inside the card's top row. The floating dismiss
    /// button in the content container uses Liquid Glass on iOS 26, but inside the card the
    /// design calls for a flat control.
    static func makeInlineDismissButton() -> UIButton {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: "xmark")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        button.setImage(image, for: .normal)
        button.tintColor = UIColor(designSystemColor: .icons)
        button.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        button.layer.cornerRadius = Constants.inlineDismissSize / 2
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = UserText.keyCommandClose
        button.alpha = 0
        button.isUserInteractionEnabled = false
        return button
    }
}

// MARK: - Setup

private extension UnifiedToggleInputView {

    func setupUI() {
        clipsToBounds = false
        backgroundColor = .clear

        // backgroundColor is applied later by `applyFireModeAppearance` (called at the end of setupUI).
        expandedShadowView.shadows = expandedShadows
        addSubview(expandedShadowView)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = Constants.cardCornerRadiusCollapsed
        cardView.layer.shadowColor = cardShadowColor
        cardView.layer.shadowOpacity = 1.0
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12
        cardView.isUserInteractionEnabled = false
        addSubview(cardView)

        NSLayoutConstraint.activate([
            expandedShadowView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            expandedShadowView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            expandedShadowView.topAnchor.constraint(equalTo: cardView.topAnchor),
            expandedShadowView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])

        toggleView.translatesAutoresizingMaskIntoConstraints = false
        toggleView.alpha = 0
        toggleView.onModeChanged = { [weak self] mode in
            guard let self else { return }
            // Intent only — coordinator is the single writer of handler.currentToggleState.
            self.delegate?.unifiedToggleInputViewDidChangeMode(self, mode: mode)
            if self.isExpanded {
                self.textEntryView.becomeFirstResponder()
            }
        }
        addSubview(toggleView)

        inlineDismissButton.addTarget(self, action: #selector(handleInlineDismissTap), for: .primaryActionTriggered)
        addSubview(inlineDismissButton)

        textEntryView.translatesAutoresizingMaskIntoConstraints = false
        textEntryView.isExpandable = false
        textEntryView.placeholderTextColor = UIColor(designSystemColor: .textTertiary)
        addSubview(textEntryView)

        attachmentsStrip.translatesAutoresizingMaskIntoConstraints = false
        attachmentsStrip.clipsToBounds = false
        attachmentsStrip.alpha = 0
        attachmentsStrip.onAttachmentsChanged = { [weak self] in
            guard let self else { return }
            updateAttachmentsStripLayout()
            layoutIfNeeded()
            onNeedsHierarchyLayout?()
            onAttachmentsLayoutDidChange?()
        }
        attachmentsStrip.onAttachmentRemoved = { [weak self] id in
            self?.onAttachmentRemoved?(id)
        }
        addSubview(attachmentsStrip)

        toolsToolbar.translatesAutoresizingMaskIntoConstraints = false
        toolsToolbar.clipsToBounds = true
        toolsToolbar.alpha = 0
        toolsToolbar.onSubmitTapped = { [weak self] in
            guard let self else { return }
            handler.submitText(handler.currentText)
        }
        toolsToolbar.onStopGeneratingTapped = { [weak self] in
            self?.handler.stopGeneratingButtonTapped()
        }
        toolsToolbar.onAttachTapped = { [weak self] in
            self?.onAttachTapped?()
        }
        toolsToolbar.onVoiceTapped = { [weak self] in
            self?.handler.microphoneButtonTapped()
        }
        toolsToolbar.onSelectedToolClearTapped = { [weak self] in
            guard let self else { return }
            delegate?.unifiedToggleInputViewDidClearSelectedTool(self)
        }
        addSubview(toolsToolbar)
        toolsToolbar.refreshFireMode(fireMode: handler.isFireTab)

        textEntryView.onTextInputActivated = { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.delegate?.unifiedToggleInputViewDidTapWhileCollapsed(self)
        }

        setupConstraints()
        applyFireModeAppearance(isFireTab: handler.isFireTab)
    }

    func setupConstraints() {
        cardTopConstraint = cardView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.cardVerticalMargin)
        cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.cardHorizontalMargin)
        cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.cardHorizontalMargin)
        cardBottomConstraint = cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.cardVerticalMargin)
        cardCollapsedHeightConstraint = cardView.heightAnchor.constraint(equalToConstant: Constants.collapsedCardHeight)
        cardCollapsedHeightConstraint.priority = .defaultHigh
        cardCollapsedHeightConstraint.isActive = true
        toggleTopConstraint = toggleView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 0)
        toggleHeightConstraint = toggleView.heightAnchor.constraint(equalToConstant: 0)
        toggleTrailingConstraint = toggleView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Constants.toggleHorizontalPadding)
        inlineDismissHeightConstraint = inlineDismissButton.heightAnchor.constraint(equalToConstant: 0)
        inputTopConstraint = textEntryView.topAnchor.constraint(equalTo: toggleView.bottomAnchor, constant: 0)
        toolbarBottomConstraint = toolsToolbar.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        attachmentsStripHeightConstraint = attachmentsStrip.heightAnchor.constraint(equalToConstant: 0)
        toolbarHeightConstraint = toolsToolbar.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            cardTopConstraint,
            cardLeadingConstraint,
            cardTrailingConstraint,
            cardBottomConstraint,

            toggleTopConstraint,
            toggleView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.toggleHorizontalPadding),
            toggleTrailingConstraint,
            toggleHeightConstraint,

            inlineDismissButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Constants.toggleTopPadding),
            inlineDismissButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Constants.inlineDismissTrailingPadding),
            inlineDismissButton.widthAnchor.constraint(equalToConstant: Constants.inlineDismissSize),
            inlineDismissHeightConstraint,

            inputTopConstraint,
            textEntryView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            textEntryView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            attachmentsStrip.topAnchor.constraint(equalTo: textEntryView.bottomAnchor),
            attachmentsStrip.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            attachmentsStrip.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            attachmentsStripHeightConstraint,

            toolsToolbar.topAnchor.constraint(equalTo: attachmentsStrip.bottomAnchor),
            toolsToolbar.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            toolsToolbar.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            toolbarBottomConstraint,
            toolbarHeightConstraint,
        ])
    }

    func setupSubscriptions() {
        handler.textSubmissionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] submission in
                guard let self else { return }
                delegate?.unifiedToggleInputViewDidSubmitText(self, text: submission.text, mode: submission.mode)
            }
            .store(in: &cancellables)

        handler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                let hasSubmittableText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                toolsToolbar.isSubmitEnabled = hasSubmittableText
                delegate?.unifiedToggleInputViewDidChangeText(self, text: text)
            }
            .store(in: &cancellables)

        handler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self else { return }
                toggleView.setMode(mode, animated: true)
                updateToolbarVisibility(for: mode, animated: true)
            }
            .store(in: &cancellables)

        handler.searchGoToButtonTappedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                delegate?.unifiedToggleInputViewDidTapSearchGoTo(self)
            }
            .store(in: &cancellables)

        textEntryView.textHeightChangeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.onNeedsHierarchyLayout?()
            }
            .store(in: &cancellables)
    }
}
