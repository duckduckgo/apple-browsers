//
//  AIChatBasicNativeInputViewController.swift
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

/// Delegate protocol for handling user interactions with the basic native input view controller.
protocol AIChatBasicNativeInputViewControllerDelegate: AnyObject {
    func basicNativeInputViewController(_ viewController: AIChatBasicNativeInputViewController, didSubmitPrompt prompt: String)
    func basicNativeInputViewControllerDidTapVoice(_ viewController: AIChatBasicNativeInputViewController)
    func basicNativeInputViewControllerDidTapClear(_ viewController: AIChatBasicNativeInputViewController)
    func basicNativeInputViewControllerDidRemoveContextChip(_ viewController: AIChatBasicNativeInputViewController)
    func basicNativeInputViewController(_ viewController: AIChatBasicNativeInputViewController, didChangeText text: String)
}

// MARK: - Default Implementations

extension AIChatBasicNativeInputViewControllerDelegate {
    func basicNativeInputViewControllerDidTapClear(_ viewController: AIChatBasicNativeInputViewController) {}
    func basicNativeInputViewControllerDidRemoveContextChip(_ viewController: AIChatBasicNativeInputViewController) {}
    func basicNativeInputViewController(_ viewController: AIChatBasicNativeInputViewController, didChangeText text: String) {}
}

// MARK: - View Controller

/// View controller that wraps the basic native input view and manages voice search availability.
final class AIChatBasicNativeInputViewController: UIViewController {

    // MARK: - Properties

    weak var delegate: AIChatBasicNativeInputViewControllerDelegate?

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

    var isContextChipVisible: Bool {
        nativeInputView.isContextChipVisible
    }

    func setText(_ text: String) {
        nativeInputView.setText(text)
    }

    func appendText(_ text: String) {
        nativeInputView.appendText(text)
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

    func showContextChip(_ chipView: UIView) {
        nativeInputView.showContextChip(chipView)
    }

    func hideContextChip() {
        nativeInputView.hideContextChip()
    }

    func updateContextChipState(_ state: AIChatContextChipView.State) {
        nativeInputView.updateContextChipState(state)
    }

    func setChipTapCallback(_ callback: @escaping () -> Void) {
        nativeInputView.setChipTapCallback(callback)
    }
}

// MARK: - Private Setup

private extension AIChatBasicNativeInputViewController {

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

extension AIChatBasicNativeInputViewController: AIChatNativeInputViewDelegate {

    func nativeInputViewDidChangeText(_ view: AIChatNativeInputView, text: String) {
        delegate?.basicNativeInputViewController(self, didChangeText: text)
    }

    func nativeInputViewDidTapSubmit(_ view: AIChatNativeInputView, text: String) {
        delegate?.basicNativeInputViewController(self, didSubmitPrompt: text)
    }

    func nativeInputViewDidTapVoice(_ view: AIChatNativeInputView) {
        delegate?.basicNativeInputViewControllerDidTapVoice(self)
    }

    func nativeInputViewDidTapClear(_ view: AIChatNativeInputView) {
        delegate?.basicNativeInputViewControllerDidTapClear(self)
    }

    func nativeInputViewDidRemoveContextChip(_ view: AIChatNativeInputView) {
        delegate?.basicNativeInputViewControllerDidRemoveContextChip(self)
    }

    func nativeInputViewNeedsLayout(_ view: AIChatNativeInputView) {
        self.view.superview?.layoutIfNeeded()
    }
}
