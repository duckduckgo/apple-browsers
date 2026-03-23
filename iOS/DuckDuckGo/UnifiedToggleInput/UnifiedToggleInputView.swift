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
import UIKit

// MARK: - Delegate Protocol

/// Delegate protocol for handling interactions with the unified toggle input composite view.
protocol UnifiedToggleInputViewDelegate: AnyObject {
    func unifiedToggleInputViewDidTapWhileCollapsed(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidSubmitText(_ view: UnifiedToggleInputView, text: String, mode: TextEntryMode)
    func unifiedToggleInputViewDidChangeText(_ view: UnifiedToggleInputView, text: String)
    func unifiedToggleInputViewDidChangeMode(_ view: UnifiedToggleInputView, mode: TextEntryMode)
    func unifiedToggleInputViewDidTapVoice(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidTapSearchGoTo(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidTapDismiss(_ view: UnifiedToggleInputView)
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
        static let cardCornerRadiusExpanded: CGFloat = 24
        static let cardCornerRadiusCollapsed: CGFloat = 16
        static let toggleTopPadding: CGFloat = 8
        static let toggleBottomPadding: CGFloat = 4
        static let toggleHeight: CGFloat = 40
        static let toggleHorizontalPadding: CGFloat = 8
        static let animationDuration: TimeInterval = 0.25
        static let toggleDisabledSearchTopPadding: CGFloat = 10
        static let dismissButtonSize: CGFloat = 44
        static let dismissButtonTopPadding: CGFloat = 6
        static let cardToDismissSpacing: CGFloat = 8
    }

    // MARK: - Properties

    weak var delegate: UnifiedToggleInputViewDelegate?

    var cardPosition: UnifiedToggleInputCardPosition = .bottom {
        didSet {
            guard cardPosition != oldValue, isExpanded else { return }
            let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            let expandedCorners: CACornerMask = (cardPosition == .top || usesOmnibarMargins) ? allCorners : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            cardView.layer.maskedCorners = expandedCorners
            let shadowGoesDown = cardPosition == .top || usesOmnibarMargins
            expandedShadow0.shadowOffset = CGSize(width: 0, height: shadowGoesDown ? 8 : -8)
            expandedShadow1.shadowOffset = CGSize(width: 0, height: shadowGoesDown ? 2 : -2)
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
        didSet { handler.isVoiceSearchEnabled = isVoiceSearchAvailable }
    }

    var showsDismissButton: Bool = false {
        didSet {
            guard showsDismissButton != oldValue else { return }
            dismissButton.isHidden = !showsDismissButton
            updateCardTrailingConstraint()
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
    private let attachmentsStrip = UnifiedToggleInputAttachmentsStripView()
    private let toolsToolbar = UnifiedToggleInputToolbarView()
    private lazy var dismissButton: UIButton = makeDismissButton()

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
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08).cgColor
            : UIColor(designSystemColor: .shadowSecondary).cgColor
    }

    private var expandedShadow1Color: CGColor {
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12).cgColor
            : UIColor(designSystemColor: .shadowTertiary).cgColor
    }

    // MARK: - Constraints

    private var cardTopConstraint: NSLayoutConstraint!
    private var cardLeadingConstraint: NSLayoutConstraint!
    private var cardTrailingConstraint: NSLayoutConstraint!
    private var cardTrailingConstraintWithDismiss: NSLayoutConstraint!
    private var cardBottomConstraint: NSLayoutConstraint!
    private var cardCollapsedHeightConstraint: NSLayoutConstraint!
    private var toggleTopConstraint: NSLayoutConstraint!
    private var toggleHeightConstraint: NSLayoutConstraint!
    private var inputTopConstraint: NSLayoutConstraint!
    private var toolbarBottomConstraint: NSLayoutConstraint!
    private var attachmentsStripHeightConstraint: NSLayoutConstraint!
    private var toolbarHeightConstraint: NSLayoutConstraint!
    private var dismissButtonTopConstraint: NSLayoutConstraint!
    private var dismissButtonCenterYConstraint: NSLayoutConstraint!

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
        let path = UIBezierPath(rect: bounds).cgPath
        for shadow in [expandedShadow0, expandedShadow1] {
            shadow.bounds = bounds
            shadow.position = CGPoint(x: bounds.midX, y: bounds.midY)
            shadow.shadowPath = path
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            expandedShadow0.shadowColor = expandedShadow0Color
            expandedShadow1.shadowColor = expandedShadow1Color
            cardView.layer.shadowColor = cardShadowColor
            if isExpanded {
                cardView.layer.borderColor = expandedBorderColor
            }
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
        if enabled {
            dismissButtonCenterYConstraint.isActive = false
            dismissButtonTopConstraint.isActive = true
        } else {
            dismissButtonTopConstraint.isActive = false
            dismissButtonCenterYConstraint.isActive = true
        }
        if isExpanded {
            setExpanded(false, animated: false)
            setExpanded(true, animated: false)
        }
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool) {
        handler.setToggleState(mode)
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

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        handler.isExpanded = expanded

        let toggleHeight: CGFloat = (expanded && isToggleEnabled) ? Constants.toggleHeight : 0
        let showToolbar = expanded && isToggleEnabled && toggleView.selectedMode == .aiChat
        let hMargin: CGFloat = (expanded && !showsDismissButton && !usesOmnibarMargins) ? 0 : Constants.cardHorizontalMargin
        let vMargin: CGFloat = (expanded && !usesOmnibarMargins) ? 0 : Constants.cardVerticalMargin

        textEntryView.isExpandable = expanded
        updateCardTrailingConstraint()

        expandedShadow0.isHidden = !expanded
        expandedShadow1.isHidden = !expanded
        if expanded {
            let shadowGoesDown = cardPosition == .top || usesOmnibarMargins
            expandedShadow0.shadowOffset = CGSize(width: 0, height: shadowGoesDown ? 8 : -8)
            expandedShadow1.shadowOffset = CGSize(width: 0, height: shadowGoesDown ? 2 : -2)
        }
        cardView.layer.shadowOpacity = expanded ? 0 : 1.0
        cardCollapsedHeightConstraint.constant = Constants.collapsedCardHeight
        cardCollapsedHeightConstraint.isActive = !expanded

        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let expandedCorners: CACornerMask = (cardPosition == .top || usesOmnibarMargins)
            ? allCorners
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardView.layer.maskedCorners = expanded ? expandedCorners : allCorners
        cardView.clipsToBounds = expanded && (usesOmnibarMargins || !isToggleEnabled)

        cardView.layer.borderWidth = showToolbar ? 0.5 : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor

        let expandedCornerRadius = isToggleEnabled ? Constants.cardCornerRadiusExpanded : Constants.cardCornerRadiusCollapsed
        let changes = {
            self.cardView.layer.cornerRadius = expanded ? expandedCornerRadius : Constants.cardCornerRadiusCollapsed
            self.cardTopConstraint.constant = vMargin
            self.cardLeadingConstraint.constant = hMargin
            self.cardTrailingConstraint.constant = -hMargin
            self.cardBottomConstraint.constant = -vMargin
            self.toggleTopConstraint.constant = (expanded && self.isToggleEnabled) ? Constants.toggleTopPadding : 0
            self.toggleHeightConstraint.constant = toggleHeight
            let toggleDisabledSearchPadding = expanded && !self.isToggleEnabled && self.handler.currentToggleState == .search && self.cardPosition == .bottom
            self.inputTopConstraint.constant = expanded && self.isToggleEnabled ? Constants.toggleBottomPadding : (toggleDisabledSearchPadding ? Constants.toggleDisabledSearchTopPadding : 0)
            self.toolbarBottomConstraint.constant = toggleDisabledSearchPadding ? -Constants.toggleDisabledSearchTopPadding : 0
            self.toggleView.alpha = (expanded && self.isToggleEnabled) ? 1 : 0
            self.toolbarHeightConstraint.constant = showToolbar ? 56 : 0
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
                }
            )
        } else {
            changes()
            layoutIfNeeded()
        }
    }

