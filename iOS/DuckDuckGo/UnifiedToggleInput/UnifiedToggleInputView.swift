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
import os.log
import UIKit

private let utiLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.duckduckgo", category: "UTI")

// MARK: - Delegate Protocol

/// Delegate protocol for handling interactions with the unified toggle input composite view.
protocol UnifiedToggleInputViewDelegate: AnyObject {
    func unifiedToggleInputViewDidTapWhileCollapsed(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidSubmitText(_ view: UnifiedToggleInputView, text: String, mode: TextEntryMode)
    func unifiedToggleInputViewDidChangeText(_ view: UnifiedToggleInputView, text: String)
    func unifiedToggleInputViewDidChangeMode(_ view: UnifiedToggleInputView, mode: TextEntryMode)
    func unifiedToggleInputViewDidTapSearchGoTo(_ view: UnifiedToggleInputView)
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
        static let cardTrailingMarginWithDismiss: CGFloat = 68
        static let cardCornerRadiusExpanded: CGFloat = 24
        static let cardCornerRadiusCollapsed: CGFloat = 16
        static let toggleTopPadding: CGFloat = 8
        static let toggleBottomPadding: CGFloat = 4
        static let toggleHeight: CGFloat = 40
        static let toggleHorizontalPadding: CGFloat = 8
        static let animationDuration: TimeInterval = 0.25
        static let toggleDisabledSearchTopPadding: CGFloat = 10
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        utiLog.debug("InputView.hitTest - point: \(point.debugDescription, privacy: .public)")
        let result = super.hitTest(point, with: event)
        return result == self ? nil : result
    }

    // MARK: - Properties

    weak var delegate: UnifiedToggleInputViewDelegate?

