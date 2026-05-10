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
import DesignResourcesKitIcons
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

    var isBottom: Bool { self == .bottom }
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
        // Match the omnibar's small-top spacing so the dismiss snap lands on identical pill frames.
        static let collapsedCardTopMarginBottom: CGFloat = 10
        static let collapsedCardBottomMarginBottom: CGFloat = 6
        static let cardCornerRadiusExpanded: CGFloat = 28
        static let cardCornerRadiusCollapsed: CGFloat = 16
        static let toggleTopPadding: CGFloat = 8
        static let toggleBottomPadding: CGFloat = 4
        /// Bottom padding between the input content and the card edge when the AI tools
        /// toolbar is hidden, mirroring `toggleBottomPadding` so the input sits centered
        /// inside its 64pt row per the Figma spec.
        static let inputBottomPadding: CGFloat = 4
        static let toggleHeight: CGFloat = 40
        static let toggleHorizontalPadding: CGFloat = 8
        static let animationDuration: TimeInterval = 0.25
        static let toggleDisabledSearchTopPadding: CGFloat = 6
        static let toolbarHeight: CGFloat = 56
        static let expandedBorderWidth: CGFloat = 0.5
        static let inlineDismissSize: CGFloat = 40
        static let inlineDismissLeadingPadding: CGFloat = 8
        static let toggleInlineDismissSpacing: CGFloat = 8
        /// Spacing between the inline dismiss button and the field's leading content when the
        /// dismiss shares the field row (toggle disabled, top position).
        static let fieldRowInlineDismissSpacing: CGFloat = 4

        /// Leading constant for the toggle when the inline dismiss button shares the top row.
        static var toggleLeadingWithInlineDismiss: CGFloat {
            inlineDismissLeadingPadding + inlineDismissSize + toggleInlineDismissSpacing
        }

        /// Leading constant for the text entry field when the inline dismiss shares the field row.
        static var textEntryViewLeadingWithInlineDismiss: CGFloat {
            inlineDismissLeadingPadding + inlineDismissSize + fieldRowInlineDismissSpacing
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
    private var currentLayout: UnifiedToggleInputCardLayout = .collapsed

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

    var attachmentMenu: UIMenu? {
        get { toolsToolbar.attachmentMenu }
        set { toolsToolbar.attachmentMenu = newValue }
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

    var handlerIsTopBarPosition: Bool {
        get { handler.isTopBarPosition }
        set { handler.isTopBarPosition = newValue }
    }

    // MARK: - Attachment Callbacks

    var onAttachmentRemoved: ((UUID) -> Void)?
    var onInlineDismissTapped: (() -> Void)?
    var onAIChatShortcutTapped: (() -> Void)?

    // MARK: - Attachment API

    var isImageButtonHidden: Bool {
        get { toolsToolbar.isImageButtonHidden }
        set { toolsToolbar.isImageButtonHidden = newValue }
    }

    var isImageButtonEnabled: Bool {
        get { toolsToolbar.isImageButtonEnabled }
        set { toolsToolbar.isImageButtonEnabled = newValue }
    }

    var currentAttachments: [UnifiedToggleInputAttachment] {
        attachmentsStrip.attachments
    }

    func addAttachment(_ attachment: UnifiedToggleInputAttachment) {
        attachmentsStrip.addAttachment(attachment)
    }

    func removeAttachment(id: UUID) {
        attachmentsStrip.removeAttachment(id: id)
    }

    func removeAllAttachments() {
        attachmentsStrip.removeAllAttachments()
    }

    // MARK: - Page-Context Chip

    func bindPageContextChip(to viewModel: UnifiedToggleInputPageContextChipViewModel) {
        pageContextChipCancellables.removeAll()
        pageContextChip.onTapToAttach = { [weak viewModel] in viewModel?.tapToAttach() }
        pageContextChip.onRemove = { [weak viewModel] in viewModel?.tapToRemove() }
        viewModel.$state
            .sink { [weak self] state in self?.pageContextChip.configure(state: state) }
            .store(in: &pageContextChipCancellables)
        viewModel.$isVisible
            .sink { [weak self] isVisible in self?.isPageContextChipPresent = isVisible }
            .store(in: &pageContextChipCancellables)
    }

    private var isPageContextChipPresent: Bool = false {
        didSet {
            guard oldValue != isPageContextChipPresent else { return }
            pageContextChip.isHidden = !isPageContextChipPresent
            pageContextChipHeightConstraint.isActive = !isPageContextChipPresent
            layoutIfNeeded()
            onNeedsHierarchyLayout?()
        }
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
    private let pageContextChip = AIChatContextChipView()
    private var pageContextChipCancellables = Set<AnyCancellable>()

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
    private var toggleHeightConstraint: NSLayoutConstraint!
    private var inlineDismissTopConstraint: NSLayoutConstraint!
    private var inlineDismissCenterYConstraint: NSLayoutConstraint!
    private var inputTopConstraint: NSLayoutConstraint!
    private var textEntryViewLeadingConstraint: NSLayoutConstraint!
    private var toolbarBottomConstraint: NSLayoutConstraint!
    private var attachmentsStripHeightConstraint: NSLayoutConstraint!
    private var pageContextChipHeightConstraint: NSLayoutConstraint!
    private var toolbarHeightConstraint: NSLayoutConstraint!

    // MARK: - Initialization

    init(handler: UnifiedToggleInputHandler, isToggleEnabled: Bool = true) {
        self.handler = handler
        self.isToggleEnabled = isToggleEnabled
        self.textEntryView = SwitchBarTextEntryView(handler: handler, voiceButtonAppearance: .aiVoicePlain)
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

    var placeholderWindowX: CGFloat? { textEntryView.placeholderWindowX }

    var defaultPlaceholderColor: UIColor { textEntryView.defaultPlaceholderColor }

    var placeholderTextColor: UIColor {
        get { textEntryView.placeholderTextColor }
        set { textEntryView.placeholderTextColor = newValue }
    }

    func animatePlaceholderColorTransition(from: UIColor, to color: UIColor, duration: TimeInterval) {
        textEntryView.animatePlaceholderColorTransition(from: from, to: color, duration: duration)
    }

    func setTextHorizontalShift(_ shift: CGFloat) {
        textEntryView.setTextHorizontalShift(shift)
    }

    @discardableResult
    func alignPlaceholderHorizontally(toWindowX windowX: CGFloat) -> CGFloat {
        textEntryView.alignPlaceholderHorizontally(toWindowX: windowX)
    }

    func updateToggleEnabled(_ enabled: Bool) {
        guard enabled != isToggleEnabled else { return }
        isToggleEnabled = enabled
        if isExpanded {
            applyCardLayout(.collapsed, animated: false)
            applyCardLayout(.expanded(showsToggle: enabled, showsToolbar: enabled && toggleView.selectedMode == .aiChat), animated: false)
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
            let showToolbar = mode == .aiChat
            inputTopConstraint.constant = Constants.toggleBottomPadding
            toolbarBottomConstraint.constant = showToolbar ? 0 : -Constants.inputBottomPadding
        } else {
            let usePadding = mode == .search
            let padding = usePadding ? Constants.toggleDisabledSearchTopPadding : 0
            inputTopConstraint.constant = padding
            toolbarBottomConstraint.constant = -padding
        }
    }

    func applyCardLayout(_ layout: UnifiedToggleInputCardLayout, animated: Bool, updateShadow: Bool = true) {
        let expanded = layout.isExpanded
        isExpanded = expanded
        handler.isExpanded = expanded
        textEntryView.voiceButtonAppearance = expanded ? .microphone : .aiVoicePlain
        guard layout != currentLayout else { return }
        currentLayout = layout

        let showsToggle = layout.showsToggle
        let showToolbar = layout.showsToolbar
        let toggleHeight: CGFloat = showsToggle ? Constants.toggleHeight : 0
        // The toggle's leading slot is permanently reserved for the back button so the
        // toggle doesn't slide right as it fades in. Visibility of the dismiss itself is
        // gated on the toggle actually being shown, so the back button can fade in together
        // with the toggle via `applyToggleRevealChanges` rather than snapping in on activation.
        let showInlineDismiss = expanded && showsToggle
        // When the toggle is disabled by the user, the dismiss moves into the field row
        // alongside the inline buttons. Keyed on `isToggleEnabled` (not `showsToggle`)
        // so the dismiss stays hidden during the toggle-on activation transient where
        // `showsToggle` is briefly `false`.
        let showFieldRowInlineDismiss = expanded && !isToggleEnabled

        let hLeadingMargin: CGFloat
        let hTrailingMargin: CGFloat
        if expanded && cardPosition == .bottom && !usesOmnibarMargins {
            hLeadingMargin = Constants.cardHorizontalMarginBottom
            hTrailingMargin = Constants.cardHorizontalMarginBottom
        } else {
            hLeadingMargin = Constants.cardHorizontalMargin
            hTrailingMargin = cardTrailingMargin
        }

        let topMargin: CGFloat
        let bottomMargin: CGFloat
        if expanded && !usesOmnibarMargins {
            let expandedMargin = (cardPosition == .bottom) ? Constants.cardVerticalMarginBottom : Constants.cardVerticalMargin
            topMargin = expandedMargin
            bottomMargin = expandedMargin
        } else if !expanded && cardPosition == .bottom {
            topMargin = Constants.collapsedCardTopMarginBottom
            bottomMargin = Constants.collapsedCardBottomMarginBottom
        } else {
            topMargin = Constants.cardVerticalMargin
            bottomMargin = Constants.cardVerticalMargin
        }

        textEntryView.isExpandable = expanded

        if updateShadow {
            expandedShadowView.isHidden = !expanded
            cardView.layer.shadowOpacity = expanded ? 0 : 1.0
        }
        cardCollapsedHeightConstraint.constant = Constants.collapsedCardHeight
        cardCollapsedHeightConstraint.isActive = !expanded

        cardView.layer.maskedCorners = Constants.allCorners
        cardView.clipsToBounds = expanded && (usesOmnibarMargins || !isToggleEnabled)

        cardView.layer.borderWidth = showToolbar ? Constants.expandedBorderWidth : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor

        let expandedCornerRadius = Constants.cardCornerRadiusExpanded
        let changes = {
            self.cardView.layer.cornerRadius = expanded ? expandedCornerRadius : Constants.cardCornerRadiusCollapsed
            self.cardTopConstraint.constant = topMargin
            self.cardLeadingConstraint.constant = hLeadingMargin
            self.cardTrailingConstraint.constant = -hTrailingMargin
            self.cardBottomConstraint.constant = -bottomMargin
            self.toggleTopConstraint.constant = (expanded && showsToggle) ? Constants.toggleTopPadding : 0
            self.toggleHeightConstraint.constant = toggleHeight
            let toggleDisabledSearchPadding = expanded && !self.isToggleEnabled && self.handler.currentToggleState == .search
            let toggleEnabledNoToolbarPadding = expanded && showsToggle && !showToolbar
            self.inputTopConstraint.constant = (expanded && showsToggle) ? Constants.toggleBottomPadding : (toggleDisabledSearchPadding ? Constants.toggleDisabledSearchTopPadding : 0)
            self.toolbarBottomConstraint.constant = toggleDisabledSearchPadding
                ? -Constants.toggleDisabledSearchTopPadding
                : (toggleEnabledNoToolbarPadding ? -Constants.inputBottomPadding : 0)
            self.toggleView.alpha = (expanded && showsToggle) ? 1 : 0
            self.applyInlineDismissVerticalAnchor(useFieldRowAnchor: showFieldRowInlineDismiss)
            self.applyInlineDismissVisibility(showInlineDismiss || showFieldRowInlineDismiss)
            self.applyTextEntryViewLeadingInset(showFieldRowInlineDismiss: showFieldRowInlineDismiss)
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

    /// Top + toggle-on: slim card with toggle hidden so the toggle can fade in alongside
    /// the bar's grow animation. Top + toggle-off and bottom: collapsed bar — there's no
    /// toggle-reveal transient to stage, so the show pose animates straight from collapsed
    /// to expanded inside the surrounding `UIView.animate`.
    func prepareForOmnibarEditingShow() {
        switch (cardPosition, isToggleEnabled) {
        case (.top, true):
            applyCardLayout(.collapsed, animated: false)
            applyCardLayout(.expanded(showsToggle: false, showsToolbar: false), animated: false)
        case (_, _):
            applyCardLayout(.collapsed, animated: false)
        }
    }

    /// Active editing pose. Call inside a UIView.animate block.
    func applyOmnibarEditingShowPose() {
        switch (cardPosition, isToggleEnabled) {
        case (.top, true):
            applyToggleRevealChanges()
            layoutIfNeeded()
        case (_, _):
            applyCardLayout(.expanded(showsToggle: isToggleEnabled, showsToolbar: isToggleEnabled && toggleView.selectedMode == .aiChat), animated: false)
        }
    }

    /// Inactive editing pose. Call inside a UIView.animate block.
    /// Shadow swap is deferred to `finalizeOmnibarEditingDismiss` so the dominant expanded shadow
    /// stays visible during collapse instead of snapping off mid-animation.
    func applyOmnibarEditingDismissPose() {
        switch (cardPosition, isToggleEnabled) {
        case (.top, true):
            applyToggleHideChanges()
            layoutIfNeeded()
        case (_, _):
            applyCardLayout(.collapsed, animated: false, updateShadow: false)
        }
    }

    /// Snap the shadow to its collapsed-pose state. Bottom and top + toggle-off both defer the
    /// shadow swap during dismiss to keep the dominant expanded shadow visible across the
    /// animation; this restores the collapsed shadow once the UTI is hidden. Top + toggle-on
    /// never alters the shadow during animation, so it doesn't need finalizing here.
    func finalizeOmnibarEditingDismiss() {
        let needsShadowFinalize = cardPosition.isBottom || (cardPosition == .top && !isToggleEnabled)
        guard needsShadowFinalize else { return }
        expandedShadowView.isHidden = true
        cardView.layer.shadowOpacity = 1.0
    }

    /// The property mutations that reveal the toggle within the omnibar-editing card.
    /// Designed to be invoked inside an animation context (UIView.animate or UIViewPropertyAnimator).
    func applyToggleRevealChanges() {
        let showToolbar = toggleView.selectedMode == .aiChat
        cardView.layer.cornerRadius = Constants.cardCornerRadiusExpanded
        toggleTopConstraint.constant = Constants.toggleTopPadding
        toggleHeightConstraint.constant = Constants.toggleHeight
        toggleView.alpha = 1
        applyInlineDismissVisibility(true)
        inputTopConstraint.constant = Constants.toggleBottomPadding
        toolbarBottomConstraint.constant = showToolbar ? 0 : -Constants.inputBottomPadding
        cardView.layer.borderWidth = showToolbar ? Constants.expandedBorderWidth : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor
        toolbarHeightConstraint.constant = showToolbar ? Constants.toolbarHeight : 0
        toolsToolbar.alpha = showToolbar ? 1 : 0
        updateAttachmentsStripLayout()
    }

    /// The property mutations that hide the toggle, returning the card to its slim
    /// omnibar-editing pose. Designed to be invoked inside an animation context.
    func applyToggleHideChanges() {
        cardView.layer.cornerRadius = Constants.cardCornerRadiusCollapsed
        toggleTopConstraint.constant = 0
        toggleHeightConstraint.constant = 0
        toggleView.alpha = 0
        applyInlineDismissVisibility(false)
        inputTopConstraint.constant = 0
        toolbarBottomConstraint.constant = 0
        toolbarHeightConstraint.constant = 0
        toolsToolbar.alpha = 0
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
                // Use handler's currentToggleState — toggleView.selectedMode is only updated when
                // isToggleEnabled, so it goes stale in toggle-off omnibar (search-only).
                let showToolbar = self.handler.currentToggleState == .aiChat
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

    /// Card trailing margin for the current state. The card spans the full width since the
    /// inline X is hosted inside the card (in the toggle row when the toggle is shown, or in
    /// the field row alongside the inline buttons when the toggle is hidden at `.top`).
    private var cardTrailingMargin: CGFloat {
        Constants.cardHorizontalMargin
    }

    private func updateToolbarVisibility(for mode: TextEntryMode, animated: Bool) {
        guard isExpanded else { return }

        let showToolbar = mode == .aiChat
        toolbarHeightConstraint.constant = showToolbar ? Constants.toolbarHeight : 0
        if isToggleEnabled {
            toolbarBottomConstraint.constant = showToolbar ? 0 : -Constants.inputBottomPadding
        }
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
        let hasAttachments = !attachmentsStrip.attachments.isEmpty
        let showStrip = hasAttachments && isExpanded && handler.currentToggleState == .aiChat
        attachmentsStripHeightConstraint.constant = showStrip ? UnifiedToggleInputAttachmentsStripView.Constants.stripHeight : 0
        attachmentsStrip.alpha = showStrip ? 1 : 0
    }
}

// MARK: - Inline Dismiss

private extension UnifiedToggleInputView {

    /// Refreshes the inline dismiss button's row anchor, opacity, and the field's leading
    /// inset. Safe to call outside of animation blocks.
    func refreshInlineDismissPresentation() {
        let showToggleRowDismiss = isExpanded && isToggleEnabled
        let showFieldRowDismiss = isExpanded && !isToggleEnabled
        applyInlineDismissVerticalAnchor(useFieldRowAnchor: showFieldRowDismiss)
        applyInlineDismissVisibility(showToggleRowDismiss || showFieldRowDismiss)
        applyTextEntryViewLeadingInset(showFieldRowInlineDismiss: showFieldRowDismiss)
        layoutIfNeeded()
    }

    /// Apply visibility without touching the toggle's leading constraint. Intended for use
    /// inside existing animation blocks so that opacity animates with the surrounding layout.
    /// The button is laid out at its full size at all times — only opacity is toggled — so
    /// the chevron icon never renders into a partially-collapsed frame mid-animation.
    func applyInlineDismissVisibility(_ visible: Bool) {
        inlineDismissButton.alpha = visible ? 1 : 0
        inlineDismissButton.isUserInteractionEnabled = visible
    }

    /// Switches the inline dismiss button between the toggle-row anchor (top of card) and the
    /// field-row anchor (vertically centered with `textEntryView`). The latter is used when
    /// the toggle is hidden so the X visually shares a row with the inline trailing buttons.
    func applyInlineDismissVerticalAnchor(useFieldRowAnchor: Bool) {
        if useFieldRowAnchor {
            inlineDismissTopConstraint.isActive = false
            inlineDismissCenterYConstraint.isActive = true
        } else {
            inlineDismissCenterYConstraint.isActive = false
            inlineDismissTopConstraint.isActive = true
        }
    }

    /// Pushes the text entry field's leading edge in to leave room for the inline dismiss
    /// when it shares the field row, otherwise lets the field span the card's full width.
    func applyTextEntryViewLeadingInset(showFieldRowInlineDismiss: Bool) {
        textEntryViewLeadingConstraint.constant = showFieldRowInlineDismiss
            ? Constants.textEntryViewLeadingWithInlineDismiss
            : 0
    }

    @objc func handleInlineDismissTap() {
        onInlineDismissTapped?()
    }

    /// Flat, circular back-chevron button hosted inside the card on the leading edge.
    /// Used as the dismiss control across all card positions and toggle states.
    static func makeInlineDismissButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.chevronLeft, for: .normal)
        button.tintColor = UIColor(designSystemColor: .icons)
        button.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        button.layer.cornerRadius = Constants.inlineDismissSize / 2
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = UserText.backButtonTitle
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

        pageContextChip.translatesAutoresizingMaskIntoConstraints = false
        pageContextChip.isHidden = true
        addSubview(pageContextChip)

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
        toolsToolbar.onVoiceTapped = { [weak self] in
            self?.handler.aiVoiceChatButtonTapped()
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

        textEntryView.onAIChatShortcutTapped = { [weak self] in
            self?.onAIChatShortcutTapped?()
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
        inlineDismissTopConstraint = inlineDismissButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Constants.toggleTopPadding)
        inlineDismissCenterYConstraint = inlineDismissButton.centerYAnchor.constraint(equalTo: textEntryView.centerYAnchor)
        inputTopConstraint = textEntryView.topAnchor.constraint(equalTo: toggleView.bottomAnchor, constant: 0)
        textEntryViewLeadingConstraint = textEntryView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor)
        toolbarBottomConstraint = toolsToolbar.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        attachmentsStripHeightConstraint = attachmentsStrip.heightAnchor.constraint(equalToConstant: 0)
        pageContextChipHeightConstraint = pageContextChip.heightAnchor.constraint(equalToConstant: 0)
        toolbarHeightConstraint = toolsToolbar.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            cardTopConstraint,
            cardLeadingConstraint,
            cardTrailingConstraint,
            cardBottomConstraint,

            toggleTopConstraint,
            toggleView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.toggleLeadingWithInlineDismiss),
            toggleView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Constants.toggleHorizontalPadding),
            toggleHeightConstraint,

            inlineDismissTopConstraint,
            inlineDismissButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.inlineDismissLeadingPadding),
            inlineDismissButton.widthAnchor.constraint(equalToConstant: Constants.inlineDismissSize),
            inlineDismissButton.heightAnchor.constraint(equalToConstant: Constants.inlineDismissSize),

            inputTopConstraint,
            textEntryViewLeadingConstraint,
            textEntryView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            pageContextChip.topAnchor.constraint(equalTo: textEntryView.bottomAnchor),
            pageContextChip.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.cardHorizontalMargin),
            pageContextChipHeightConstraint,

            attachmentsStrip.topAnchor.constraint(equalTo: pageContextChip.bottomAnchor),
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
