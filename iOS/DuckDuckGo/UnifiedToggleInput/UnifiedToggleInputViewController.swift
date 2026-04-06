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
import os.log
import UIKit

private let utiLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.duckduckgo", category: "UTI")

// MARK: - Delegate Protocol

/// Delegate for handling unified toggle input events at the coordinator/business-logic level.
/// The view controller translates raw view events into these higher-level callbacks.
protocol UnifiedToggleInputViewControllerDelegate: AnyObject {
    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode)
    func unifiedToggleInputVCDidTapSearchGoTo(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidTapAttach(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachment id: UUID)
    func unifiedToggleInputVCDidChangeAttachments(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVCDidChangeHeight(_ vc: UnifiedToggleInputViewController)
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
        utiLog.debug("InputVC.init - isToggleEnabled: \(isToggleEnabled, privacy: .public)")
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
            utiLog.debug("InputVC.isVoiceSearchAvailable.set - \(self.handler.isVoiceSearchEnabled, privacy: .public) → \(newValue, privacy: .public)")
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
            utiLog.debug("InputVC.isGenerating.didSet - \(oldValue, privacy: .public) → \(self.isGenerating, privacy: .public)")
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
        utiLog.debug("InputVC.addAttachment - id: \(attachment.id, privacy: .public)")
        inputBarView.addAttachment(attachment)
    }

    func removeAttachment(id: UUID) {
        utiLog.debug("InputVC.removeAttachment - id: \(id, privacy: .public)")
        inputBarView.removeAttachment(id: id)
    }

    func removeAllAttachments() {
        utiLog.debug("InputVC.removeAllAttachments")
        inputBarView.removeAllAttachments()
    }

    func apply(_ config: UTIViewConfig, animated: Bool) {
        utiLog.debug("InputVC.apply - config: \(String(describing: config), privacy: .public), animated: \(animated, privacy: .public)")
        utiLog.debug("InputVC.apply → setting cardPosition=\(String(describing: config.cardPosition), privacy: .public)")
        cardPosition = config.cardPosition
        utiLog.debug("InputVC.apply → setting usesOmnibarMargins=\(config.usesOmnibarMargins, privacy: .public)")
        usesOmnibarMargins = config.usesOmnibarMargins
        utiLog.debug("InputVC.apply → setting isToolbarSubmitHidden=\(config.isToolbarSubmitHidden, privacy: .public)")
        isToolbarSubmitHidden = config.isToolbarSubmitHidden
        utiLog.debug("InputVC.apply → setting isTopBarPosition=\(config.isTopBarPosition, privacy: .public)")
        isTopBarPosition = config.isTopBarPosition
        utiLog.debug("InputVC.apply → calling setInputMode(\(String(describing: config.inputMode), privacy: .public))")
        setInputMode(config.inputMode, animated: animated)
        utiLog.debug("InputVC.apply → calling setInactiveCardAppearance(\(config.inactiveAppearance, privacy: .public))")
        setInactiveCardAppearance(config.inactiveAppearance)
        utiLog.debug("InputVC.apply → calling setExpanded(\(config.isExpanded, privacy: .public))")
        setExpanded(config.isExpanded, animated: animated)
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        utiLog.debug("InputVC.setExpanded - expanded: \(expanded, privacy: .public), animated: \(animated, privacy: .public)")
        inputBarView.setExpanded(expanded, animated: animated)
    }

    func setExpandedWithToggleHidden(_ expanded: Bool) {
        utiLog.debug("InputVC.setExpandedWithToggleHidden - expanded: \(expanded, privacy: .public)")
        inputBarView.setExpandedWithToggleHidden(expanded)
    }

    func animateToggleReveal(additionalAnimations: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        utiLog.debug("InputVC.animateToggleReveal → forwarding to inputBarView")
        inputBarView.animateToggleReveal(additionalAnimations: additionalAnimations, completion: completion)
    }

    func animateToggleHide(additionalAnimations: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        utiLog.debug("InputVC.animateToggleHide → forwarding to inputBarView")
        inputBarView.animateToggleHide(additionalAnimations: additionalAnimations, completion: completion)
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool) {
        utiLog.debug("InputVC.setInputMode - mode: \(String(describing: mode), privacy: .public), animated: \(animated, privacy: .public)")
        inputBarView.setInputMode(mode, animated: animated)
    }

    func selectAllText() {
        utiLog.debug("InputVC.selectAllText")
        inputBarView.selectAllText()
    }

    func updateToggleEnabled(_ enabled: Bool) {
        utiLog.debug("InputVC.updateToggleEnabled - enabled: \(enabled, privacy: .public)")
        handler.isToggleEnabled = enabled
        inputBarView.updateToggleEnabled(enabled)
    }

    func setInactiveCardAppearance(_ inactive: Bool) {
        utiLog.debug("InputVC.setInactiveCardAppearance - inactive: \(inactive, privacy: .public)")
        inputBarView.setInactiveCardAppearance(inactive)
    }

    func activateInput() {
        utiLog.debug("InputVC.activateInput")
        utiLog.debug("InputVC.activateInput → calling inputBarView.becomeFirstResponder")
        inputBarView.becomeFirstResponder()
    }

    func deactivateInput() {
        utiLog.debug("InputVC.deactivateInput")
        utiLog.debug("InputVC.deactivateInput → calling inputBarView.resignFirstResponder")
        inputBarView.resignFirstResponder()
    }

    // MARK: - Lifecycle

    override func loadView() {
        utiLog.debug("InputVC.loadView")
        let barView = UnifiedToggleInputView(handler: handler, isToggleEnabled: isToggleEnabled)
        barView.delegate = self
        barView.onNeedsHierarchyLayout = { [weak self] in
            guard let self else {
                utiLog.debug("InputVC.onNeedsHierarchyLayout ↩️ guard: self is nil")
                return
            }
            utiLog.debug("InputVC.onNeedsHierarchyLayout → calling delegate.didChangeHeight")
            self.view.window?.layoutIfNeeded()
            self.delegate?.unifiedToggleInputVCDidChangeHeight(self)
        }
        barView.onAttachTapped = { [weak self] in
            guard let self else {
                utiLog.debug("InputVC.onAttachTapped ↩️ guard: self is nil")
                return
            }
            utiLog.debug("InputVC.onAttachTapped → calling delegate.didTapAttach")
            delegate?.unifiedToggleInputVCDidTapAttach(self)
        }
        barView.onAttachmentRemoved = { [weak self] id in
            guard let self else {
                utiLog.debug("InputVC.onAttachmentRemoved ↩️ guard: self is nil")
                return
            }
            utiLog.debug("InputVC.onAttachmentRemoved → calling delegate.didRemoveAttachment(\(id, privacy: .public))")
            delegate?.unifiedToggleInputVC(self, didRemoveAttachment: id)
        }
        barView.onAttachmentsLayoutDidChange = { [weak self] in
            guard let self else {
                utiLog.debug("InputVC.onAttachmentsLayoutDidChange ↩️ guard: self is nil")
                return
            }
            utiLog.debug("InputVC.onAttachmentsLayoutDidChange → calling delegate.didChangeAttachments")
            delegate?.unifiedToggleInputVCDidChangeAttachments(self)
        }
        view = barView
    }
}

