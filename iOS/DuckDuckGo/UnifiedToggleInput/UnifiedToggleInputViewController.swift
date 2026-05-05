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
import UIKit

// MARK: - Delegate Protocol

/// Delegate for handling unified toggle input events at the coordinator/business-logic level.
/// The view controller translates raw view events into these higher-level callbacks.
protocol UnifiedToggleInputViewControllerDelegate: AnyObject {
    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode)
    func unifiedToggleInputVCDidTapSearchGoTo(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidClearSelectedTool(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapAttach(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachment id: UUID)
    func unifiedToggleInputVCDidChangeAttachments(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidChangeHeight(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapInlineDismiss(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapAIChatShortcut(_ vc: UnifiedToggleInputViewController)
}

// MARK: - View Controller

/// Manages the `UnifiedToggleInputView` lifecycle and acts as its delegate.
/// Provides a typed API for the coordinator to drive the view without direct view access.
final class UnifiedToggleInputViewController: UIViewController {

    // MARK: - Properties

    weak var delegate: UnifiedToggleInputViewControllerDelegate?

    private var inputBarView: UnifiedToggleInputView {
        // swiftlint:disable:next force_cast
        view as! UnifiedToggleInputView
    }

    let isToggleEnabled: Bool
    let handler: UnifiedToggleInputHandler

    // MARK: - Public API

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

    var isInputExpanded: Bool {
        inputBarView.isExpanded
    }

    var isInputFirstResponder: Bool {
        inputBarView.isFirstResponder
    }

    var inputMode: TextEntryMode {
        inputBarView.inputMode
    }

    var attachButtonView: UIView { inputBarView.attachButtonView }

    var isVoiceSearchAvailable: Bool {
        get { handler.isVoiceSearchEnabled }
        set {
            handler.isVoiceSearchEnabled = newValue
            inputBarView.isVoiceSearchAvailable = newValue
        }
    }

    var cardPosition: UnifiedToggleInputCardPosition {
        get { inputBarView.cardPosition }
        set { inputBarView.cardPosition = newValue }
    }

    var usesOmnibarMargins: Bool {
        get { inputBarView.usesOmnibarMargins }
        set { inputBarView.usesOmnibarMargins = newValue }
    }

    var isTopBarPosition: Bool {
        get { inputBarView.handlerIsTopBarPosition }
        set { inputBarView.handlerIsTopBarPosition = newValue }
    }

    var isToolbarSubmitHidden: Bool {
        get { inputBarView.isToolbarSubmitHidden }
        set { inputBarView.isToolbarSubmitHidden = newValue }
    }

    var isToolbarAIVoiceChatActive: Bool {
        get { inputBarView.isToolbarAIVoiceChatActive }
        set { inputBarView.isToolbarAIVoiceChatActive = newValue }
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

    var toolsMenu: UIMenu? {
        get { inputBarView.toolsMenu }
        set { inputBarView.toolsMenu = newValue }
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

    var isImageButtonHidden: Bool {
        get { inputBarView.isImageButtonHidden }
        set { inputBarView.isImageButtonHidden = newValue }
    }

    var isImageButtonEnabled: Bool {
        get { inputBarView.isImageButtonEnabled }
        set { inputBarView.isImageButtonEnabled = newValue }
    }

    var modelSupportsImageAttachments: Bool {
        get { inputBarView.modelSupportsImageAttachments }
        set { inputBarView.modelSupportsImageAttachments = newValue }
    }

    var isAttachmentsFull: Bool {
        inputBarView.isAttachmentsFull
    }

    var currentAttachments: [AIChatImageAttachment] {
        inputBarView.currentAttachments
    }

    func addAttachment(_ attachment: AIChatImageAttachment) {
        inputBarView.addAttachment(attachment)
    }

    func removeAttachment(id: UUID) {
        inputBarView.removeAttachment(id: id)
    }

    func removeAllAttachments() {
        inputBarView.removeAllAttachments()
    }

    func apply(_ config: UTIViewConfig, animated: Bool) {
        cardPosition = config.cardPosition
        usesOmnibarMargins = config.usesOmnibarMargins
        isToolbarSubmitHidden = config.isToolbarSubmitHidden
        isTopBarPosition = config.isTopBarPosition
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
    func alignPlaceholderHorizontally(toWindowX windowX: CGFloat) -> CGFloat {
        inputBarView.alignPlaceholderHorizontally(toWindowX: windowX)
    }

    func updateToggleEnabled(_ enabled: Bool) {
        handler.isToggleEnabled = enabled
        inputBarView.updateToggleEnabled(enabled)
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
        let barView = UnifiedToggleInputView(handler: handler, isToggleEnabled: isToggleEnabled)
        barView.delegate = self
        barView.onNeedsHierarchyLayout = { [weak self] in
            guard let self else { return }
            self.view.window?.layoutIfNeeded()
            self.delegate?.unifiedToggleInputVCDidChangeHeight(self)
        }
        barView.onAttachTapped = { [weak self] in
            guard let self else { return }
            delegate?.unifiedToggleInputVCDidTapAttach(self)
        }
        barView.onAttachmentRemoved = { [weak self] id in
            guard let self else { return }
            delegate?.unifiedToggleInputVC(self, didRemoveAttachment: id)
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
        view = barView
    }
}

// MARK: - UnifiedToggleInputViewDelegate

extension UnifiedToggleInputViewController: UnifiedToggleInputViewDelegate {

    func unifiedToggleInputViewDidTapWhileCollapsed(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidTapWhileCollapsed(self)
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

    func unifiedToggleInputViewDidTapSearchGoTo(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidTapSearchGoTo(self)
    }

    func unifiedToggleInputViewDidClearSelectedTool(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidClearSelectedTool(self)
    }
}
