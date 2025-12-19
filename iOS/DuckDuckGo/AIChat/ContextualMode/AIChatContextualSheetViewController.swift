//
//  AIChatContextualSheetViewController.swift
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

import DesignResourcesKitIcons
import UIKit

/// Delegate protocol for contextual sheet related actions
protocol AIChatContextualSheetViewControllerDelegate: AnyObject {
    
    /// Called when the user requests to load a URL externally (e.g., tapping a link)
    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestToLoad url: URL)

    /// Called when the sheet should be dismissed
    func aiChatContextualSheetViewControllerDidRequestDismiss(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user taps expand to open duck.ai in a new tab
    func aiChatContextualSheetViewControllerDidRequestExpand(_ viewController: AIChatContextualSheetViewController)
    
    /// Called when the user taps new chat to start a new contextual chat
    func aiChatContextualSheetViewControllerDidRequestNewChat(_ viewController: AIChatContextualSheetViewController)
}

/// Contextual sheet view controller. Configures UX and actions.
final class AIChatContextualSheetViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        static let headerTopPadding: CGFloat = 16
        static let headerHeight: CGFloat = 44
        static let headerButtonSize: CGFloat = 44
        static let headerHorizontalPadding: CGFloat = 8
        static let daxIconSize: CGFloat = 24
        static let titleSpacing: CGFloat = 8
        static let sheetCornerRadius: CGFloat = 24
        static let contentTopPadding: CGFloat = 8
    }

    // MARK: - Properties

    weak var delegate: AIChatContextualSheetViewControllerDelegate?

    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private lazy var contextualInputViewController = AIChatContextualInputViewController(voiceSearchHelper: voiceSearchHelper)

    // MARK: - UI Components

    private lazy var headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var leftButtonContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var leftButtonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var expandButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.expand, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textPrimary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(expandButtonTapped), for: .touchUpInside)
        button.accessibilityTraits = .button
        return button
    }()

    private lazy var newChatButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.aiChatAdd, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textPrimary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(newChatButtonTapped), for: .touchUpInside)
        button.accessibilityTraits = .button
        button.isHidden = true
        return button
    }()

    private lazy var titleContainer: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Constants.titleSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var daxIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = DesignSystemImages.Glyphs.Size24.duckDuckGoDaxColor
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = UserText.duckAiFeatureName
        label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        label.textColor = UIColor(designSystemColor: .textPrimary)
        return label
    }()

    private lazy var rightButtonContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.close, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textPrimary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        button.accessibilityTraits = .button
        return button
    }()

    private lazy var contentContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol) {
        self.voiceSearchHelper = voiceSearchHelper
        super.init(nibName: nil, bundle: nil)
        configureModalPresentation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        showContextualInput()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureSheetPresentation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateButtonContainerCornerRadii()
    }

    // MARK: - Actions

    @objc private func expandButtonTapped() {
        delegate?.aiChatContextualSheetViewControllerDidRequestExpand(self)
    }

    @objc private func newChatButtonTapped() {
        delegate?.aiChatContextualSheetViewControllerDidRequestNewChat(self)
    }

    @objc private func closeButtonTapped() {
        delegate?.aiChatContextualSheetViewControllerDidRequestDismiss(self)
    }

    // MARK: - Child View Controller Management

    private func showContextualInput() {
        contextualInputViewController.delegate = self
        embedChildViewController(contextualInputViewController)
    }

    private func embedChildViewController(_ childVC: UIViewController) {
        addChild(childVC)
        childVC.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(childVC.view)

        NSLayoutConstraint.activate([
            childVC.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            childVC.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            childVC.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            childVC.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])

        childVC.didMove(toParent: self)
    }
}

// MARK: - AIChatContextualInputViewControllerDelegate

extension AIChatContextualSheetViewController: AIChatContextualInputViewControllerDelegate {

    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSubmitPrompt prompt: String) {
    }

    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSelectQuickAction action: AIChatContextualQuickAction) {
        contextualInputViewController(viewController, didSubmitPrompt: action.prompt)
    }

    func contextualInputViewControllerDidTapVoice(_ viewController: AIChatContextualInputViewController) {
    }

    func contextualInputViewControllerDidTapAttach(_ viewController: AIChatContextualInputViewController) {
    }
}

// MARK: - Private UI Setup Methods
private extension AIChatContextualSheetViewController {
    
    func setupUI() {
        view.backgroundColor = UIColor(designSystemColor: .backgroundTertiary)

        view.addSubview(headerView)

        headerView.addSubview(leftButtonContainer)
        leftButtonContainer.addSubview(leftButtonStack)
        leftButtonStack.addArrangedSubview(expandButton)
        leftButtonStack.addArrangedSubview(newChatButton)

        headerView.addSubview(titleContainer)
        titleContainer.addArrangedSubview(daxIcon)
        titleContainer.addArrangedSubview(titleLabel)

        headerView.addSubview(rightButtonContainer)
        rightButtonContainer.addSubview(closeButton)

        view.addSubview(contentContainerView)

        setupConstraints()
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor, constant: Constants.headerTopPadding),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Constants.headerHeight),

            leftButtonContainer.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: Constants.headerHorizontalPadding),
            leftButtonContainer.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            leftButtonStack.topAnchor.constraint(equalTo: leftButtonContainer.topAnchor),
            leftButtonStack.leadingAnchor.constraint(equalTo: leftButtonContainer.leadingAnchor),
            leftButtonStack.trailingAnchor.constraint(equalTo: leftButtonContainer.trailingAnchor),
            leftButtonStack.bottomAnchor.constraint(equalTo: leftButtonContainer.bottomAnchor),

            expandButton.widthAnchor.constraint(equalToConstant: Constants.headerButtonSize),
            expandButton.heightAnchor.constraint(equalToConstant: Constants.headerButtonSize),

            newChatButton.widthAnchor.constraint(equalToConstant: Constants.headerButtonSize),
            newChatButton.heightAnchor.constraint(equalToConstant: Constants.headerButtonSize),

            titleContainer.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleContainer.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            daxIcon.widthAnchor.constraint(equalToConstant: Constants.daxIconSize),
            daxIcon.heightAnchor.constraint(equalToConstant: Constants.daxIconSize),

            rightButtonContainer.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -Constants.headerHorizontalPadding),
            rightButtonContainer.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            closeButton.topAnchor.constraint(equalTo: rightButtonContainer.topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: rightButtonContainer.leadingAnchor),
            closeButton.trailingAnchor.constraint(equalTo: rightButtonContainer.trailingAnchor),
            closeButton.bottomAnchor.constraint(equalTo: rightButtonContainer.bottomAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Constants.headerButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Constants.headerButtonSize),

            contentContainerView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: Constants.contentTopPadding),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    func updateButtonContainerCornerRadii() {
        let leftHeight = leftButtonContainer.bounds.height
        leftButtonContainer.layer.cornerRadius = leftHeight / 2

        let rightHeight = rightButtonContainer.bounds.height
        rightButtonContainer.layer.cornerRadius = rightHeight / 2
    }
    
    func configureModalPresentation() {
        modalPresentationStyle = .pageSheet
    }

    func configureSheetPresentation() {
        guard let sheet = sheetPresentationController else { return }

        sheet.detents = [.medium(), .large()]
        sheet.largestUndimmedDetentIdentifier = .medium
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.prefersGrabberVisible = true
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.preferredCornerRadius = Constants.sheetCornerRadius
    }
}