// MARK: - UnifiedToggleInputViewDelegate

extension UnifiedToggleInputViewController: UnifiedToggleInputViewDelegate {

    func unifiedToggleInputViewDidTapWhileCollapsed(_ view: UnifiedToggleInputView) {
        utiLog.debug("InputVC.unifiedToggleInputViewDidTapWhileCollapsed → calling delegate.didTapWhileCollapsed")
        delegate?.unifiedToggleInputVCDidTapWhileCollapsed(self)
    }

    func unifiedToggleInputViewDidSubmitText(_ view: UnifiedToggleInputView, text: String, mode: TextEntryMode) {
        utiLog.debug("InputVC.unifiedToggleInputViewDidSubmitText → calling delegate.didSubmitText, mode=\(String(describing: mode), privacy: .public)")
        delegate?.unifiedToggleInputVC(self, didSubmitText: text, mode: mode)
    }

    func unifiedToggleInputViewDidChangeText(_ view: UnifiedToggleInputView, text: String) {
        utiLog.debug("InputVC.unifiedToggleInputViewDidChangeText → calling delegate.didChangeText")
        delegate?.unifiedToggleInputVC(self, didChangeText: text)
    }

    func unifiedToggleInputViewDidChangeMode(_ view: UnifiedToggleInputView, mode: TextEntryMode) {
        utiLog.debug("InputVC.unifiedToggleInputViewDidChangeMode → calling delegate.didChangeMode(\(String(describing: mode), privacy: .public))")
        delegate?.unifiedToggleInputVC(self, didChangeMode: mode)
    }

    func unifiedToggleInputViewDidTapSearchGoTo(_ view: UnifiedToggleInputView) {
        utiLog.debug("InputVC.unifiedToggleInputViewDidTapSearchGoTo → calling delegate.didTapSearchGoTo")
        delegate?.unifiedToggleInputVCDidTapSearchGoTo(self)
    }
}
