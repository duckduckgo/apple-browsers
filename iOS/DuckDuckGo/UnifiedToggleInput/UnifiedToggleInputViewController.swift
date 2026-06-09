//
//  UnifiedToggleInputViewController.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

// MARK: - Delegate Protocol

/// Delegate for handling unified toggle input events at the coordinator/business-logic level.
/// The view controller translates raw view events into these higher-level callbacks.
protocol UnifiedToggleInputViewControllerDelegate: AnyObject {
    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidRequestSubmitCurrentInput(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode)
    func unifiedToggleInputVCDidClearSelectedTool(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachment id: UUID, attachment: UnifiedToggleInputAttachment, isUserInitiated: Bool)
    func unifiedToggleInputVCDidChangeAttachments(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidChangeHeight(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapInlineDismiss(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapAIChatShortcut(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapFire(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapAppMenu(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapReturnKey(_ vc: UnifiedToggleInputViewController)
}

// MARK: - View Controller

/// Manages the `UnifiedToggleInputView` lifecycle and acts as its delegate.
/// Provides a typed API for the coordinator to drive the view without direct view access.
final class UnifiedToggleInputViewController: UIViewController {

    // MARK: - Properties

    weak var delegate: UnifiedToggleInputViewControllerDelegate?

    let isToggleEnabled: Bool
    let handler: UnifiedToggleInputHandler
    private lazy var inputBarView = UnifiedToggleInputView(handler: handler, isToggleEnabled: isToggleEnabled)
    private(set) var attachmentValidationMessage: String?

    private var containerView: UnifiedToggleInputContainerView? {
        guard isViewLoaded else { return nil }
        return view as? UnifiedToggleInputContainerView
    }

    // MARK: - Public API

    /// The collapsed AI-tab fire button. Exposed for onboarding highlight and enable/disable targeting.
    var aiTabFireButton: UIButton { inputBarView.aiTabFireButton }

    /// Dims the input bar for the fire-education onboarding step without affecting the fire button.
    func setOnboardingDimmed(_ dimmed: Bool) {
        inputBarView.setOnboardingDimmed(dimmed)
    }

    init(isToggleEnabled: Bool, isFireTab: Bool = false) {
        self.isToggleEnabled = isToggleEnabled
        self.handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false,
                                                 isToggleEnabled: isToggleEnabled,
                                                 isFireTab: isFireTab)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String {
        get { inputBarView.text }
        set { inputBarView.text = newValue }
    }

    func applyDismissSnapshot(_ snapshot: UTIDismissSnapshot) {
        inputBarView.applyDismissSnapshot(snapshot)
    }

    func refreshPlaceholderForCurrentMode() {
        inputBarView.refreshPlaceholderForCurrentMode()
    }

    var isInputExpanded: Bool {
        inputBarView.isExpanded
    }

    var isInputFirstResponder: Bool {
        inputBarView.isFirstResponder
    }

    var inputMode: TextEntryMode {
        inputBarView.inputMode
    }

    func insertNewlineAtCursor() {
        inputBarView.insertNewlineAtCursor()
    }

    func prepareToolbarSubmitStyleForDismissal() {
        inputBarView.prepareToolbarSubmitStyleForDismissal()
    }

    var isVoiceSearchAvailable: Bool {
        get { handler.isVoiceSearchEnabled }
        set {
            handler.isVoiceSearchEnabled = newValue
            inputBarView.isVoiceSearchAvailable = newValue
        }
    }

    var cardPosition: UnifiedToggleInputCardPosition {
        get { inputBarView.cardPosition }
        set {
            inputBarView.cardPosition = newValue
            containerView?.cardPosition = newValue
        }
    }

    var usesOmnibarMargins: Bool {
        get { inputBarView.usesOmnibarMargins }
        set { inputBarView.usesOmnibarMargins = newValue }
    }

    var isTopBarPosition: Bool {
        get { inputBarView.handlerIsTopBarPosition }
        set { inputBarView.handlerIsTopBarPosition = newValue }
    }

    var isToolbarAIVoiceChatActive: Bool {
        get { inputBarView.isToolbarAIVoiceChatActive }
        set { inputBarView.isToolbarAIVoiceChatActive = newValue }
    }

    var isSubmitBlockedByRecoveryCard: Bool {
        get { inputBarView.isToolbarSubmitBlockedByRecoveryCard }
        set { inputBarView.isToolbarSubmitBlockedByRecoveryCard = newValue }
    }

    var isGenerating: Bool = false {
        didSet {
            guard isGenerating != oldValue else { return }
            handler.isGenerating = isGenerating
            inputBarView.isGenerating = isGenerating
        }
    }

    var modelName: String {
        get { inputBarView.modelName }
        set { inputBarView.modelName = newValue }
    }

    var modelPickerMenu: UIMenu? {
        get { inputBarView.modelPickerMenu }
        set { inputBarView.modelPickerMenu = newValue }
    }

    @discardableResult
    func presentModelPickerMenu() -> Bool {
        inputBarView.presentModelPickerMenu()
    }

    var toolsMenu: UIMenu? {
        get { inputBarView.toolsMenu }
        set { inputBarView.toolsMenu = newValue }
    }

    var attachmentMenu: UIMenu? {
        get { inputBarView.attachmentMenu }
        set { inputBarView.attachmentMenu = newValue }
    }

    var reasoningPickerMenu: UIMenu? {
        get { inputBarView.reasoningPickerMenu }
        set { inputBarView.reasoningPickerMenu = newValue }
    }

    var isModelChipHidden: Bool {
        get { inputBarView.isModelChipHidden }
        set { inputBarView.isModelChipHidden = newValue }
    }

    var selectedTool: AIChatRAGTool? {
        get { inputBarView.selectedTool }
        set { inputBarView.selectedTool = newValue }
    }

    var selectedReasoningMode: AIChatReasoningMode? {
        get { inputBarView.selectedReasoningMode }
        set { inputBarView.selectedReasoningMode = newValue }
    }

    var isToolsButtonHidden: Bool {
        get { inputBarView.isToolsButtonHidden }
        set { inputBarView.isToolsButtonHidden = newValue }
    }

    var isReasoningButtonHidden: Bool {
        get { inputBarView.isReasoningButtonHidden }
        set { inputBarView.isReasoningButtonHidden = newValue }
    }

    var isToolbarReturnKeyHidden: Bool {
        get { inputBarView.isToolbarReturnKeyHidden }
        set { inputBarView.isToolbarReturnKeyHidden = newValue }
    }

    func setAvailableExpandedHeight(_ available: CGFloat?) {
        loadViewIfNeeded()
        inputBarView.setAvailableExpandedHeight(available)
    }

    var isImageButtonHidden: Bool {
        get { inputBarView.isImageButtonHidden }
        set { inputBarView.isImageButtonHidden = newValue }
    }

    var isImageButtonEnabled: Bool {
        get { inputBarView.isImageButtonEnabled }
        set { inputBarView.isImageButtonEnabled = newValue }
    }

    var currentAttachments: [UnifiedToggleInputAttachment] {
        loadViewIfNeeded()
        return inputBarView.currentAttachments
    }

    func addAttachment(_ attachment: UnifiedToggleInputAttachment) {
        loadViewIfNeeded()
        inputBarView.addAttachment(attachment)
    }

    func replaceAttachment(id: UUID, with attachment: UnifiedToggleInputAttachment) {
        loadViewIfNeeded()
        inputBarView.replaceAttachment(id: id, with: attachment)
    }

    func removeAttachment(id: UUID) {
        loadViewIfNeeded()
        inputBarView.removeAttachment(id: id)
    }

    func removeAllAttachments() {
        loadViewIfNeeded()
        inputBarView.removeAllAttachments()
    }

    func showAttachmentValidationError(_ message: String) {
        attachmentValidationMessage = message
        loadViewIfNeeded()
        containerView?.showAttachmentValidationError(message)
        notifyHeightDidChange()
    }

    func clearAttachmentValidationError() {
        guard attachmentValidationMessage != nil else { return }
        attachmentValidationMessage = nil
        containerView?.clearAttachmentValidationError()
        notifyHeightDidChange()
    }

    func apply(_ config: UTIViewConfig, animated: Bool) {
        cardPosition = config.cardPosition
        usesOmnibarMargins = config.usesOmnibarMargins
        isTopBarPosition = config.isTopBarPosition
        // Set before `applyCardLayout` reads the flag.
        inputBarView.isInlineDismissHidden = config.isAITab
        setInputMode(config.inputMode, animated: animated)
        setInactiveCardAppearance(config.inactiveAppearance)
        applyCardLayout(config.cardLayout, animated: animated)
    }

    func applyToolsPresentation(
        isToolsButtonHidden: Bool,
        selectedTool: AIChatRAGTool?,
        toolsMenu: UIMenu?
    ) {
        self.isToolsButtonHidden = isToolsButtonHidden
        self.selectedTool = selectedTool
        self.toolsMenu = toolsMenu
    }

    func applyCardLayout(_ layout: UnifiedToggleInputCardLayout, animated: Bool) {
        inputBarView.applyCardLayout(layout, animated: animated)
    }

    func setAITabCollapsedFooterPoseActive(_ active: Bool) {
        inputBarView.setAITabCollapsedFooterPoseActive(active)
    }

    func prepareForOmnibarEditingShow() {
        inputBarView.prepareForOmnibarEditingShow()
    }

    func applyOmnibarEditingShowPose() {
        inputBarView.applyOmnibarEditingShowPose()
    }

    func applyOmnibarEditingDismissPose() {
        inputBarView.applyOmnibarEditingDismissPose()
    }

    func finalizeOmnibarEditingDismiss() {
        inputBarView.finalizeOmnibarEditingDismiss()
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool) {
        inputBarView.setInputMode(mode, animated: animated)
    }

    func selectAllText() {
        inputBarView.selectAllText()
    }

    var placeholderWindowX: CGFloat? { inputBarView.placeholderWindowX }

    var defaultPlaceholderColor: UIColor { inputBarView.defaultPlaceholderColor }

    var placeholderTextColor: UIColor {
        get { inputBarView.placeholderTextColor }
        set { inputBarView.placeholderTextColor = newValue }
    }

    func animatePlaceholderColorTransition(from: UIColor, to color: UIColor, duration: TimeInterval) {
        inputBarView.animatePlaceholderColorTransition(from: from, to: color, duration: duration)
    }

    func setTextHorizontalShift(_ shift: CGFloat) {
        inputBarView.setTextHorizontalShift(shift)
    }

    @discardableResult
    func alignVisibleTextLeadingEdge(toWindowX windowX: CGFloat) -> CGFloat {
        inputBarView.alignVisibleTextLeadingEdge(toWindowX: windowX)
    }

    func updateToggleEnabled(_ enabled: Bool, showsToolbar: Bool) {
        handler.isToggleEnabled = enabled
        inputBarView.updateToggleEnabled(enabled, showsToolbar: showsToolbar)
    }

    func setInactiveCardAppearance(_ inactive: Bool) {
        inputBarView.setInactiveCardAppearance(inactive)
    }

    func activateInput() {
        inputBarView.becomeFirstResponder()
    }

    func deactivateInput() {
        inputBarView.resignFirstResponder()
    }

    func refreshFireMode(fireMode: Bool) {
        inputBarView.refreshFireMode(fireMode: fireMode)
    }

    // MARK: - Page-Context Chip

    func bindPageContextChip(to viewModel: UnifiedToggleInputPageContextChipViewModel) {
        inputBarView.bindPageContextChip(to: viewModel)
    }

    // MARK: - Lifecycle

    override func loadView() {
        let barView = inputBarView
        barView.delegate = self
        barView.onNeedsHierarchyLayout = { [weak self] in
            guard let self else { return }
            self.notifyHeightDidChange()
        }
        barView.onAttachmentRemoved = { [weak self] id, attachment, isUserInitiated in
            guard let self else { return }
            delegate?.unifiedToggleInputVC(self, didRemoveAttachment: id, attachment: attachment, isUserInitiated: isUserInitiated)
        }
        barView.onAttachmentsLayoutDidChange = { [weak self] in
            guard let self else { return }
            delegate?.unifiedToggleInputVCDidChangeAttachments(self)
        }
        barView.onInlineDismissTapped = { [weak self] in
            guard let self else { return }
            delegate?.unifiedToggleInputVCDidTapInlineDismiss(self)
        }
        barView.onAIChatShortcutTapped = { [weak self] in
            guard let self else { return }
            delegate?.unifiedToggleInputVCDidTapAIChatShortcut(self)
        }
        let containerView = UnifiedToggleInputContainerView(inputView: barView)
        containerView.cardPosition = barView.cardPosition
        if let attachmentValidationMessage {
            containerView.showAttachmentValidationError(attachmentValidationMessage)
        }
        view = containerView
    }

    private func notifyHeightDidChange() {
        delegate?.unifiedToggleInputVCDidChangeHeight(self)
    }
}

// MARK: - UnifiedToggleInputViewDelegate

extension UnifiedToggleInputViewController: UnifiedToggleInputViewDelegate {

    func unifiedToggleInputViewDidTapWhileCollapsed(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidTapWhileCollapsed(self)
    }

    func unifiedToggleInputViewDidRequestSubmitCurrentInput(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidRequestSubmitCurrentInput(self)
    }

    func unifiedToggleInputViewDidSubmitText(_ view: UnifiedToggleInputView, text: String, mode: TextEntryMode) {
        delegate?.unifiedToggleInputVC(self, didSubmitText: text, mode: mode)
    }

    func unifiedToggleInputViewDidChangeText(_ view: UnifiedToggleInputView, text: String) {
        delegate?.unifiedToggleInputVC(self, didChangeText: text)
    }

    func unifiedToggleInputViewDidChangeMode(_ view: UnifiedToggleInputView, mode: TextEntryMode) {
        delegate?.unifiedToggleInputVC(self, didChangeMode: mode)
    }

    func unifiedToggleInputViewDidClearSelectedTool(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidClearSelectedTool(self)
    }

    func unifiedToggleInputViewDidTapFire(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidTapFire(self)
    }

    func unifiedToggleInputViewDidTapAppMenu(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidTapAppMenu(self)
    }

    func unifiedToggleInputViewDidTapReturnKey(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidTapReturnKey(self)
    }
}

private final class UnifiedToggleInputContainerView: UIView {

    private enum Metrics {
        static let bannerHeight: CGFloat = 48
        static let bannerSpacing: CGFloat = 8
        static let topBannerHorizontalMargin: CGFloat = 16
        static let bottomBannerHorizontalMargin: CGFloat = 12
    }

    var cardPosition: UnifiedToggleInputCardPosition = .bottom {
        didSet {
            guard cardPosition != oldValue else { return }
            applyBannerPlacement()
        }
    }

    private let unifiedInputView: UnifiedToggleInputView
    private let errorBannerView = UnifiedToggleInputAttachmentErrorBannerView()

    private var isBannerVisible = false
    private var bannerHeightConstraint: NSLayoutConstraint!
    private var inputTopToContainerConstraint: NSLayoutConstraint!
    private var inputBottomToContainerConstraint: NSLayoutConstraint!
    private var bannerTopToContainerConstraint: NSLayoutConstraint!
    private var bannerBottomToContainerConstraint: NSLayoutConstraint!
    private var bannerTopToInputConstraint: NSLayoutConstraint!
    private var bannerBottomToInputConstraint: NSLayoutConstraint!
    private var bannerLeadingConstraint: NSLayoutConstraint!
    private var bannerTrailingConstraint: NSLayoutConstraint!

    init(inputView: UnifiedToggleInputView) {
        self.unifiedInputView = inputView
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAttachmentValidationError(_ message: String) {
        errorBannerView.message = message
        isBannerVisible = true
        errorBannerView.isHidden = false
        applyBannerPlacement()
    }

    func clearAttachmentValidationError() {
        isBannerVisible = false
        applyBannerPlacement()
        errorBannerView.isHidden = true
    }
}

private extension UnifiedToggleInputContainerView {

    func setupUI() {
        backgroundColor = .clear
        addSubview(unifiedInputView)
        addSubview(errorBannerView)
        unifiedInputView.translatesAutoresizingMaskIntoConstraints = false
        errorBannerView.translatesAutoresizingMaskIntoConstraints = false
        errorBannerView.isHidden = true

        bannerHeightConstraint = errorBannerView.heightAnchor.constraint(equalToConstant: 0)
        inputTopToContainerConstraint = unifiedInputView.topAnchor.constraint(equalTo: topAnchor)
        inputBottomToContainerConstraint = unifiedInputView.bottomAnchor.constraint(equalTo: bottomAnchor)
        bannerTopToContainerConstraint = errorBannerView.topAnchor.constraint(equalTo: topAnchor)
        bannerBottomToContainerConstraint = errorBannerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        bannerTopToInputConstraint = errorBannerView.topAnchor.constraint(equalTo: unifiedInputView.bottomAnchor, constant: Metrics.bannerSpacing)
        bannerBottomToInputConstraint = errorBannerView.bottomAnchor.constraint(equalTo: unifiedInputView.topAnchor, constant: -Metrics.bannerSpacing)
        bannerLeadingConstraint = errorBannerView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor)
        bannerTrailingConstraint = errorBannerView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)

        // Pin content horizontally to the safe area so the card and its flanking buttons clear the
        // Dynamic Island in landscape; the horizontal safe-area inset is 0 in portrait and on iPad.
        NSLayoutConstraint.activate([
            unifiedInputView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            unifiedInputView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            bannerLeadingConstraint,
            bannerTrailingConstraint,
            bannerHeightConstraint,
        ])

        applyBannerPlacement()
    }

    func applyBannerPlacement() {
        NSLayoutConstraint.deactivate([
            inputTopToContainerConstraint,
            inputBottomToContainerConstraint,
            bannerTopToContainerConstraint,
            bannerBottomToContainerConstraint,
            bannerTopToInputConstraint,
            bannerBottomToInputConstraint,
        ])

        bannerHeightConstraint.constant = isBannerVisible ? Metrics.bannerHeight : 0
        let horizontalMargin = cardPosition == .top ? Metrics.topBannerHorizontalMargin : Metrics.bottomBannerHorizontalMargin
        bannerLeadingConstraint.constant = horizontalMargin
        bannerTrailingConstraint.constant = -horizontalMargin

        if !isBannerVisible {
            NSLayoutConstraint.activate([
                inputTopToContainerConstraint,
                inputBottomToContainerConstraint,
                bannerTopToContainerConstraint,
            ])
            return
        }

        switch cardPosition {
        case .top:
            NSLayoutConstraint.activate([
                inputTopToContainerConstraint,
                bannerTopToInputConstraint,
                bannerBottomToContainerConstraint,
            ])
        case .bottom:
            NSLayoutConstraint.activate([
                bannerTopToContainerConstraint,
                bannerBottomToInputConstraint,
                inputBottomToContainerConstraint,
            ])
        }
    }
}

private final class UnifiedToggleInputAttachmentErrorBannerView: UIView {

    var message: String? {
        get { messageLabel.text }
        set { messageLabel.text = newValue }
    }

    private let iconView: UIImageView = {
        let imageView = UIImageView(image: DesignSystemImages.Glyphs.Size24.alertRecolorable)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.daxCaption1()
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 2
        label.textColor = UIColor(designSystemColor: .textPrimary)
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }
}

private extension UnifiedToggleInputAttachmentErrorBannerView {

    enum Metrics {
        static let cornerRadius: CGFloat = 24
        static let horizontalPadding: CGFloat = 18
        static let iconSize: CGFloat = 24
        static let iconTextSpacing: CGFloat = 12
    }

    func setupUI() {
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        accessibilityTraits = .staticText

        addSubview(iconView)
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.iconTextSpacing),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applyColors()
    }

    func applyColors() {
        backgroundColor = UIColor(singleUseColor: .unifiedToggleInputAttachmentErrorBannerBackground)
        iconView.tintColor = UIColor(singleUseColor: .unifiedToggleInputAttachmentErrorIcon)
        messageLabel.textColor = UIColor(singleUseColor: .unifiedToggleInputAttachmentErrorText)
    }
}
