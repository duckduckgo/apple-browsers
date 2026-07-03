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
    func unifiedToggleInputViewDidRequestSubmitCurrentInput(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidSubmitText(_ view: UnifiedToggleInputView, text: String, mode: TextEntryMode)
    func unifiedToggleInputViewDidChangeText(_ view: UnifiedToggleInputView, text: String)
    func unifiedToggleInputViewDidChangeMode(_ view: UnifiedToggleInputView, mode: TextEntryMode)
    func unifiedToggleInputView(_ view: UnifiedToggleInputView, isDraggingToggle isDragging: Bool)
    func unifiedToggleInputViewDidClearSelectedTool(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidTapFire(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidTapAppMenu(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidTapReturnKey(_ view: UnifiedToggleInputView)
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

    /// Exposed so external chrome (e.g. the top-edge separator anchored outside the animating
    /// UTI hierarchy) can pin to the same Y this footer occupies. The `.aiTab(.collapsed)`
    /// display state renders the `.flanked` card layout, hence the flanked metrics in the body.
    static let aiTabCollapsedFooterHeight: CGFloat =
        Constants.flankedCardHeight
        + Constants.flankedCardTopMargin
        + Constants.flankedCardBottomMargin

    // MARK: - Constants

    private enum Constants {
        // `.collapsed` layout — UTI mimics the regular omnibar pill so the snap between the two
        // surfaces reads as one continuous element.
        static let collapsedCardHeight: CGFloat = 44
        static var cardCornerRadiusCollapsed: CGFloat { OmniBarMetrics.cornerRadius }
        static let collapsedCardTopMargin: CGFloat = 10
        static let collapsedCardBottomMargin: CGFloat = 6
        /// Priority the card's top constraint is dropped to while reproducing the measured omnibar
        /// pill: below `cardPinnedHeightConstraint` (`.defaultHigh`) so the card keeps the pill's
        /// 44pt height (bottom-anchored) regardless of the hosting container's height.
        static let matchedPoseCardTopPriority: UILayoutPriority = .defaultLow
        // `.flanked` layout — 48pt capsule sized to match the fire/voice accessory height.
        static let flankedCardHeight: CGFloat = 48
        static let cardCornerRadiusFlanked: CGFloat = flankedCardHeight / 2
        // 6/6 symmetric margins keep the 48pt card vertically centred in the 60pt navigation
        // container regardless of cardPosition; the previous 10/6 split would have forced
        // auto-layout to break the bottom margin (10+48+6 = 64 > 60) and the card would render
        // shorter than the 48pt fire/voice buttons that flank it.
        static let flankedCardTopMargin: CGFloat = 6
        static let flankedCardBottomMargin: CGFloat = 6
        /// Outer horizontal padding for the whole `.flanked` row: the fire/menu accessory buttons'
        /// distance from the view edges, and the base inset the flanked-pill card is laid out from
        /// (see `flankedHorizontalInset` in `setupConstraints`). Keeps the flanked input's left/right
        /// padding consistent end-to-end.
        static let flankedCardHorizontalMargin: CGFloat = 16
        /// Card container's outer horizontal margin in the non-flanked layouts.
        static let cardHorizontalMargin: CGFloat = 8
        static let cardVerticalMargin: CGFloat = 8
        /// Outer horizontal margin for the expanded card at the bottom-bar position.
        static let cardHorizontalMarginBottom: CGFloat = 8
        static let cardVerticalMarginBottom: CGFloat = 8
        /// Page-context chip's leading inset within the card. Decoupled from `cardHorizontalMargin`
        /// so the card's outer margin can change without shifting the chip.
        static let pageContextChipLeadingInset: CGFloat = 16
        /// Omnibar pill's horizontal inset; the card's hand-off start width so it animates to the
        /// narrower editing margins. Mirrors `DefaultOmniBarView`'s portrait value (landscape/iPad differ).
        static let omnibarMatchingHorizontalMargin: CGFloat = 16
        static let cardCornerRadiusExpanded: CGFloat = 28
        static let toggleTopPadding: CGFloat = 8
        static let toggleBottomPadding: CGFloat = 9
        /// Bottom padding between the input content and the card edge when the AI tools
        /// toolbar is hidden. Slightly larger than the matching top gap so the cursor doesn't
        /// crowd the card's bottom curve in Search mode.
        static let inputBottomPadding: CGFloat = 10
        static let toggleHeight: CGFloat = 40
        static let toggleHorizontalPadding: CGFloat = 8
        static let animationDuration: TimeInterval = 0.25
        static let dismissToggleFadeDuration: TimeInterval = 0.18
        static let toggleDisabledSearchTopPadding: CGFloat = 6
        static let toolbarHeight: CGFloat = 56
        static let expandedBorderWidth: CGFloat = 0.5
        static let inlineDismissSize: CGFloat = 40
        static let inlineDismissLeadingPadding: CGFloat = 8
        static let toggleInlineDismissSpacing: CGFloat = 8
        static let aiTabCollapsedAccessorySize: CGFloat = 48
        static let aiTabExpandedInputTopPadding: CGFloat = 9
        static let aiTabExpandedInputBottomPadding: CGFloat = 6
        static let aiTabExpandedWithToggleInputTopPadding: CGFloat = 0
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
        static let aiTabCollapsedAccessorySpacing: CGFloat = 8
        // Fire / voice fade in once the pill has finished shrinking into its flanked frame.
        static let aiTabCollapsedAccessoryFadeDelay: TimeInterval = 0.18
        static let aiTabCollapsedAccessoryFadeDuration: TimeInterval = 0.12
        // Subtler than the fire button (0.16) to match the visual weight of top-toolbar elements.
        static let aiTabCollapsedMenuButtonShadowOpacity: Float = 0.04
        static let aiTabCollapsedMenuButtonDisabledShadowOpacity: Float = 0.0
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

    /// When true, the inline dismiss (back chevron) and its reserved layout slot are
    /// suppressed regardless of which layout the view is in.
    var isInlineDismissHidden: Bool = false {
        didSet {
            guard isInlineDismissHidden != oldValue else { return }
            refreshInlineDismissPresentation()
        }
    }

    /// True when hosted by a Duck.ai tab. Drives the extra 3pt above/below the text view while
    /// expanded. Set before `setInputMode`/`applyCardLayout` so the layout pass reads it.
    var isAITab: Bool = false

    var text: String {
        get { handler.currentText }
        set { textEntryView.setQueryText(newValue) }
    }

    /// See `SwitchBarTextEntryView.applyDismissSnapshot`.
    func applyDismissSnapshot(_ snapshot: UTIDismissSnapshot) {
        textEntryView.applyDismissSnapshot(snapshot)
        // Toggle pill fades over the full dismiss with easeOut, leaving the labels visible
        // near the end; run a quick fade so they're gone well before UTI lands on the omnibar.
        UIView.animate(withDuration: Constants.dismissToggleFadeDuration,
                       delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState],
                       animations: { [weak self] in
            self?.toggleView.alpha = 0
        })
    }

    func refreshPlaceholderForCurrentMode() {
        textEntryView.refreshPlaceholderForCurrentMode()
    }

    var inputMode: TextEntryMode {
        handler.currentToggleState
    }

    func insertNewlineAtCursor() {
        textEntryView.insertNewlineAtCursor()
    }

    func prepareToolbarSubmitStyleForDismissal() {
        toolsToolbar.prepareForToolbarVisibilityChange(showToolbar: false)
    }

    private(set) var isExpanded = false
    private var currentLayout: UnifiedToggleInputCardLayout = .collapsed

    var isToolbarAIVoiceChatActive: Bool = false {
        didSet { toolsToolbar.isAIVoiceChatActive = isToolbarAIVoiceChatActive }
    }

    var isToolbarSubmitBlockedByRecoveryCard: Bool = false {
        didSet { toolsToolbar.isSubmitBlockedByRecoveryCard = isToolbarSubmitBlockedByRecoveryCard }
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

    @discardableResult
    func presentModelPickerMenu() -> Bool {
        toolsToolbar.presentModelPickerMenu()
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

    var isToolbarReturnKeyHidden: Bool {
        get { toolsToolbar.isReturnKeyHidden }
        set { toolsToolbar.isReturnKeyHidden = newValue }
    }

    /// Caps the text field so the whole card fits within `available` height (the gap above the
    /// keyboard in landscape); nil lifts the cap. Chrome is constant, so the field's ceiling is
    /// the budget minus chrome, and it scrolls beyond that.
    func setAvailableExpandedHeight(_ available: CGFloat?) {
        guard let available else {
            textEntryView.externalMaxHeightCap = nil
            return
        }
        layoutIfNeeded()
        guard bounds.height > 0 else { return }
        let chrome = bounds.height - textEntryView.bounds.height
        textEntryView.externalMaxHeightCap = available - chrome
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
        set {
            guard handler.isTopBarPosition != newValue else { return }
            handler.updateBarPosition(isTop: newValue)
            textEntryView.updatePoseForCurrentState()
        }
    }

    // MARK: - Attachment Callbacks

    var onAttachmentRemoved: ((UUID, UnifiedToggleInputAttachment, Bool) -> Void)?
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

    var isToolbarSubmitEnabled: Bool {
        toolsToolbar.isSubmitEnabled
    }

    func addAttachment(_ attachment: UnifiedToggleInputAttachment) {
        attachmentsStrip.addAttachment(attachment)
    }

    func replaceAttachment(id: UUID, with attachment: UnifiedToggleInputAttachment) {
        attachmentsStrip.replaceAttachment(id: id, with: attachment)
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

    private lazy var aiTabCollapsedFireButton: UIButton = {
        let button = Self.makeAITabAccessoryButton(image: DesignSystemImages.Glyphs.Size24.fireSolid, traitCollection: traitCollection)
        button.isHidden = true
        button.accessibilityLabel = UserText.actionForgetAll
        button.addTarget(self, action: #selector(fireTapped), for: .touchUpInside)
        return button
    }()

    /// The collapsed AI-tab fire button. Exposed for onboarding highlight and enable/disable targeting.
    var aiTabFireButton: UIButton { aiTabCollapsedFireButton }

    private lazy var aiTabCollapsedMenuButton: UIButton = {
        let button = Self.makeAITabAccessoryButton(image: DesignSystemImages.Glyphs.Size24.menuHamburger, traitCollection: traitCollection)
        button.isHidden = true
        button.accessibilityLabel = UserText.menuButtonHint
        button.addTarget(self, action: #selector(appMenuTapped), for: .touchUpInside)
        return button
    }()

    @objc private func fireTapped() {
        delegate?.unifiedToggleInputViewDidTapFire(self)
    }

    @objc private func appMenuTapped() {
        delegate?.unifiedToggleInputViewDidTapAppMenu(self)
    }

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
            .init(id: ShadowID.outer,
                  color: UIColor(designSystemColor: .shadowSecondary),
                  radius: 32,
                  offset: CGSize(width: 0, height: 8)),
            .init(id: ShadowID.rim,
                  color: UIColor(designSystemColor: .shadowTertiary),
                  radius: 16,
                  offset: CGSize(width: 0, height: 2)),
        ]
    }

    private var flankedShadows: [CompositeShadowView.Shadow] {
        [
            CompositeShadowView.Shadow.defaultLayer1.withID(ShadowID.outer),
            .init(id: ShadowID.rim,
                  color: UIColor(designSystemColor: .shadowSecondary),
                  radius: 6,
                  offset: CGSize(width: 0, height: 2)),
        ]
    }

    /// Mirrors `CompositeShadowView.applyDefaultShadow()` (used by the standard omnibar) so the
    /// UTI's composite shadow can morph to the omnibar's shape without a visible swap.
    private var omnibarMatchingShadows: [CompositeShadowView.Shadow] {
        [
            CompositeShadowView.Shadow.defaultLayer2.withID(ShadowID.outer),
            CompositeShadowView.Shadow.defaultLayer1.withID(ShadowID.rim),
        ]
    }

    /// Stable IDs so we can mutate shadows in place at runtime via `updateShadow(_:)`
    /// instead of reassigning `.shadows` (which recreates sublayers mid-animation).
    private enum ShadowID {
        static let outer = "outer"
        static let rim = "rim"
    }

    /// Window-space frame of the resting omnibar pill (`searchContainer`), captured at focus time.
    /// The bottom-position collapsed pose aligns to this so the UTI↔omnibar hand-off has no snap.
    /// Unused at the top position, which matches via fixed omnibar margins.
    var omnibarPillWindowFrame: CGRect?

    /// Card constraint constants that reproduce the resting omnibar pill at the bottom position.
    /// Cached at focus — when the container is laid out at its editing-start frame and the pill can
    /// be measured — so the symmetric dismiss can land back on the pill without re-measuring (the
    /// pill has been removed from the toolbar by then).
    private var cachedOmnibarMatchedInsets: OmnibarMatchedInsets?

    private struct OmnibarMatchedInsets {
        let leading: CGFloat
        let trailing: CGFloat
        /// Gap from the card's bottom edge to the container's bottom (a stable screen-space offset);
        /// combined with the pinned 44pt height this reproduces the pill at any container height.
        let bottom: CGFloat
    }

    /// The collapsed pill's corner radius. The bottom floating omnibar renders as a capsule
    /// (radius = height / 2); the top omnibar uses the standard omnibar radius.
    private var collapsedCornerRadius: CGFloat {
        cardPosition == .bottom ? Constants.collapsedCardHeight / 2 : Constants.cardCornerRadiusCollapsed
    }

    private func cardBackgroundColor(isFireTab: Bool) -> UIColor {
        UIColor(singleUseColor: isFireTab ? .fireModeCardBackground : .unifiedToggleInputCardBackground)
    }

    // MARK: - Constraints

    private var cardTopConstraint: NSLayoutConstraint!
    private var cardLeadingConstraint: NSLayoutConstraint!
    private var cardLeadingFlankedConstraint: NSLayoutConstraint!
    private var cardTrailingConstraint: NSLayoutConstraint!
    private var cardTrailingFlankedConstraint: NSLayoutConstraint!
    private var cardBottomConstraint: NSLayoutConstraint!
    private var cardPinnedHeightConstraint: NSLayoutConstraint!
    private var toggleTopConstraint: NSLayoutConstraint!
    private var toggleLeadingConstraint: NSLayoutConstraint!
    private var toggleHeightConstraint: NSLayoutConstraint!
    private var inlineDismissTopConstraint: NSLayoutConstraint!
    private var inlineDismissCenterYConstraint: NSLayoutConstraint!
    private var inputTopConstraint: NSLayoutConstraint!
    private var inputBottomConstraint: NSLayoutConstraint!
    private var textEntryViewLeadingConstraint: NSLayoutConstraint!
    private var textEntryViewTrailingConstraint: NSLayoutConstraint!
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
        textEntryView.style = isToggleEnabled ? .multiLine : .singleLine
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
        guard !expandedShadowView.isHidden else { return }
        // Runs inside UIView.animate via layoutIfNeeded so the shadow corners animate with cardView.
        expandedShadowView.layer.cornerRadius = cardView.layer.cornerRadius
        expandedShadowView.layer.maskedCorners = cardView.layer.maskedCorners
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            cardView.layer.shadowColor = cardShadowColor
            // Resync the stored shadows so `CompositeShadowView`'s own trait handler doesn't
            // revert dynamic colors to the init-time config.
            expandedShadowView.shadows = currentLayout == .flanked ? flankedShadows : expandedShadows
            if isExpanded {
                cardView.layer.borderColor = expandedBorderColor
            }
            refreshGlassAITabAccessoryConfigurations()
        }
    }

    private func refreshGlassAITabAccessoryConfigurations() {
        guard #available(iOS 26, *) else { return }
        // Rebuilds config from scratch — re-apply any per-button tweaks here if added later.
        for button in [aiTabCollapsedFireButton, aiTabCollapsedMenuButton] {
            guard let currentImage = button.configuration?.image else { continue }
            var config = Self.glassAccessoryConfiguration(for: traitCollection)
            config.image = currentImage
            config.cornerStyle = .capsule
            button.configuration = config
        }
    }

    // MARK: - Onboarding

    /// Dims the input bar during the fire-education onboarding step while keeping the fire button
    /// fully visible and the text entry non-interactive.
    func setOnboardingDimmed(_ dimmed: Bool) {
        // Dim all direct subviews except the fire and voice accessory buttons — both are rendered
        // at full alpha to avoid a muddy semi-transparent shadow. The voice button's disabled
        // appearance is handled via isEnabled below.
        subviews.filter { $0 !== aiTabCollapsedFireButton && $0 !== aiTabCollapsedMenuButton }.forEach {
            $0.alpha = dimmed ? 0.5 : 1
        }
        // Show the voice button as cleanly disabled (design-system icon tint) rather than dimmed.
        aiTabCollapsedMenuButton.isEnabled = !dimmed
        // Block the text view from directly becoming first responder when the user taps the pill.
        textEntryView.isUserInteractionEnabled = !dimmed
        // Suppress the stop-generating button during onboarding — its red color is distracting even when dimmed.
        handler.isOnboardingLocked = dimmed
        let shadowOpacity = dimmed ? Constants.aiTabCollapsedMenuButtonDisabledShadowOpacity : Constants.aiTabCollapsedMenuButtonShadowOpacity
        Self.applyAITabAccessoryShadow(to: aiTabCollapsedMenuButton, opacity: shadowOpacity)
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
        // Future direct content subviews inherit fire-mode appearance by default; card chrome and collapsed flanking accessories keep the OS trait.
        fireModeContentSubviews.forEach {
            $0.overrideUserInterfaceStyle = style
        }
    }

    private var fireModeContentSubviews: [UIView] {
        subviews.filter {
            $0 !== cardView &&
            $0 !== expandedShadowView &&
            $0 !== aiTabCollapsedFireButton &&
            $0 !== aiTabCollapsedMenuButton
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
    func alignVisibleTextLeadingEdge(toWindowX windowX: CGFloat) -> CGFloat {
        textEntryView.alignVisibleTextLeadingEdge(toWindowX: windowX)
    }

    func updateToggleEnabled(_ enabled: Bool, showsToolbar: Bool) {
        guard enabled != isToggleEnabled else { return }
        isToggleEnabled = enabled
        textEntryView.style = enabled ? .multiLine : .singleLine
        if isExpanded {
            applyCardLayout(.collapsed, animated: false)
            applyCardLayout(.expanded(showsToggle: enabled, showsToolbar: showsToolbar), animated: false)
        }
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool) {
        if handler.currentToggleState != mode {
            handler.setToggleState(mode)
        }
        if isToggleEnabled {
            toggleView.setMode(mode, animated: animated)
        }
        textEntryView.style = mode == .aiChat ? .multiLine : .singleLine
        // Drive textView pose synchronously inside the caller's UIView.animate so the
        // placeholder constraint switch animates rather than snapping when the publisher
        // subscriber fires after the animation transaction has already committed.
        textEntryView.updatePoseForCurrentState()
        updateToolbarVisibility(for: mode, animated: animated)
        updateToggleDisabledSearchPadding(for: mode)
    }

    /// Extra breathing room above the text view while expanded on a Duck.ai tab; zero otherwise.
    private var inputExtraPaddingTop: CGFloat {
        guard isExpanded && isAITab else {
            return 0
        }

        return currentLayout.showsToggle ? Constants.aiTabExpandedWithToggleInputTopPadding : Constants.aiTabExpandedInputTopPadding
    }

    /// Extra breathing room below the text view while expanded on a Duck.ai tab; zero otherwise.
    private var inputExtraPaddingBottom: CGFloat {
        isExpanded && isAITab ? Constants.aiTabExpandedInputBottomPadding : 0
    }

    private func updateToggleDisabledSearchPadding(for mode: TextEntryMode) {
        guard isExpanded else { return }

        let showToolbar = mode == .aiChat

        if isToggleEnabled {
            inputTopConstraint.constant = Constants.toggleBottomPadding + inputExtraPaddingTop
            inputBottomConstraint.constant = inputExtraPaddingBottom
            toolbarBottomConstraint.constant = showToolbar ? 0 : -Constants.inputBottomPadding
        } else {
            let padding = Constants.toggleDisabledSearchTopPadding
            inputTopConstraint.constant = padding + inputExtraPaddingTop
            inputBottomConstraint.constant = 0
            toolbarBottomConstraint.constant = showToolbar ? 0 : -padding
        }
    }

    func setAITabCollapsedFooterPoseActive(_ active: Bool) {
        guard aiTabCollapsedFireButton.isHidden == active else { return }

        if active {
            // alpha-0 before unhide avoids a 1-frame flash on top of the still-wide pill.
            aiTabCollapsedFireButton.alpha = 0
            aiTabCollapsedMenuButton.alpha = 0
        }
        aiTabCollapsedFireButton.isHidden = !active
        aiTabCollapsedMenuButton.isHidden = !active
        textEntryView.placeholderTextAlignment = active ? .center : .natural

        guard active else { return }
        // Clear transient state left by the omnibar dismiss (color + horizontal shift).
        textEntryView.placeholderTextColor = textEntryView.defaultPlaceholderColor
        textEntryView.setTextHorizontalShift(0)
        UIView.animate(withDuration: Constants.aiTabCollapsedAccessoryFadeDuration,
                       delay: Constants.aiTabCollapsedAccessoryFadeDelay,
                       options: .curveEaseOut) {
            self.aiTabCollapsedFireButton.alpha = 1
            self.aiTabCollapsedMenuButton.alpha = 1
        }
    }

    private func setCardFlanked(_ flanked: Bool) {
        cardLeadingConstraint.isActive = !flanked
        cardLeadingFlankedConstraint.isActive = flanked
        cardTrailingConstraint.isActive = !flanked
        cardTrailingFlankedConstraint.isActive = flanked
    }

    private struct CardDimensions {
        /// nil = content-driven height (the multi-row `.expanded` card).
        let pinnedHeight: CGFloat?
        let cornerRadius: CGFloat
    }

    private static func cardDimensions(for layout: UnifiedToggleInputCardLayout) -> CardDimensions {
        switch layout {
        case .collapsed:
            return CardDimensions(pinnedHeight: Constants.collapsedCardHeight,
                                  cornerRadius: Constants.cardCornerRadiusCollapsed)
        case .flanked:
            return CardDimensions(pinnedHeight: Constants.flankedCardHeight,
                                  cornerRadius: Constants.cardCornerRadiusFlanked)
        case .expanded:
            return CardDimensions(pinnedHeight: nil,
                                  cornerRadius: Constants.cardCornerRadiusExpanded)
        }
    }

    func applyCardLayout(_ layout: UnifiedToggleInputCardLayout, animated: Bool) {
        let expanded = layout.isExpanded
        isExpanded = expanded
        handler.isExpanded = expanded
        // The matched omnibar pose (`applyOmnibarMatchedInsets`) drops the top constraint below the
        // pinned height so the card stays the pill's height; restore it here so every other layout
        // is driven by its real top/bottom margins again.
        cardTopConstraint.priority = .required
        // Flanked: hide the in-pill voice icon (external accessories flank the pill, voice is in the Plus menu).
        // Snap synchronously so the focus animation drives the transition — animating here would snapshot at the old layout and drift.
        textEntryView.setVoiceButtonAppearance(layout == .flanked ? .hidden : (expanded ? .microphone : .aiVoicePlain), animated: false)
        if layout != .flanked {
            // Non-flanked: card spans full width, so external fire/menu must hide. The reverse is `setAITabCollapsedFooterPoseActive` (fades in).
            aiTabCollapsedFireButton.isHidden = true
            aiTabCollapsedMenuButton.isHidden = true
        }
        guard layout != currentLayout else { return }
        currentLayout = layout

        let showsToggle = layout.showsToggle
        let showToolbar = layout.showsToolbar
        toolsToolbar.prepareForToolbarVisibilityChange(showToolbar: showToolbar)
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
        } else if layout == .collapsed {
            hLeadingMargin = Constants.omnibarMatchingHorizontalMargin
            hTrailingMargin = Constants.omnibarMatchingHorizontalMargin
        } else {
            hLeadingMargin = Constants.cardHorizontalMargin
            hTrailingMargin = cardTrailingMargin
        }

        let topMargin: CGFloat
        let bottomMargin: CGFloat
        switch layout {
        case .expanded where !usesOmnibarMargins:
            let expandedMargin = (cardPosition == .bottom) ? Constants.cardVerticalMarginBottom : Constants.cardVerticalMargin
            topMargin = expandedMargin
            bottomMargin = expandedMargin
        case .flanked:
            topMargin = Constants.flankedCardTopMargin
            bottomMargin = Constants.flankedCardBottomMargin
        case .collapsed:
            topMargin = Constants.collapsedCardTopMargin
            bottomMargin = Constants.collapsedCardBottomMargin
        case .expanded:
            topMargin = Constants.cardVerticalMargin
            bottomMargin = Constants.cardVerticalMargin
        }

        textEntryView.isExpandable = expanded

        let useCompositeShadow = expanded || layout == .flanked
        // In-place mutation preserves the in-flight cornerRadius CAAnimation.
        expandedShadowView.updateShadows(layout == .flanked ? flankedShadows : expandedShadows)
        expandedShadowView.isHidden = !useCompositeShadow
        cardView.layer.shadowOpacity = useCompositeShadow ? 0 : 1.0
        let dimensions = Self.cardDimensions(for: layout)
        if let pinned = dimensions.pinnedHeight {
            cardPinnedHeightConstraint.constant = pinned
            cardPinnedHeightConstraint.isActive = true
        } else {
            cardPinnedHeightConstraint.isActive = false
        }

        cardView.layer.maskedCorners = Constants.allCorners
        cardView.clipsToBounds = expanded && (usesOmnibarMargins || !isToggleEnabled)

        cardView.layer.borderWidth = showToolbar ? Constants.expandedBorderWidth : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor
        let changes = {
            self.setCardFlanked(layout == .flanked)
            // Bottom collapsed pose is a capsule to match the floating omnibar pill; everything
            // else uses the layout's own radius.
            self.cardView.layer.cornerRadius = (layout == .collapsed) ? self.collapsedCornerRadius : dimensions.cornerRadius
            self.cardTopConstraint.constant = topMargin
            self.cardLeadingConstraint.constant = hLeadingMargin
            self.cardTrailingConstraint.constant = -hTrailingMargin
            self.cardBottomConstraint.constant = -bottomMargin
            self.toggleTopConstraint.constant = (expanded && showsToggle) ? Constants.toggleTopPadding : 0
            self.toggleHeightConstraint.constant = toggleHeight
            // No toggle row → balance the card with matching top/bottom inset so content
            // doesn't sit flush against the edges.
            let toggleDisabledPadding = expanded && !self.isToggleEnabled
            let toggleEnabledNoToolbarPadding = expanded && showsToggle && !showToolbar

            self.inputTopConstraint.constant = ((expanded && showsToggle) ? Constants.toggleBottomPadding : (toggleDisabledPadding ? Constants.toggleDisabledSearchTopPadding : 0)) + self.inputExtraPaddingTop
            self.inputBottomConstraint.constant = self.inputExtraPaddingBottom
            self.toolbarBottomConstraint.constant = toggleDisabledPadding
                ? (showToolbar ? 0 : -Constants.toggleDisabledSearchTopPadding)
                : (toggleEnabledNoToolbarPadding ? -Constants.inputBottomPadding : 0)
            self.toggleView.alpha = (expanded && showsToggle) ? 1 : 0
            self.applyInlineDismissVerticalAnchor(useFieldRowAnchor: showFieldRowInlineDismiss)
            self.applyInlineDismissVisibility(showInlineDismiss || showFieldRowInlineDismiss)
            self.applyTextEntryViewLeadingInset(showFieldRowInlineDismiss: showFieldRowInlineDismiss)
            self.applyToggleLeadingInset()
            // Only restore when re-presenting (focusing) — clearing during the dismiss collapse
            // would fade the buttons in over the same animation that's shrinking them away.
            if expanded {
                self.textEntryView.clearDismissSnapshot()
            }
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
                    if showToolbar {
                        self.toolsToolbar.finalizeToolbarShown()
                    }
                }
            )
        } else {
            changes()
            layoutIfNeeded()
            if showToolbar {
                toolsToolbar.finalizeToolbarShown()
            }
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
            // Pre-apply the inline dismiss leading inset so the text area is already at its
            // final width before animation — otherwise the width change animates with the card.
            if !isToggleEnabled {
                UIView.performWithoutAnimation {
                    self.applyInlineDismissVerticalAnchor(useFieldRowAnchor: true)
                    self.applyTextEntryViewLeadingInset(showFieldRowInlineDismiss: true)
                    self.layoutIfNeeded()
                }
            }
            textEntryView.clearDismissSnapshot()
        }
        alignWithOmnibarChrome()
    }

    /// Active editing pose. Call inside a UIView.animate block.
    func applyOmnibarEditingShowPose() {
        switch (cardPosition, isToggleEnabled) {
        case (.top, true):
            applyToggleRevealChanges()
            layoutIfNeeded()
            // applyCardLayout's `(_, _)` case applies expandedShadows internally; the toggle-reveal
            // path bypasses it, so morph the omnibar-matching pre-stage shadows back here.
            expandedShadowView.updateShadows(expandedShadows)
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
            applyCardLayout(.collapsed, animated: false)
        }
        alignWithOmnibarChrome()
    }

    /// Matches the UTI's chrome (margins, corner radius, composite shadow) to the standard omnibar
    /// so the UTI ↔ omnibar transition has no visible chrome snap at hand-off.
    private func alignWithOmnibarChrome() {
        switch cardPosition {
        case .top:
            // Match the omnibar's symmetric 8pt nav-bar insets; otherwise the top override alone
            // would stretch the pinned 44pt height to 46pt (defaultHigh priority loses to bottom).
            cardTopConstraint.constant = Constants.cardVerticalMargin
            cardBottomConstraint.constant = -Constants.cardVerticalMargin
            // Start width matches the omnibar so the expanded pose (set inside the animation block)
            // can animate the card's width rather than snap it.
            cardLeadingConstraint.constant = Constants.omnibarMatchingHorizontalMargin
            cardTrailingConstraint.constant = -Constants.omnibarMatchingHorizontalMargin
        case .bottom:
            if let cached = cachedOmnibarMatchedInsets {
                // Reproduce the measured pill pose (cached at focus) so the dismiss collapse lands
                // back on the pill without re-measuring — it's no longer in the toolbar by then.
                applyOmnibarMatchedInsets(cached)
            } else {
                // Pre-measurement fallback (and if the pill couldn't be measured): omnibar
                // margins + collapsed vertical insets.
                cardLeadingConstraint.constant = Constants.omnibarMatchingHorizontalMargin
                cardTrailingConstraint.constant = -Constants.omnibarMatchingHorizontalMargin
                cardTopConstraint.constant = Constants.collapsedCardTopMargin
                cardBottomConstraint.constant = -Constants.collapsedCardBottomMargin
            }
        }
        cardView.layer.cornerRadius = collapsedCornerRadius
        expandedShadowView.updateShadows(omnibarMatchingShadows)
        expandedShadowView.isHidden = false
        cardView.layer.shadowOpacity = 0
        // The prior applyCardLayout committed the frame with the .collapsed margins; commit
        // again so our overrides propagate to the cardView's actual frame.
        layoutIfNeeded()
    }

    /// Measures the resting omnibar pill (set via `omnibarPillWindowFrame`) in this view's
    /// coordinate space and pins the collapsed card to it, caching the result for the dismiss
    /// collapse. Must be called once the hosting container is laid out at its editing-start frame
    /// (bottom position only); a no-op otherwise.
    func captureOmnibarMatchedInsets() {
        guard cardPosition == .bottom,
              let pill = omnibarPillWindowFrame,
              window != nil,
              bounds.width > 0 else { return }
        let pillInSelf = convert(pill, from: nil)
        let insets = OmnibarMatchedInsets(
            leading: pillInSelf.minX,
            trailing: -(bounds.width - pillInSelf.maxX),
            bottom: -(bounds.height - pillInSelf.maxY))
        cachedOmnibarMatchedInsets = insets
        applyOmnibarMatchedInsets(insets)
        cardView.layer.cornerRadius = collapsedCornerRadius
        layoutIfNeeded()
    }

    private func applyOmnibarMatchedInsets(_ insets: OmnibarMatchedInsets) {
        cardLeadingConstraint.constant = insets.leading
        cardTrailingConstraint.constant = insets.trailing
        // Anchor the collapsed pill by its bottom gap + pinned 44pt height rather than a fixed
        // top+bottom pair. The hosting container is tall at focus (editing height) and short at
        // dismiss (resting toolbar height); pinning both edges to capture-time constants would
        // squeeze the card shorter than the pill on dismiss (a vertically squished "catseye").
        // The bottom gap is a stable screen-space offset (container bottom → pill bottom), so a
        // bottom-anchored, fixed-height card lands exactly on the pill at both ends.
        cardBottomConstraint.constant = insets.bottom
        cardTopConstraint.priority = Constants.matchedPoseCardTopPriority
        cardPinnedHeightConstraint.constant = Constants.collapsedCardHeight
        cardPinnedHeightConstraint.isActive = true
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
        // Width animation: this reveal path bypasses `applyCardLayout`, so set the expanded margins here.
        cardLeadingConstraint.constant = Constants.cardHorizontalMargin
        cardTrailingConstraint.constant = -cardTrailingMargin
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
        attachmentsStripHeightConstraint.constant = 0
        attachmentsStrip.alpha = 0
        textEntryView.isExpandable = false
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
        toolsToolbar.prepareForToolbarVisibilityChange(showToolbar: showToolbar)
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
            if showToolbar {
                toolsToolbar.finalizeToolbarShown()
            }
            return
        }

        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.toolsToolbar.alpha = showToolbar ? 1 : 0
            self.attachmentsStrip.alpha = self.attachmentsStripHeightConstraint.constant > 0 ? 1 : 0
            self.layoutIfNeeded()
            self.onNeedsHierarchyLayout?()
        } completion: { _ in
            if showToolbar {
                self.toolsToolbar.finalizeToolbarShown()
            }
        }
    }

    private func updateAttachmentsStripLayout() {
        let hasAttachments = !attachmentsStrip.attachments.isEmpty
        let showStrip = hasAttachments && isExpanded && handler.currentToggleState == .aiChat
        attachmentsStripHeightConstraint.constant = showStrip ? UnifiedToggleInputAttachmentsStripView.Constants.stripHeight : 0
        attachmentsStrip.alpha = showStrip ? 1 : 0
    }
    
    private func updateSubmitButtonAvailability() {
        let isAIChatMode = handler.currentToggleState == .aiChat
        let hasText = !handler.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasValidAttachment = isAIChatMode && attachmentsStrip.attachments.contains { !$0.isInvalid }
        let hasInvalidAttachment = isAIChatMode && attachmentsStrip.attachments.contains(where: \.isInvalid)

        toolsToolbar.isSubmitEnabled = !hasInvalidAttachment && (hasText || hasValidAttachment)
        updateNewPromptSubmitStyle()
    }

    private func updateNewPromptSubmitStyle() {
        toolsToolbar.usesNewPromptSubmitStyle = handler.submitsAIChatOnKeyboardReturn
    }

    private func submitCurrentInput() {
        delegate?.unifiedToggleInputViewDidRequestSubmitCurrentInput(self)
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
        applyToggleLeadingInset()
        layoutIfNeeded()
    }

    /// Apply visibility without touching the toggle's leading constraint. Intended for use
    /// inside existing animation blocks so that opacity animates with the surrounding layout.
    /// The button is laid out at its full size at all times — only opacity is toggled — so
    /// the chevron icon never renders into a partially-collapsed frame mid-animation.
    func applyInlineDismissVisibility(_ visible: Bool) {
        let effective = visible && !isInlineDismissHidden
        inlineDismissButton.alpha = effective ? 1 : 0
        inlineDismissButton.isUserInteractionEnabled = effective
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
        let effective = showFieldRowInlineDismiss && !isInlineDismissHidden
        textEntryViewLeadingConstraint.constant = effective
            ? Constants.textEntryViewLeadingWithInlineDismiss
            : 0
    }

    /// Pulls the toggle flush to the card's leading edge when the inline dismiss is suppressed;
    /// otherwise reserves the slot for the back-chevron button.
    func applyToggleLeadingInset() {
        toggleLeadingConstraint.constant = isInlineDismissHidden
            ? Constants.toggleHorizontalPadding
            : Constants.toggleLeadingWithInlineDismiss
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

    /// Liquid Glass on iOS 26+, raised fill on legacy. Used for the fire / voice
    /// accessories flanking the collapsed input pill on Duck.ai tabs.
    static func makeAITabAccessoryButton(image: UIImage?, traitCollection: UITraitCollection) -> UIButton {
        if #available(iOS 26, *) {
            return makeGlassAITabAccessoryButton(image: image, traitCollection: traitCollection)
        }

        let button = makeLegacyAITabAccessoryButton(image: image)
        applyAITabAccessoryShadow(to: button)
        return button
    }

    @available(iOS 26, *)
    private static func makeGlassAITabAccessoryButton(image: UIImage?, traitCollection: UITraitCollection) -> UIButton {
        var config = glassAccessoryConfiguration(for: traitCollection)
        config.image = image
        config.cornerStyle = .capsule

        let button = UIButton(configuration: config)
        configureAITabAccessoryButton(button)
        applyAITabAccessoryShadow(to: button)
        return button
    }

    /// Mirrors `AIChatTabChatHeaderView`'s glass-pill style swap: regular glass in light mode
    /// (visible material on white chrome), clear glass in dark mode (lighter, refractive).
    @available(iOS 26, *)
    static func glassAccessoryConfiguration(for traitCollection: UITraitCollection) -> UIButton.Configuration {
        traitCollection.userInterfaceStyle == .dark ? .clearGlass() : .glass()
    }

    private static func makeLegacyAITabAccessoryButton(image: UIImage?) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.backgroundColor = UIColor(singleUseColor: .unifiedToggleInputCardBackground)
        button.layer.cornerRadius = Constants.aiTabCollapsedAccessorySize / 2
        configureAITabAccessoryButton(button)
        return button
    }

    private static func configureAITabAccessoryButton(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(designSystemColor: .icons)
        button.clipsToBounds = false
    }

    private static func applyAITabAccessoryShadow(to button: UIButton, opacity: Float = 0.16) {
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = opacity
        button.layer.shadowOffset = CGSize(width: 0, height: 8)
        button.layer.shadowRadius = 16
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
        // Init matches `currentLayout = .collapsed`; AI-tab callers transition to `.flanked`
        // via `applyCardLayout` and pick up the capsule radius then.
        cardView.layer.cornerRadius = Constants.cardCornerRadiusCollapsed
        cardView.layer.shadowColor = cardShadowColor
        cardView.layer.shadowOpacity = 1.0
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12
        cardView.isUserInteractionEnabled = false
        addSubview(cardView)
        addSubview(aiTabCollapsedFireButton)
        addSubview(aiTabCollapsedMenuButton)

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
        toggleView.onDragStateChanged = { [weak self] isDragging in
            guard let self else { return }
            self.delegate?.unifiedToggleInputView(self, isDraggingToggle: isDragging)
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
            updateSubmitButtonAvailability()
            layoutIfNeeded()
            onNeedsHierarchyLayout?()
            onAttachmentsLayoutDidChange?()
        }
        attachmentsStrip.onAttachmentRemoved = { [weak self] id, attachment, isUserInitiated in
            self?.onAttachmentRemoved?(id, attachment, isUserInitiated)
        }
        addSubview(attachmentsStrip)

        toolsToolbar.translatesAutoresizingMaskIntoConstraints = false
        toolsToolbar.clipsToBounds = true
        toolsToolbar.alpha = 0
        toolsToolbar.onSubmitTapped = { [weak self] in
            guard let self else { return }
            submitCurrentInput()
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
        toolsToolbar.onReturnKeyTapped = { [weak self] in
            guard let self else { return }
            delegate?.unifiedToggleInputViewDidTapReturnKey(self)
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
        // Initialise with collapsed-pose values to match the default `currentLayout = .collapsed`.
        // `applyCardLayout` early-returns when called with the same layout, so the init values
        // need to match that initial layout exactly. AI-tab callers transition into `.flanked`
        // explicitly; `applyCardLayout(.flanked)` then writes the AI-tab-pose values.
        cardTopConstraint = cardView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.collapsedCardTopMargin)
        cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.omnibarMatchingHorizontalMargin)
        // Anchoring to self (not to the flank buttons) keeps voice/fire out of the card's
        // dependency chain. Inner content's intrinsic width pressure can no longer slide
        // voice — Auto Layout has to compress the content instead.
        let flankedHorizontalInset = Constants.flankedCardHorizontalMargin
            + Constants.aiTabCollapsedAccessorySize
            + Constants.aiTabCollapsedAccessorySpacing
        cardLeadingFlankedConstraint = cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: flankedHorizontalInset)
        cardLeadingFlankedConstraint.isActive = false
        cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.omnibarMatchingHorizontalMargin)
        cardTrailingFlankedConstraint = cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -flankedHorizontalInset)
        cardTrailingFlankedConstraint.isActive = false
        cardBottomConstraint = cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.collapsedCardBottomMargin)
        cardPinnedHeightConstraint = cardView.heightAnchor.constraint(equalToConstant: Constants.collapsedCardHeight)
        cardPinnedHeightConstraint.priority = .defaultHigh
        cardPinnedHeightConstraint.isActive = true
        toggleTopConstraint = toggleView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 0)
        toggleLeadingConstraint = toggleView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.toggleLeadingWithInlineDismiss)
        toggleHeightConstraint = toggleView.heightAnchor.constraint(equalToConstant: 0)
        inlineDismissTopConstraint = inlineDismissButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Constants.toggleTopPadding)
        inlineDismissCenterYConstraint = inlineDismissButton.centerYAnchor.constraint(equalTo: textEntryView.centerYAnchor)
        inputTopConstraint = textEntryView.topAnchor.constraint(equalTo: toggleView.bottomAnchor, constant: 0)
        inputBottomConstraint = pageContextChip.topAnchor.constraint(equalTo: textEntryView.bottomAnchor)
        textEntryViewLeadingConstraint = textEntryView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor)
        textEntryViewTrailingConstraint = textEntryView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor)
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
            toggleLeadingConstraint,
            toggleView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Constants.toggleHorizontalPadding),
            toggleHeightConstraint,

            inlineDismissTopConstraint,
            inlineDismissButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.inlineDismissLeadingPadding),
            inlineDismissButton.widthAnchor.constraint(equalToConstant: Constants.inlineDismissSize),
            inlineDismissButton.heightAnchor.constraint(equalToConstant: Constants.inlineDismissSize),

            inputTopConstraint,
            textEntryViewLeadingConstraint,
            textEntryViewTrailingConstraint,

            inputBottomConstraint,
            pageContextChip.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.pageContextChipLeadingInset),
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

            aiTabCollapsedFireButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.flankedCardHorizontalMargin),
            aiTabCollapsedFireButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            aiTabCollapsedFireButton.widthAnchor.constraint(equalToConstant: Constants.aiTabCollapsedAccessorySize),
            aiTabCollapsedFireButton.heightAnchor.constraint(equalToConstant: Constants.aiTabCollapsedAccessorySize),

            aiTabCollapsedMenuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.flankedCardHorizontalMargin),
            aiTabCollapsedMenuButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            aiTabCollapsedMenuButton.widthAnchor.constraint(equalToConstant: Constants.aiTabCollapsedAccessorySize),
            aiTabCollapsedMenuButton.heightAnchor.constraint(equalToConstant: Constants.aiTabCollapsedAccessorySize),
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
                updateSubmitButtonAvailability()
                delegate?.unifiedToggleInputViewDidChangeText(self, text: text)
            }
            .store(in: &cancellables)

        handler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] mode in
                guard let self else { return }
                toggleView.setMode(mode, animated: true)
                updateToolbarVisibility(for: mode, animated: true)
                updateSubmitButtonAvailability()
            }
            .store(in: &cancellables)

        handler.submitsAIChatOnKeyboardReturnPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNewPromptSubmitStyle()
            }
            .store(in: &cancellables)

        textEntryView.textHeightChangeSubject
            .sink { [weak self] in
                self?.onNeedsHierarchyLayout?()
            }
            .store(in: &cancellables)
    }
}