    var cardPosition: UnifiedToggleInputCardPosition = .bottom {
        didSet {
            utiLog.debug("InputView.cardPosition.didSet - \(String(describing: oldValue), privacy: .public) → \(String(describing: self.cardPosition), privacy: .public)")
            guard cardPosition != oldValue, isExpanded else {
                utiLog.debug("InputView.cardPosition.didSet ↩️ guard: same value or not expanded")
                return
            }
            let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            cardView.layer.maskedCorners = allCorners
            expandedShadow0.shadowOffset = CGSize(width: 0, height: 8)
            expandedShadow1.shadowOffset = CGSize(width: 0, height: 2)
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
        didSet {
            utiLog.debug("InputView.isToolbarSubmitHidden.didSet - \(oldValue, privacy: .public) → \(self.isToolbarSubmitHidden, privacy: .public)")
            toolsToolbar.isSubmitButtonHidden = isToolbarSubmitHidden
        }
    }

    var isToolbarAIVoiceChatActive: Bool = false {
        didSet {
            utiLog.debug("InputView.isToolbarAIVoiceChatActive.didSet - \(oldValue, privacy: .public) → \(self.isToolbarAIVoiceChatActive, privacy: .public)")
            toolsToolbar.isAIVoiceChatActive = isToolbarAIVoiceChatActive
        }
    }

    var isGenerating: Bool = false {
        didSet {
            utiLog.debug("InputView.isGenerating.didSet - \(oldValue, privacy: .public) → \(self.isGenerating, privacy: .public)")
            toolsToolbar.isGenerating = isGenerating
        }
    }

    var modelName: String {
        get { toolsToolbar.modelName }
        set { toolsToolbar.modelName = newValue }
    }

    var modelPickerMenu: UIMenu? {
        get { toolsToolbar.modelPickerMenu }
        set { toolsToolbar.modelPickerMenu = newValue }
    }

    var isModelChipHidden: Bool {
        get { toolsToolbar.isModelChipHidden }
        set { toolsToolbar.isModelChipHidden = newValue }
    }

    var isCustomizeResponsesButtonHidden: Bool {
        get { toolsToolbar.isCustomizeResponsesButtonHidden }
        set { toolsToolbar.isCustomizeResponsesButtonHidden = newValue }
    }

    /// Called inside animation blocks when a hierarchy-wide layout pass is needed
    /// so that sibling views (e.g. the content container) animate in sync.
    /// The owning view controller sets this.
    var onNeedsHierarchyLayout: (() -> Void)?
    var onAttachmentsLayoutDidChange: (() -> Void)?

    var isVoiceSearchAvailable = false {
        didSet {
            utiLog.debug("InputView.isVoiceSearchAvailable.didSet - \(oldValue, privacy: .public) → \(self.isVoiceSearchAvailable, privacy: .public)")
            handler.isVoiceSearchEnabled = isVoiceSearchAvailable
        }
    }

    var usesOmnibarMargins: Bool = false
    private(set) var isToggleEnabled: Bool

    var handlerIsTopBarPosition: Bool {
        get { handler.isTopBarPosition }
        set { handler.isTopBarPosition = newValue }
    }

    // MARK: - Attachment Callbacks

    var onAttachTapped: (() -> Void)?
    var onAttachmentRemoved: ((UUID) -> Void)?

    // MARK: - Attachment API

    var attachButtonView: UIView { toolsToolbar.imageButton }

    var isImageButtonHidden: Bool {
        get { toolsToolbar.isImageButtonHidden }
        set { toolsToolbar.isImageButtonHidden = newValue }
    }

    var isAttachmentsFull: Bool {
        attachmentsStrip.isFull
    }

    var currentAttachments: [AIChatImageAttachment] {
        attachmentsStrip.attachments
    }

    func addAttachment(_ attachment: AIChatImageAttachment) {
        utiLog.debug("InputView.addAttachment - id: \(attachment.id, privacy: .public)")
        attachmentsStrip.addAttachment(attachment)
    }

    func removeAttachment(id: UUID) {
        utiLog.debug("InputView.removeAttachment - id: \(id, privacy: .public)")
        attachmentsStrip.removeAttachment(id: id)
    }

    func removeAllAttachments() {
        utiLog.debug("InputView.removeAllAttachments")
        attachmentsStrip.removeAllAttachments()
    }

    // MARK: - Components

    private let handler: UnifiedToggleInputHandler
    private let textEntryView: SwitchBarTextEntryView
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private let cardView = UIView()
    private let toggleView = UnifiedToggleInputToggleView()
    private let attachmentsStrip = UnifiedToggleInputAttachmentsStripView()
    private let toolsToolbar = UnifiedToggleInputToolbarView()
    // MARK: - Shadow Layers

    private let expandedShadow0: CALayer = {
        let layer = CALayer()
        layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowRadius = 32
        layer.shadowOffset = CGSize(width: 0, height: -8)
        layer.isHidden = true
        return layer
    }()

    private let expandedShadow1: CALayer = {
        let layer = CALayer()
        layer.shadowColor = UIColor(designSystemColor: .shadowTertiary).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.isHidden = true
        return layer
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

    private var expandedShadow0Color: CGColor {
        UIColor(designSystemColor: .shadowSecondary).cgColor
    }

    private var expandedShadow1Color: CGColor {
        UIColor(designSystemColor: .shadowTertiary).cgColor
    }

    // MARK: - Constraints

    private var cardTopConstraint: NSLayoutConstraint!
    private var cardLeadingConstraint: NSLayoutConstraint!
    private var cardTrailingConstraint: NSLayoutConstraint!
    private var cardBottomConstraint: NSLayoutConstraint!
    private var cardCollapsedHeightConstraint: NSLayoutConstraint!
    private var toggleTopConstraint: NSLayoutConstraint!
    private var toggleHeightConstraint: NSLayoutConstraint!
    private var inputTopConstraint: NSLayoutConstraint!
    private var toolbarBottomConstraint: NSLayoutConstraint!
    private var attachmentsStripHeightConstraint: NSLayoutConstraint!
    private var toolbarHeightConstraint: NSLayoutConstraint!

    // MARK: - Initialization

    init(handler: UnifiedToggleInputHandler, isToggleEnabled: Bool = true) {
        utiLog.debug("InputView.init - isToggleEnabled: \(isToggleEnabled, privacy: .public)")
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
        utiLog.debug("InputView.layoutSubviews")
        super.layoutSubviews()
        let cardFrame = cardView.frame
        let cardPath = UIBezierPath(roundedRect: cardFrame, cornerRadius: cardView.layer.cornerRadius).cgPath
        for shadow in [expandedShadow0, expandedShadow1] {
            shadow.bounds = bounds
            shadow.position = CGPoint(x: bounds.midX, y: bounds.midY)
            shadow.shadowPath = cardPath
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        utiLog.debug("InputView.traitCollectionDidChange")
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            utiLog.debug("InputView.traitCollectionDidChange 🔀 colorAppearance changed")
            expandedShadow0.shadowColor = expandedShadow0Color
            expandedShadow1.shadowColor = expandedShadow1Color
            cardView.layer.shadowColor = cardShadowColor
            if isExpanded {
                utiLog.debug("InputView.traitCollectionDidChange 📐 updating borderColor (isExpanded=true)")
                cardView.layer.borderColor = expandedBorderColor
            }
        }
    }

    // MARK: - First Responder

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        utiLog.debug("InputView.becomeFirstResponder")
        return textEntryView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        utiLog.debug("InputView.resignFirstResponder")
        return textEntryView.resignFirstResponder()
    }

    override var isFirstResponder: Bool {
        return textEntryView.isFirstResponder
    }

    // MARK: - Public Methods

    func selectAllText() {
        utiLog.debug("InputView.selectAllText")
        textEntryView.selectAllText()
    }

    func updateToggleEnabled(_ enabled: Bool) {
        utiLog.debug("InputView.updateToggleEnabled - \(self.isToggleEnabled, privacy: .public) → \(enabled, privacy: .public)")
        guard enabled != isToggleEnabled else {
            utiLog.debug("InputView.updateToggleEnabled ↩️ guard: no change")
            return
        }
        isToggleEnabled = enabled
        if isExpanded {
            utiLog.debug("InputView.updateToggleEnabled 🔀 isExpanded=true, re-expanding")
            setExpanded(false, animated: false)
            setExpanded(true, animated: false)
        }
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool) {
        utiLog.debug("InputView.setInputMode - mode: \(String(describing: mode), privacy: .public), animated: \(animated, privacy: .public)")
        utiLog.debug("InputView.setInputMode → calling handler.setToggleState")
        handler.setToggleState(mode)
        if isToggleEnabled {
            utiLog.debug("InputView.setInputMode 🔀 isToggleEnabled=true, setting toggleView mode")
            toggleView.setMode(mode, animated: animated)
        } else {
            utiLog.debug("InputView.setInputMode 🔀 isToggleEnabled=false, skipping toggleView")
        }
        utiLog.debug("InputView.setInputMode → calling updateToolbarVisibility")
        updateToolbarVisibility(for: mode, animated: animated)
        utiLog.debug("InputView.setInputMode → calling updateToggleDisabledSearchPadding")
        updateToggleDisabledSearchPadding(for: mode)
    }

    private func updateToggleDisabledSearchPadding(for mode: TextEntryMode) {
        utiLog.debug("InputView.updateToggleDisabledSearchPadding - mode: \(String(describing: mode), privacy: .public)")
        guard isExpanded else {
            utiLog.debug("InputView.updateToggleDisabledSearchPadding ↩️ guard: not expanded")
            return
        }

        if isToggleEnabled {
            utiLog.debug("InputView.updateToggleDisabledSearchPadding 🔀 isToggleEnabled=true")
            inputTopConstraint.constant = Constants.toggleBottomPadding
            toolbarBottomConstraint.constant = 0
        } else {
            let usePadding = mode == .search && cardPosition == .bottom
            utiLog.debug("InputView.updateToggleDisabledSearchPadding 🔀 isToggleEnabled=false, usePadding=\(usePadding, privacy: .public)")
            let padding = usePadding ? Constants.toggleDisabledSearchTopPadding : 0
            inputTopConstraint.constant = padding
            toolbarBottomConstraint.constant = -padding
        }
    }

    func setExpanded(_ expanded: Bool, showToggle: Bool = true, animated: Bool) {
        utiLog.debug("InputView.setExpanded - \(self.isExpanded, privacy: .public) → \(expanded, privacy: .public), showToggle: \(showToggle, privacy: .public), animated: \(animated, privacy: .public)")
        guard expanded != isExpanded else {
            utiLog.debug("InputView.setExpanded ↩️ guard: already \(self.isExpanded, privacy: .public)")
            return
        }
        isExpanded = expanded
        handler.isExpanded = expanded

        let effectiveToggleEnabled = isToggleEnabled && showToggle
        let toggleHeight: CGFloat = (expanded && effectiveToggleEnabled) ? Constants.toggleHeight : 0
        let showToolbar = expanded && effectiveToggleEnabled && toggleView.selectedMode == .aiChat
        utiLog.debug("InputView.setExpanded 🔀 effectiveToggleEnabled=\(effectiveToggleEnabled, privacy: .public), showToolbar=\(showToolbar, privacy: .public)")

        let hLeadingMargin: CGFloat
        let hTrailingMargin: CGFloat
        let usesDismissMargin = expanded && cardPosition == .top
        if expanded && !usesOmnibarMargins {
            if cardPosition == .bottom {
                utiLog.debug("InputView.setExpanded 🔀 margins: expanded+bottom")
                hLeadingMargin = Constants.cardHorizontalMarginBottom
                hTrailingMargin = Constants.cardHorizontalMarginBottom
            } else {
                utiLog.debug("InputView.setExpanded 🔀 margins: expanded+top, dismissMargin=\(usesDismissMargin, privacy: .public)")
                hLeadingMargin = Constants.cardHorizontalMargin
                hTrailingMargin = usesDismissMargin ? Constants.cardTrailingMarginWithDismiss : Constants.cardHorizontalMargin
            }
        } else if expanded && cardPosition == .top {
            utiLog.debug("InputView.setExpanded 🔀 margins: expanded+top+omnibar")
            hLeadingMargin = Constants.cardHorizontalMargin
            hTrailingMargin = usesDismissMargin ? Constants.cardTrailingMarginWithDismiss : Constants.cardHorizontalMargin
        } else {
            utiLog.debug("InputView.setExpanded 🔀 margins: default")
            hLeadingMargin = Constants.cardHorizontalMargin
            hTrailingMargin = Constants.cardHorizontalMargin
        }

        let vMargin: CGFloat
        if expanded && !usesOmnibarMargins {
            utiLog.debug("InputView.setExpanded 🔀 vMargin: expanded+noOmnibar, position=\(String(describing: self.cardPosition), privacy: .public)")
            vMargin = (cardPosition == .bottom) ? Constants.cardVerticalMarginBottom : Constants.cardVerticalMargin
        } else {
            utiLog.debug("InputView.setExpanded 🔀 vMargin: default")
            vMargin = Constants.cardVerticalMargin
        }

        textEntryView.isExpandable = expanded

        utiLog.debug("InputView.setExpanded 📐 shadow0.isHidden=\(!expanded, privacy: .public), shadow1.isHidden=\(!expanded, privacy: .public)")
        expandedShadow0.isHidden = !expanded
        expandedShadow1.isHidden = !expanded
        if expanded {
            utiLog.debug("InputView.setExpanded 🔀 expanded=true, setting shadow offsets")
            expandedShadow0.shadowOffset = CGSize(width: 0, height: 8)
            expandedShadow1.shadowOffset = CGSize(width: 0, height: 2)
        }
        cardView.layer.shadowOpacity = expanded ? 0 : 1.0
        cardCollapsedHeightConstraint.constant = Constants.collapsedCardHeight
        cardCollapsedHeightConstraint.isActive = !expanded

        cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        cardView.clipsToBounds = expanded && (usesOmnibarMargins || !isToggleEnabled)

        cardView.layer.borderWidth = showToolbar ? 0.5 : 0
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
            let toggleDisabledSearchPadding = expanded && !self.isToggleEnabled && showToggle && self.handler.currentToggleState == .search && self.cardPosition == .bottom
            self.inputTopConstraint.constant = expanded && effectiveToggleEnabled ? Constants.toggleBottomPadding : (toggleDisabledSearchPadding ? Constants.toggleDisabledSearchTopPadding : 0)
            self.toolbarBottomConstraint.constant = toggleDisabledSearchPadding ? -Constants.toggleDisabledSearchTopPadding : 0
            self.toggleView.alpha = (expanded && effectiveToggleEnabled) ? 1 : 0
            self.toolbarHeightConstraint.constant = showToolbar ? 56 : 0
            self.toolsToolbar.alpha = showToolbar ? 1 : 0
            self.updateAttachmentsStripLayout()
        }

        if animated {
            utiLog.debug("InputView.setExpanded 🔀 animated=true")
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
            utiLog.debug("InputView.setExpanded 🔀 animated=false")
            changes()
            layoutIfNeeded()
        }
    }

