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
    func unifiedToggleInputVCDidTapDismiss(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapAttach(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachment id: UUID)
    func unifiedToggleInputVCDidChangeAttachments(_ vc: UnifiedToggleInputViewController)
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
    lazy var handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false, isToggleEnabled: isToggleEnabled)

    // MARK: - Public API

    init(isToggleEnabled: Bool) {
        self.isToggleEnabled = isToggleEnabled
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

    var showsDismissButton: Bool {
        get { inputBarView.showsDismissButton }
        set { inputBarView.showsDismissButton = newValue }
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

    var isGenerating: Bool = false {
        didSet {
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

    var isModelChipHidden: Bool {
        get { inputBarView.isModelChipHidden }
        set { inputBarView.isModelChipHidden = newValue }
    }

    var isImageButtonHidden: Bool {
        get { inputBarView.isImageButtonHidden }
        set { inputBarView.isImageButtonHidden = newValue }
    }

    var isCustomizeResponsesButtonHidden: Bool {
        get { inputBarView.isCustomizeResponsesButtonHidden }
        set { inputBarView.isCustomizeResponsesButtonHidden = newValue }
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
        showsDismissButton = config.showsDismissButton
        isToolbarSubmitHidden = config.isToolbarSubmitHidden
        isTopBarPosition = config.isTopBarPosition
        setInputMode(config.inputMode, animated: animated)
        setInactiveCardAppearance(config.inactiveAppearance)
        setExpanded(config.isExpanded, animated: animated)
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        inputBarView.setExpanded(expanded, animated: animated)
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool) {
        inputBarView.setInputMode(mode, animated: animated)
    }

    func selectAllText() {
        inputBarView.selectAllText()
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

    // MARK: - Lifecycle

    override func loadView() {
        let barView = UnifiedToggleInputView(handler: handler, isToggleEnabled: isToggleEnabled)
        barView.delegate = self
        barView.onNeedsHierarchyLayout = { [weak self] in
            self?.view.window?.layoutIfNeeded()
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

    func unifiedToggleInputViewDidTapDismiss(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidTapDismiss(self)
    }
}
