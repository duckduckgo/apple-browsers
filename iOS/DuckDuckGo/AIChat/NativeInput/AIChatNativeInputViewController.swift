//
//  AIChatNativeInputViewController.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Delegate protocol for handling user interactions with the native input view controller.
protocol AIChatNativeInputViewControllerDelegate: AnyObject {
    func nativeInputViewController(_ viewController: AIChatNativeInputViewController, didSubmitPrompt prompt: String)
    func nativeInputViewControllerDidTapVoice(_ viewController: AIChatNativeInputViewController)
    func nativeInputViewControllerDidTapClear(_ viewController: AIChatNativeInputViewController)
    func nativeInputViewControllerDidRemoveContextChip(_ viewController: AIChatNativeInputViewController)
    func nativeInputViewController(_ viewController: AIChatNativeInputViewController, didChangeText text: String)
}

// MARK: - Default Implementations

extension AIChatNativeInputViewControllerDelegate {
    func nativeInputViewControllerDidTapClear(_ viewController: AIChatNativeInputViewController) {}
    func nativeInputViewControllerDidRemoveContextChip(_ viewController: AIChatNativeInputViewController) {}
    func nativeInputViewController(_ viewController: AIChatNativeInputViewController, didChangeText text: String) {}
}

// MARK: - View Controller

/// View controller that wraps the native input view and manages voice search availability.
final class AIChatNativeInputViewController: UIViewController {

    // MARK: - Properties

    weak var delegate: AIChatNativeInputViewControllerDelegate?

    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let nativeInputView = AIChatNativeInputView()

    var text: String {
        get { nativeInputView.text }
        set { nativeInputView.text = newValue }
    }

    var placeholder: String {
        get { nativeInputView.placeholder }
        set { nativeInputView.placeholder = newValue }
    }

    var isAttachButtonHidden: Bool {
        get { nativeInputView.isAttachButtonHidden }
        set { nativeInputView.isAttachButtonHidden = newValue }
    }

    var isContextChipVisible: Bool {
        nativeInputView.isContextChipVisible
    }

    var attachActions: [AIChatAttachAction] {
        get { nativeInputView.attachActions }
        set { nativeInputView.attachActions = newValue }
    }

    func setText(_ text: String) {
        nativeInputView.setText(text)
    }

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol) {
        self.voiceSearchHelper = voiceSearchHelper
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateVoiceButtonState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateVoiceButtonState()
    }

    // MARK: - Public Methods

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return nativeInputView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        return nativeInputView.resignFirstResponder()
    }

    func showContextChip(_ chipView: UIView, animated: Bool = true) {
        nativeInputView.showContextChip(chipView, animated: animated)
    }

    func hideContextChip(animated: Bool = true) {
        nativeInputView.hideContextChip(animated: animated)
    }
}

// MARK: - Private Setup

private extension AIChatNativeInputViewController {

    func setupUI() {
        view.backgroundColor = .clear

        nativeInputView.delegate = self
        nativeInputView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nativeInputView)

        NSLayoutConstraint.activate([
            nativeInputView.topAnchor.constraint(equalTo: view.topAnchor),
            nativeInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nativeInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nativeInputView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func updateVoiceButtonState() {
        nativeInputView.isVoiceButtonEnabled = voiceSearchHelper.isVoiceSearchEnabled
    }
}

// MARK: - AIChatNativeInputViewDelegate

extension AIChatNativeInputViewController: AIChatNativeInputViewDelegate {

    func nativeInputViewDidChangeText(_ view: AIChatNativeInputView, text: String) {
        delegate?.nativeInputViewController(self, didChangeText: text)
    }

    func nativeInputViewDidTapSubmit(_ view: AIChatNativeInputView, text: String) {
        delegate?.nativeInputViewController(self, didSubmitPrompt: text)
    }

    func nativeInputViewDidTapVoice(_ view: AIChatNativeInputView) {
        delegate?.nativeInputViewControllerDidTapVoice(self)
    }

    func nativeInputViewDidTapClear(_ view: AIChatNativeInputView) {
        delegate?.nativeInputViewControllerDidTapClear(self)
    }

    func nativeInputViewDidRemoveContextChip(_ view: AIChatNativeInputView) {
        delegate?.nativeInputViewControllerDidRemoveContextChip(self)
    }

    func nativeInputViewNeedsLayout(_ view: AIChatNativeInputView) {
        self.view.superview?.layoutIfNeeded()
    }
}