    func setExpandedWithToggleHidden(_ expanded: Bool) {
        utiLog.debug("InputView.setExpandedWithToggleHidden - expanded: \(expanded, privacy: .public)")
        setExpanded(expanded, showToggle: false, animated: false)
    }

    func animateToggleReveal(additionalAnimations: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        utiLog.debug("InputView.animateToggleReveal")
        guard isExpanded, isToggleEnabled else {
            utiLog.debug("InputView.animateToggleReveal ↩️ guard: isExpanded=\(self.isExpanded, privacy: .public), isToggleEnabled=\(self.isToggleEnabled, privacy: .public)")
            completion?()
            return
        }

        UIView.animate(
            withDuration: Constants.animationDuration,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                self.cardView.layer.cornerRadius = Constants.cardCornerRadiusExpanded
                self.toggleTopConstraint.constant = Constants.toggleTopPadding
                self.toggleHeightConstraint.constant = Constants.toggleHeight
                self.toggleView.alpha = 1
                self.inputTopConstraint.constant = Constants.toggleBottomPadding
                if self.cardPosition == .top {
                    self.cardTrailingConstraint.constant = -Constants.cardTrailingMarginWithDismiss
                }
                additionalAnimations?()
                self.layoutIfNeeded()
            },
            completion: { _ in
                completion?()
            }
        )
    }

    func animateToggleHide(additionalAnimations: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        utiLog.debug("InputView.animateToggleHide")
        guard isExpanded, isToggleEnabled else {
            utiLog.debug("InputView.animateToggleHide ↩️ guard: isExpanded=\(self.isExpanded, privacy: .public), isToggleEnabled=\(self.isToggleEnabled, privacy: .public)")
            completion?()
            return
        }

        if cardPosition == .top {
            utiLog.debug("InputView.animateToggleHide 🔀 cardPosition=top, adjusting trailing")
            cardTrailingConstraint.constant = -Constants.cardHorizontalMargin
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
        utiLog.debug("InputView.setInactiveCardAppearance - inactive: \(inactive, privacy: .public)")
        guard isExpanded else {
            utiLog.debug("InputView.setInactiveCardAppearance ↩️ guard: not expanded")
            return
        }

        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        UIView.animate(withDuration: Constants.animationDuration, delay: 0, options: .curveEaseInOut) {
            if inactive {
                utiLog.debug("InputView.setInactiveCardAppearance 🔀 inactive=true")
                self.cardView.layer.maskedCorners = allCorners
                self.expandedShadow0.shadowOffset = CGSize(width: 0, height: 8)
                self.expandedShadow1.shadowOffset = CGSize(width: 0, height: 2)
                let trailingMargin = self.cardPosition == .top ? Constants.cardTrailingMarginWithDismiss : Constants.cardHorizontalMargin
                self.cardTopConstraint.constant = Constants.cardVerticalMargin
                self.cardLeadingConstraint.constant = Constants.cardHorizontalMargin
                self.cardTrailingConstraint.constant = -trailingMargin
                self.cardBottomConstraint.constant = -Constants.cardVerticalMargin
                self.toolbarHeightConstraint.constant = 0
                self.toolsToolbar.alpha = 0
            } else {
                utiLog.debug("InputView.setInactiveCardAppearance 🔀 inactive=false")
                self.cardView.layer.maskedCorners = allCorners
                self.expandedShadow0.shadowOffset = CGSize(width: 0, height: 8)
                self.expandedShadow1.shadowOffset = CGSize(width: 0, height: 2)
                let leadingMargin: CGFloat
                let trailingMargin: CGFloat
                if !self.usesOmnibarMargins && self.cardPosition == .bottom {
                    utiLog.debug("InputView.setInactiveCardAppearance 🔀 margins: noOmnibar+bottom")
                    leadingMargin = Constants.cardHorizontalMarginBottom
                    trailingMargin = Constants.cardHorizontalMarginBottom
                } else {
                    utiLog.debug("InputView.setInactiveCardAppearance 🔀 margins: default, position=\(String(describing: self.cardPosition), privacy: .public)")
                    leadingMargin = Constants.cardHorizontalMargin
                    trailingMargin = self.cardPosition == .top ? Constants.cardTrailingMarginWithDismiss : Constants.cardHorizontalMargin
                }
                let verticalMargin: CGFloat = (!self.usesOmnibarMargins && self.cardPosition == .bottom)
                    ? Constants.cardVerticalMarginBottom
                    : Constants.cardVerticalMargin
                let showToolbar = self.isToggleEnabled && self.toggleView.selectedMode == .aiChat
                self.cardTopConstraint.constant = verticalMargin
                self.cardLeadingConstraint.constant = leadingMargin
                self.cardTrailingConstraint.constant = -trailingMargin
                self.cardBottomConstraint.constant = -verticalMargin
                self.toolbarHeightConstraint.constant = showToolbar ? 56 : 0
                self.toolsToolbar.alpha = showToolbar ? 1 : 0
            }
            self.layoutIfNeeded()
            self.onNeedsHierarchyLayout?()
        }
    }

    // MARK: - Private

    private func updateToolbarVisibility(for mode: TextEntryMode, animated: Bool) {
        utiLog.debug("InputView.updateToolbarVisibility - mode: \(String(describing: mode), privacy: .public), animated: \(animated, privacy: .public)")
        guard isExpanded else {
            utiLog.debug("InputView.updateToolbarVisibility ↩️ guard: not expanded")
            return
        }

        let showToolbar = mode == .aiChat
        utiLog.debug("InputView.updateToolbarVisibility 🔀 showToolbar=\(showToolbar, privacy: .public)")
        utiLog.debug("InputView.updateToolbarVisibility 📐 setting toolbarHeight=\(showToolbar ? 56 : 0, privacy: .public)")
        toolbarHeightConstraint.constant = showToolbar ? 56 : 0
        cardView.layer.borderWidth = showToolbar ? 0.5 : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor
        updateAttachmentsStripLayout()

        guard animated else {
            utiLog.debug("InputView.updateToolbarVisibility ↩️ guard: not animated, applying immediately")
            toolsToolbar.alpha = showToolbar ? 1 : 0
            attachmentsStrip.alpha = attachmentsStripHeightConstraint.constant > 0 ? 1 : 0
            layoutIfNeeded()
            return
        }
        utiLog.debug("InputView.updateToolbarVisibility 🔀 animated=true")

        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.toolsToolbar.alpha = showToolbar ? 1 : 0
            self.attachmentsStrip.alpha = self.attachmentsStripHeightConstraint.constant > 0 ? 1 : 0
            self.layoutIfNeeded()
            self.onNeedsHierarchyLayout?()
        }
    }

    private func updateAttachmentsStripLayout() {
        utiLog.debug("InputView.updateAttachmentsStripLayout")
        let hasImages = !attachmentsStrip.attachments.isEmpty
        let showStrip = hasImages && isExpanded && handler.currentToggleState == .aiChat
        utiLog.debug("InputView.updateAttachmentsStripLayout 🔀 hasImages=\(hasImages, privacy: .public), showStrip=\(showStrip, privacy: .public)")
        utiLog.debug("InputView.updateAttachmentsStripLayout 📐 stripHeight=\(showStrip ? UnifiedToggleInputAttachmentsStripView.Constants.stripHeight : 0, privacy: .public)")
        attachmentsStripHeightConstraint.constant = showStrip ? UnifiedToggleInputAttachmentsStripView.Constants.stripHeight : 0
        attachmentsStrip.alpha = showStrip ? 1 : 0
    }
}

