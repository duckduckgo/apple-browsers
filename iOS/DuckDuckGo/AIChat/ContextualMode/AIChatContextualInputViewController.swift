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
import DesignResourcesKit
import DesignResourcesKitIcons
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
        static let iPadBottomPadding: CGFloat = 16
    }

    // MARK: - Properties

    weak var delegate: AIChatContextualInputViewControllerDelegate?

    private let isContextualSheetImprovementsEnabled: Bool
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

    private lazy var welcomeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var welcomeCenterYConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol, isContextualSheetImprovementsEnabled: Bool = false) {
        self.isContextualSheetImprovementsEnabled = isContextualSheetImprovementsEnabled
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateWelcomeLabelCentering()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBottomPaddingForOrientation()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateBottomPaddingForOrientation()
        })
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

    func setText(_ text: String) {
        nativeInputViewController.setText(text)
    }

    func appendText(_ text: String) {
        nativeInputViewController.appendText(text)
    }

    func showContextChip(_ chipView: UIView) {
        nativeInputViewController.showContextChip(chipView)
        updateQuickActions()
    }

    func hideContextChip() {
        nativeInputViewController.hideContextChip()
        updateQuickActions()
    }

    func updateContextChipState(_ state: AIChatContextChipView.State) {
        nativeInputViewController.updateContextChipState(state)
    }

    func setChipTapCallback(_ callback: @escaping () -> Void) {
        nativeInputViewController.setChipTapCallback(callback)
    }
}

// MARK: - Private Setup

private extension AIChatContextualInputViewController {

    func setupUI() {
        view.backgroundColor = .clear

        if isContextualSheetImprovementsEnabled {
            setupImprovedUI()
        } else {
            setupOriginalUI()
        }
    }

    func setupOriginalUI() {
        view.addSubview(quickActionsScrollView)
        quickActionsScrollView.addSubview(quickActionsView)
        embedNativeInputViewController()

        bottomConstraint = nativeInputViewController.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)

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
            bottomConstraint!,
        ])
    }

    func setupImprovedUI() {
        view.addSubview(quickActionsScrollView)
        quickActionsScrollView.addSubview(quickActionsView)
        view.addSubview(welcomeLabel)
        embedNativeInputViewController()

        configureWelcomeLabel()

        bottomConstraint = nativeInputViewController.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)

        let centerY = welcomeLabel.centerYAnchor.constraint(equalTo: view.topAnchor)
        welcomeCenterYConstraint = centerY

        NSLayoutConstraint.activate([
            // Scroll view wraps quick actions at natural size, pinned above input
            quickActionsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            quickActionsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
            quickActionsScrollView.bottomAnchor.constraint(equalTo: nativeInputViewController.view.topAnchor, constant: -Constants.quickActionsBottomSpacing),

            quickActionsView.topAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.topAnchor),
            quickActionsView.leadingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.leadingAnchor),
            quickActionsView.trailingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.trailingAnchor),
            quickActionsView.bottomAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.bottomAnchor),
            quickActionsView.widthAnchor.constraint(equalTo: quickActionsScrollView.frameLayoutGuide.widthAnchor),
            quickActionsScrollView.frameLayoutGuide.heightAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.heightAnchor),

            // Welcome label centered horizontally, vertical position set dynamically
            centerY,
            welcomeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            welcomeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            welcomeLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Constants.horizontalPadding),

            nativeInputViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            nativeInputViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
            bottomConstraint!,
        ])
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
        let actions: [AIChatContextualQuickAction] = [.summarize]
        quickActionsView.configure(with: actions)
    }

    func configureWelcomeLabel() {
        let font = UIFont(name: "DuckSansDisplay-Medium", size: 25) ?? UIFont.daxTitle2()
        let privatelyColor = UIColor(designSystemColor: .shieldPrivacy)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(designSystemColor: .textPrimary),
            .paragraphStyle: paragraphStyle
        ]

        let mutableText = NSMutableAttributedString(string: UserText.aiChatWelcomeAskAnything, attributes: defaultAttributes)

        let shieldImage = DesignSystemImages.Color.Size42.shieldUtility
        let iconAttachment = NSTextAttachment()
        iconAttachment.image = shieldImage
        let iconVerticalOffset = (font.capHeight - shieldImage.size.height) / 2
        iconAttachment.bounds = CGRect(x: 0, y: iconVerticalOffset, width: shieldImage.size.width, height: shieldImage.size.height)
        mutableText.append(NSAttributedString(attachment: iconAttachment))

        let privatelyAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: privatelyColor,
            .paragraphStyle: paragraphStyle
        ]
        mutableText.append(NSAttributedString(string: UserText.aiChatWelcomePrivately, attributes: privatelyAttributes))

        welcomeLabel.attributedText = mutableText
    }

    func updateWelcomeLabelCentering() {
        guard isContextualSheetImprovementsEnabled else { return }
        let scrollViewTop = quickActionsScrollView.frame.minY
        guard scrollViewTop > 0 else { return }
        welcomeCenterYConstraint?.constant = scrollViewTop / 2
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

    @objc func keyboardWillShow(_ notification: Notification) {
        bottomConstraint?.constant = -Constants.keyboardSpacing
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        bottomConstraint?.constant = bottomPaddingForOrientation()
    }

    func updateBottomPaddingForOrientation() {
        bottomConstraint?.constant = bottomPaddingForOrientation()
    }

    func bottomPaddingForOrientation() -> CGFloat {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return 0 }
        return -Constants.iPadBottomPadding
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