    func setInactiveCardAppearance(_ inactive: Bool) {
        guard isExpanded else { return }

        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let topOnlyCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        UIView.animate(withDuration: Constants.animationDuration, delay: 0, options: .curveEaseInOut) {
            if inactive {
                self.cardView.layer.maskedCorners = allCorners
                self.expandedShadow0.shadowOffset = CGSize(width: 0, height: 8)
                self.expandedShadow1.shadowOffset = CGSize(width: 0, height: 2)
                self.cardTopConstraint.constant = Constants.cardVerticalMargin
                self.cardLeadingConstraint.constant = Constants.cardHorizontalMargin
                self.cardTrailingConstraint.constant = -Constants.cardHorizontalMargin
                self.cardBottomConstraint.constant = -Constants.cardVerticalMargin
                self.toolbarHeightConstraint.constant = 0
                self.toolsToolbar.alpha = 0
            } else {
                self.cardView.layer.maskedCorners = self.usesOmnibarMargins ? allCorners : topOnlyCorners
                let shadowGoesDown = self.cardPosition == .top || self.usesOmnibarMargins
                self.expandedShadow0.shadowOffset = CGSize(width: 0, height: shadowGoesDown ? 8 : -8)
                self.expandedShadow1.shadowOffset = CGSize(width: 0, height: shadowGoesDown ? 2 : -2)
                let horizontalMargin: CGFloat = (!self.showsDismissButton && !self.usesOmnibarMargins) ? 0 : Constants.cardHorizontalMargin
                let verticalMargin: CGFloat = self.usesOmnibarMargins ? Constants.cardVerticalMargin : 0
                let showToolbar = self.isToggleEnabled && self.toggleView.selectedMode == .aiChat
                self.cardTopConstraint.constant = verticalMargin
                self.cardLeadingConstraint.constant = horizontalMargin
                self.cardTrailingConstraint.constant = -horizontalMargin
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
        guard isExpanded else { return }

        let showToolbar = mode == .aiChat
        toolbarHeightConstraint.constant = showToolbar ? 56 : 0
        cardView.layer.borderWidth = showToolbar ? 0.5 : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor
        expandedShadow0.isHidden = !showToolbar
        expandedShadow1.isHidden = !showToolbar
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
        let showStrip = hasImages && isExpanded && handler.currentToggleState == .aiChat
        attachmentsStripHeightConstraint.constant = showStrip ? UnifiedToggleInputAttachmentsStripView.Constants.stripHeight : 0
        attachmentsStrip.alpha = showStrip ? 1 : 0
    }
}

// MARK: - Setup

private extension UnifiedToggleInputView {

    func setupUI() {
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
        addSubview(toolsToolbar)

        textEntryView.onTextInputActivated = { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.delegate?.unifiedToggleInputViewDidTapWhileCollapsed(self)
        }

        dismissButton.isHidden = true
        addSubview(dismissButton)

        setupConstraints()
    }

    func setupConstraints() {
        let dismissButtonTrailingOffset = -(Constants.dismissButtonSize + Constants.cardToDismissSpacing + Constants.cardHorizontalMargin)

        cardTopConstraint = cardView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.cardVerticalMargin)
        cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.cardHorizontalMargin)
        cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.cardHorizontalMargin)
        cardTrailingConstraintWithDismiss = cardView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: dismissButtonTrailingOffset
        )
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

            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.cardHorizontalMargin),
            dismissButton.widthAnchor.constraint(equalToConstant: Constants.dismissButtonSize),
            dismissButton.heightAnchor.constraint(equalToConstant: Constants.dismissButtonSize),
        ])

        dismissButtonTopConstraint = dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: Constants.dismissButtonTopPadding)
        dismissButtonCenterYConstraint = dismissButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
        if isToggleEnabled {
            dismissButtonTopConstraint.isActive = true
        } else {
            dismissButtonCenterYConstraint.isActive = true
        }
    }

    private func updateCardTrailingConstraint() {
        if isExpanded && showsDismissButton {
            cardTrailingConstraint.isActive = false
            cardTrailingConstraintWithDismiss.isActive = true
        } else {
            cardTrailingConstraintWithDismiss.isActive = false
            cardTrailingConstraint.isActive = true
        }
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

        handler.microphoneButtonTappedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                delegate?.unifiedToggleInputViewDidTapVoice(self)
            }
            .store(in: &cancellables)

        handler.searchGoToButtonTappedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                delegate?.unifiedToggleInputViewDidTapSearchGoTo(self)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Dismiss Button

extension UnifiedToggleInputView {

    private func makeDismissButton() -> UIButton {
        if #available(iOS 26, *) {
            var config = UIButton.Configuration.glass()
            config.image = UIImage(systemName: "xmark")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(handleDismissTap), for: .primaryActionTriggered)
            return button
        }
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImage(systemName: "xmark")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        button.setImage(image, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textPrimary)
        button.backgroundColor = UIColor(singleUseColor: .unifiedToggleInputCardBackground)
        button.layer.cornerRadius = Constants.dismissButtonSize / 2
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.12
        button.layer.shadowRadius = 8
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.addTarget(self, action: #selector(handleDismissTap), for: .primaryActionTriggered)
        return button
    }

    @objc private func handleDismissTap() {
        delegate?.unifiedToggleInputViewDidTapDismiss(self)
    }
}