// MARK: - Setup

private extension UnifiedToggleInputView {

    func setupUI() {
        utiLog.debug("InputView.setupUI")
        clipsToBounds = false
        backgroundColor = .clear

        layer.insertSublayer(expandedShadow0, at: 0)
        layer.insertSublayer(expandedShadow1, at: 1)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(singleUseColor: .unifiedToggleInputCardBackground)
        cardView.layer.cornerRadius = Constants.cardCornerRadiusCollapsed
        cardView.layer.shadowColor = cardShadowColor
        cardView.layer.shadowOpacity = 1.0
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12
        cardView.isUserInteractionEnabled = false
        addSubview(cardView)

        toggleView.translatesAutoresizingMaskIntoConstraints = false
        toggleView.alpha = 0
        toggleView.onModeChanged = { [weak self] mode in
            guard let self else { return }
            self.handler.setToggleState(mode)
            self.delegate?.unifiedToggleInputViewDidChangeMode(self, mode: mode)
            if self.isExpanded {
                self.textEntryView.becomeFirstResponder()
            }
        }
        addSubview(toggleView)

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
        toolsToolbar.onCustomizeResponsesTapped = { [weak self] in
            self?.handler.customizeResponsesButtonTapped()
        }
        toolsToolbar.onAttachTapped = { [weak self] in
            self?.onAttachTapped?()
        }
        toolsToolbar.onVoiceTapped = { [weak self] in
            self?.handler.microphoneButtonTapped()
        }
        addSubview(toolsToolbar)

        textEntryView.onTextInputActivated = { [weak self] in
            guard let self, !self.isExpanded else {
                utiLog.debug("InputView.onTextInputActivated ↩️ guard: nil self or already expanded")
                return
            }
            utiLog.debug("InputView.onTextInputActivated → calling delegate.didTapWhileCollapsed")
            self.delegate?.unifiedToggleInputViewDidTapWhileCollapsed(self)
        }

        setupConstraints()
    }

    func setupConstraints() {
        utiLog.debug("InputView.setupConstraints")
        cardTopConstraint = cardView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.cardVerticalMargin)
        cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.cardHorizontalMargin)
        cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.cardHorizontalMargin)
        cardBottomConstraint = cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.cardVerticalMargin)
        cardCollapsedHeightConstraint = cardView.heightAnchor.constraint(equalToConstant: Constants.collapsedCardHeight)
        cardCollapsedHeightConstraint.priority = .defaultHigh
        cardCollapsedHeightConstraint.isActive = true
        toggleTopConstraint = toggleView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 0)
        toggleHeightConstraint = toggleView.heightAnchor.constraint(equalToConstant: 0)
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
            toggleView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Constants.toggleHorizontalPadding),
            toggleHeightConstraint,

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
        utiLog.debug("InputView.setupSubscriptions")
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
