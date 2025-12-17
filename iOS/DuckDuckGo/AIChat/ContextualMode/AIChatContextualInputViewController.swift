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
    func contextualInputViewControllerDidTapAttach(_ viewController: AIChatContextualInputViewController)
}

// MARK: - View Controller

/// Container view controller that hosts the native input and handles keyboard adjustments.
final class AIChatContextualInputViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        static let horizontalPadding: CGFloat = 20
        static let quickActionsBottomSpacing: CGFloat = 12
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
        return view
    }()

    private var bottomConstraint: NSLayoutConstraint?

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
        configureNativeInput()
        configureQuickActions()
        registerForKeyboardNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        bottomConstraint?.constant = 0
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
}

// MARK: - Private Setup

private extension AIChatContextualInputViewController {

    func setupUI() {
        view.backgroundColor = .clear

        view.addSubview(quickActionsScrollView)
        quickActionsScrollView.addSubview(quickActionsView)
        embedNativeInputViewController()

        bottomConstraint = nativeInputViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        bottomConstraint?.priority = .defaultHigh

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

            nativeInputViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            nativeInputViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
            bottomConstraint!,
        ])
    }

    func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        let keyboardFrameInView = view.convert(endFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - keyboardFrameInView.minY)
        bottomConstraint?.constant = -overlap

        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) {
            self.view.layoutIfNeeded()
        }
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
        quickActionsView.configure(with: [.summarize])
    }

    func scrollQuickActionsToBottom() {
        view.layoutIfNeeded()
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, quickActionsScrollView.contentSize.height - quickActionsScrollView.bounds.height)
        )
        quickActionsScrollView.setContentOffset(bottomOffset, animated: false)
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

    func nativeInputViewControllerDidTapAttach(_ viewController: AIChatNativeInputViewController) {
        delegate?.contextualInputViewControllerDidTapAttach(self)
    }

    func nativeInputViewController(_ viewController: AIChatNativeInputViewController, didChangeText text: String) {
        scrollQuickActionsToBottom()
    }
}

