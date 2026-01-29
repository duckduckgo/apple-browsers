//
//  AIChatContextualInputViewController.swift
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

/// Delegate protocol for handling user interactions with the contextual input view controller.
protocol AIChatContextualInputViewControllerDelegate: AnyObject {
    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSubmitPrompt prompt: String)
    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSelectQuickAction action: AIChatContextualQuickAction)
    func contextualInputViewControllerDidTapVoice(_ viewController: AIChatContextualInputViewController)
    func contextualInputViewControllerDidRemoveContextChip(_ viewController: AIChatContextualInputViewController)
}

// MARK: - View Controller

/// Container view controller that hosts the native input and handles keyboard adjustments.
final class AIChatContextualInputViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        static let horizontalPadding: CGFloat = 20
        static let quickActionsBottomSpacing: CGFloat = 12
        static let keyboardSpacing: CGFloat = 20
    }

    // MARK: - Properties

    weak var delegate: AIChatContextualInputViewControllerDelegate?

    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private lazy var nativeInputViewController = AIChatNativeInputViewController(voiceSearchHelper: voiceSearchHelper)

    private lazy var quickActionsScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var quickActionsView: AIChatQuickActionsView<AIChatContextualQuickAction> = {
        let view = AIChatQuickActionsView<AIChatContextualQuickAction>()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }()

    private var safeAreaBottomConstraint: NSLayoutConstraint?
    private var keyboardBottomConstraint: NSLayoutConstraint?

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol) {
        self.voiceSearchHelper = voiceSearchHelper
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureNativeInput()
        configureQuickActions()
        setupKeyboardObservers()
    }

    // MARK: - Public Methods

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return nativeInputViewController.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        return nativeInputViewController.resignFirstResponder()
    }

    var isContextChipVisible: Bool {
        nativeInputViewController.isContextChipVisible
    }

    var attachActions: [AIChatAttachAction] {
        get { nativeInputViewController.attachActions }
        set { nativeInputViewController.attachActions = newValue }
    }

    func setText(_ text: String) {
        nativeInputViewController.setText(text)
    }

    func showContextChip(_ chipView: UIView, animated: Bool = true) {
        nativeInputViewController.showContextChip(chipView, animated: animated)
        updateQuickActions()
    }

    func hideContextChip(animated: Bool = true) {
        nativeInputViewController.hideContextChip(animated: animated)
        updateQuickActions()
    }

    func updateContextChip(title: String, favicon: UIImage?) {
        nativeInputViewController.updateContextChip(title: title, favicon: favicon)
    }
}

// MARK: - Private Setup

private extension AIChatContextualInputViewController {

    func setupUI() {
        view.backgroundColor = .clear

        view.addSubview(quickActionsScrollView)
        quickActionsScrollView.addSubview(quickActionsView)
        embedNativeInputViewController()

        NSLayoutConstraint.activate([
            quickActionsScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            quickActionsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            quickActionsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
            quickActionsScrollView.bottomAnchor.constraint(equalTo: nativeInputViewController.view.topAnchor, constant: -Constants.quickActionsBottomSpacing),

            quickActionsView.topAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.topAnchor),
            quickActionsView.leadingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.leadingAnchor),
            quickActionsView.trailingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.trailingAnchor),
            quickActionsView.bottomAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.bottomAnchor),
            quickActionsView.widthAnchor.constraint(equalTo: quickActionsScrollView.frameLayoutGuide.widthAnchor),
            quickActionsView.heightAnchor.constraint(greaterThanOrEqualTo: quickActionsScrollView.frameLayoutGuide.heightAnchor),

            nativeInputViewController.view.topAnchor.constraint(greaterThanOrEqualTo: quickActionsView.bottomAnchor, constant: Constants.quickActionsBottomSpacing),
            nativeInputViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            nativeInputViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
            nativeInputViewController.view.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        safeAreaBottomConstraint = nativeInputViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        safeAreaBottomConstraint?.isActive = true
    }

    func embedNativeInputViewController() {
        addChild(nativeInputViewController)
        nativeInputViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nativeInputViewController.view)
        nativeInputViewController.didMove(toParent: self)
    }

    func configureNativeInput() {
        nativeInputViewController.delegate = self
        nativeInputViewController.placeholder = UserText.searchInputFieldPlaceholderDuckAI
    }

    func configureQuickActions() {
        quickActionsView.onActionSelected = { [weak self] action in
            guard let self else { return }
            delegate?.contextualInputViewController(self, didSelectQuickAction: action)
        }
        updateQuickActions()
    }

    internal func updateQuickActions() {
        let actions: [AIChatContextualQuickAction] = if isContextChipVisible {
            [.summarize]
        } else {
            [.summarize, .attachPageContent]
        }
        quickActionsView.configure(with: actions)
    }

    func scrollQuickActionsToBottom() {
        view.layoutIfNeeded()
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, quickActionsScrollView.contentSize.height - quickActionsScrollView.bounds.height)
        )
        quickActionsScrollView.setContentOffset(bottomOffset, animated: false)
    }

    func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    // Note: UIKeyboardLayoutGuide has known issues on first appearance in sheets.
    // The layout frame isn't properly initialized until after the view has appeared.
    // We use a safe area constraint initially, then switch to keyboard layout guide when the keyboard appears.
    //
    // Related references:
    // - https://useyourloaf.com/blog/keyboard-layout-guide/
    // - https://developer.apple.com/forums/thread/746826

    @objc func keyboardWillShow(_ notification: Notification) {
        if keyboardBottomConstraint == nil {
            safeAreaBottomConstraint?.isActive = false
            keyboardBottomConstraint = nativeInputViewController.view.bottomAnchor.constraint(
                equalTo: view.keyboardLayoutGuide.topAnchor,
                constant: -Constants.keyboardSpacing
            )
            keyboardBottomConstraint?.isActive = true
        } else {
            keyboardBottomConstraint?.constant = -Constants.keyboardSpacing
        }
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        keyboardBottomConstraint?.constant = 0
    }
}

// MARK: - AIChatNativeInputViewControllerDelegate

extension AIChatContextualInputViewController: AIChatNativeInputViewControllerDelegate {

    func nativeInputViewController(_ viewController: AIChatNativeInputViewController, didSubmitPrompt prompt: String) {
        delegate?.contextualInputViewController(self, didSubmitPrompt: prompt)
    }

    func nativeInputViewControllerDidTapVoice(_ viewController: AIChatNativeInputViewController) {
        delegate?.contextualInputViewControllerDidTapVoice(self)
    }

    func nativeInputViewControllerDidRemoveContextChip(_ viewController: AIChatNativeInputViewController) {
        delegate?.contextualInputViewControllerDidRemoveContextChip(self)
    }

    func nativeInputViewController(_ viewController: AIChatNativeInputViewController, didChangeText text: String) {
        scrollQuickActionsToBottom()
    }
}
