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

import UIKit

// MARK: - Delegate Protocol

/// Delegate for handling unified toggle input events at the coordinator/business-logic level.
/// The view controller translates raw view events into these higher-level callbacks.
protocol UnifiedToggleInputViewControllerDelegate: AnyObject {
    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String)
    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode)
    func unifiedToggleInputVCDidTapVoice(_ vc: UnifiedToggleInputViewController)
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

    private lazy var handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)

    // MARK: - Public API

    var text: String {
        get { inputBarView.text }
        set { inputBarView.text = newValue }
    }

    var isInputExpanded: Bool {
        inputBarView.isExpanded
    }

    var inputMode: TextEntryMode {
        inputBarView.inputMode
    }

    var isVoiceSearchAvailable: Bool {
        get { handler.isVoiceSearchEnabled }
        set {
            handler.isVoiceSearchEnabled = newValue
            inputBarView.isVoiceSearchAvailable = newValue
        }
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

    func activateInput() {
        inputBarView.becomeFirstResponder()
    }

    func deactivateInput() {
        inputBarView.resignFirstResponder()
    }

    // MARK: - Lifecycle

    override func loadView() {
        let barView = UnifiedToggleInputView(handler: handler)
        barView.delegate = self
        barView.onNeedsHierarchyLayout = { [weak self] in
            // Propagate layout to the containing hierarchy so sibling views
            // (e.g. the content container) animate in sync with the input bar.
            self?.view.window?.layoutIfNeeded()
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

    func unifiedToggleInputViewDidTapVoice(_ view: UnifiedToggleInputView) {
        delegate?.unifiedToggleInputVCDidTapVoice(self)
    }
}
