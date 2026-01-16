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

import AIChat
import Combine
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import OSLog
import SwiftUI
import UIKit

/// Delegate protocol for contextual sheet related actions
protocol AIChatContextualSheetViewControllerDelegate: AnyObject {

    /// Called when the user requests to load a URL externally (e.g., tapping a link)
    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestToLoad url: URL)

    /// Called when the sheet should be dismissed
    func aiChatContextualSheetViewControllerDidRequestDismiss(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user taps expand to open duck.ai in a new tab with the current chat URL
    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestExpandWithURL url: URL)

    /// Called when a new web view controller is created (for storing on the tab for persistence)
    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didCreateWebViewController webVC: AIChatContextualWebViewController)

    /// Called when the user requests to open AI Chat settings
    func aiChatContextualSheetViewControllerDidRequestOpenSettings(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user requests to open sync settings
    func aiChatContextualSheetViewControllerDidRequestOpenSyncSettings(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user taps the "Attach Page" button and context needs to be collected
    func aiChatContextualSheetViewControllerDidRequestAttachPage(_ viewController: AIChatContextualSheetViewController)
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

    // MARK: - Types

    /// Factory closure for creating web view controllers, eliminating prop drilling
    typealias WebViewControllerFactory = () -> AIChatContextualWebViewController

    // MARK: - Properties

    weak var delegate: AIChatContextualSheetViewControllerDelegate?

    private let viewModel: AIChatContextualSheetViewModel
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let webViewControllerFactory: WebViewControllerFactory
    private let settings: AIChatSettingsProvider
    private let onOpenSettings: () -> Void

    private lazy var contextualInputViewController = AIChatContextualInputViewController(voiceSearchHelper: voiceSearchHelper)
    private var cancellables = Set<AnyCancellable>()

    /// Existing web view controller passed in for an active chat session
    private var existingWebViewController: AIChatContextualWebViewController?

    /// Preloaded web view controller, created when sheet opens to reduce loading time on submit
    private var preloadedWebViewController: AIChatContextualWebViewController?

    /// The current active web view controller showing the chat
    private weak var currentWebViewController: AIChatContextualWebViewController?

    /// Hosting controller for the onboarding overlay
    private var onboardingHostingController: UIHostingController<AIChatContextualOnboardingView>?

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
        imageView.image = DesignSystemImages.Color.Size24.duckAI
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = UserText.duckAiFeatureName
        label.font = UIFont.daxHeadline()
        label.adjustsFontForContentSizeCategory = true
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

    init(viewModel: AIChatContextualSheetViewModel,
         voiceSearchHelper: VoiceSearchHelperProtocol,
         webViewControllerFactory: @escaping WebViewControllerFactory,
         existingWebViewController: AIChatContextualWebViewController? = nil,
         settings: AIChatSettingsProvider = AIChatSettings(),
         onOpenSettings: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.voiceSearchHelper = voiceSearchHelper
        self.webViewControllerFactory = webViewControllerFactory
        self.existingWebViewController = existingWebViewController
        self.settings = settings
        self.onOpenSettings = onOpenSettings
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
        bindViewModel()

        if let existingWebVC = existingWebViewController {
            existingWebVC.delegate = self
            existingWebVC.aiChatContentHandlingDelegate = self
            viewModel.setInitialContextualChatURL(existingWebVC.currentContextualChatURL)
            transitionToWebView(existingWebVC)
            expandToLargeDetent()
        } else {
            showContextualInput()
            preloadWebViewController()
            showOnboardingIfNeeded()
        }
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
        let url = viewModel.expandURL()
        Logger.aiChat.debug("[AIChatContextual] Expand tapped with URL: \(url.absoluteString)")
        delegate?.aiChatContextualSheetViewController(self, didRequestExpandWithURL: url)
    }

    @objc private func newChatButtonTapped() {
        viewModel.didStartNewChat()
        currentWebViewController?.startNewChat()
    }

    @objc private func closeButtonTapped() {
        delegate?.aiChatContextualSheetViewControllerDidRequestDismiss(self)
    }

    // MARK: - Public Methods

    /// Called when page context has been collected (after requesting attachment)
    func didReceivePageContext() {
        guard let chipView = viewModel.createContextChipView(onRemove: { [weak self] in
            self?.contextualInputViewController.hideContextChip()
        }) else { return }

        contextualInputViewController.showContextChip(chipView)
    }
}

// MARK: - Private Methods

private extension AIChatContextualSheetViewController {

    func showContextualInput() {
        contextualInputViewController.delegate = self
        configureAttachActions()
        embedChildViewController(contextualInputViewController)

        if viewModel.isAutomaticContextAttachmentEnabled {
            attachPageContext()
        }
    }

    func configureAttachActions() {
        let attachActions = viewModel.createAttachActions { [weak self] in
            self?.attachPageContext()
        }
        contextualInputViewController.attachActions = attachActions
    }

    func attachPageContext() {
        if let chipView = viewModel.createContextChipView(onRemove: { [weak self] in
            self?.contextualInputViewController.hideContextChip()
        }) {
            contextualInputViewController.showContextChip(chipView)
            return
        }

        delegate?.aiChatContextualSheetViewControllerDidRequestAttachPage(self)
    }

    func embedChildViewController(_ childVC: UIViewController) {
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

    func removeCurrentChildViewController() {
        children.forEach { child in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }

    func preloadWebViewController() {
        let webVC = webViewControllerFactory()
        webVC.delegate = self
        webVC.aiChatContentHandlingDelegate = self
        preloadedWebViewController = webVC
        webVC.loadViewIfNeeded()
    }

    func transitionToWebView(_ webVC: AIChatContextualWebViewController) {
        removeCurrentChildViewController()
        embedChildViewController(webVC)
        currentWebViewController = webVC
        existingWebViewController = nil
    }

    func showWebViewWithPrompt(_ prompt: String) {
        guard let webVC = preloadedWebViewController else { return }

        viewModel.didSubmitPrompt()

        let pageContext = contextualInputViewController.isContextChipVisible ? viewModel.fullPageContext : nil

        transitionToWebView(webVC)
        view.layoutIfNeeded()
        expandToLargeDetent()

        webVC.submitPrompt(prompt, pageContext: pageContext)
        delegate?.aiChatContextualSheetViewController(self, didCreateWebViewController: webVC)

        preloadedWebViewController = nil
    }

    func expandToLargeDetent() {
        guard let sheet = sheetPresentationController else { return }
        sheet.animateChanges {
            sheet.selectedDetentIdentifier = .large
        }
    }
}

// MARK: - AIChatContextualInputViewControllerDelegate

extension AIChatContextualSheetViewController: AIChatContextualInputViewControllerDelegate {

    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSubmitPrompt prompt: String) {
        showWebViewWithPrompt(prompt)
    }

    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSelectQuickAction action: AIChatContextualQuickAction) {
        showWebViewWithPrompt(action.prompt)
    }

    func contextualInputViewControllerDidTapVoice(_ viewController: AIChatContextualInputViewController) {
        let voiceSearchController = VoiceSearchViewController(preferredTarget: .AIChat, hideToggle: true)
        voiceSearchController.delegate = self
        voiceSearchController.modalTransitionStyle = .crossDissolve
        voiceSearchController.modalPresentationStyle = .overFullScreen
        present(voiceSearchController, animated: true)
    }

    func contextualInputViewControllerDidRemoveContextChip(_ viewController: AIChatContextualInputViewController) {
        viewModel.clearPageContext()
    }
}

// MARK: - VoiceSearchViewControllerDelegate

extension AIChatContextualSheetViewController: VoiceSearchViewControllerDelegate {

    func voiceSearchViewController(_ viewController: VoiceSearchViewController, didFinishQuery query: String?, target: VoiceSearchTarget) {
        viewController.dismiss(animated: true)
        if let query, !query.isEmpty {
            contextualInputViewController.setText(query)
        }
    }
}

// MARK: - AIChatContextualWebViewControllerDelegate

extension AIChatContextualSheetViewController: AIChatContextualWebViewControllerDelegate {

    func contextualWebViewController(_ viewController: AIChatContextualWebViewController, didRequestToLoad url: URL) {
        delegate?.aiChatContextualSheetViewController(self, didRequestToLoad: url)
    }

    func contextualWebViewController(_ viewController: AIChatContextualWebViewController, didUpdateContextualChatURL url: URL?) {
        Logger.aiChat.debug("[AIChatContextual] Received contextual chat URL update: \(String(describing: url?.absoluteString))")
        viewModel.didUpdateContextualChatURL(url)
    }
}

// MARK: - AIChatContentHandlingDelegate

extension AIChatContextualSheetViewController: AIChatContentHandlingDelegate {

    func aiChatContentHandlerDidReceiveOpenSettingsRequest(_ handler: AIChatContentHandling) {
        delegate?.aiChatContextualSheetViewControllerDidRequestOpenSettings(self)
    }

    func aiChatContentHandlerDidReceiveCloseChatRequest(_ handler: AIChatContentHandling) {
        delegate?.aiChatContextualSheetViewControllerDidRequestDismiss(self)
    }

    func aiChatContentHandlerDidReceiveOpenSyncSettingsRequest(_ handler: AIChatContentHandling) {
        delegate?.aiChatContextualSheetViewControllerDidRequestOpenSyncSettings(self)
    }

    func aiChatContentHandlerDidReceivePromptSubmission(_ handler: AIChatContentHandling) {
        viewModel.didSubmitPrompt()
    }
}

// MARK: - ViewModel Binding

private extension AIChatContextualSheetViewController {

    func bindViewModel() {
        viewModel.$isExpandEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                Logger.aiChat.debug("[AIChatContextual] Expand button state: enabled=\(isEnabled)")
                self?.expandButton.isEnabled = isEnabled
            }
            .store(in: &cancellables)

        viewModel.$isNewChatButtonVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                self?.newChatButton.isHidden = !isVisible
            }
            .store(in: &cancellables)
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
        sheet.selectedDetentIdentifier = .medium
        sheet.largestUndimmedDetentIdentifier = .medium
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.prefersGrabberVisible = true
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.preferredCornerRadius = Constants.sheetCornerRadius
    }
}

// MARK: - Onboarding

private extension AIChatContextualSheetViewController {

    func showOnboardingIfNeeded() {
        guard !settings.hasSeenContextualOnboarding else { return }

        isModalInPresentation = true
        Pixel.fire(pixel: .aiChatContextualOnboardingDisplayed)

        let onboardingView = AIChatContextualOnboardingView(
            onConfirm: { [weak self] in
                Pixel.fire(pixel: .aiChatContextualOnboardingConfirmPressed)
                self?.dismissOnboarding()
            },
            onViewSettings: { [weak self] in
                Pixel.fire(pixel: .aiChatContextualOnboardingSettingsPressed)
                self?.settings.markContextualOnboardingSeen()
                self?.onOpenSettings()
            }
        )

        let hostingController = UIHostingController(rootView: onboardingView)
        hostingController.view.backgroundColor = UIColor(designSystemColor: .backgroundTertiary)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.layer.cornerRadius = Constants.sheetCornerRadius
        hostingController.view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        hostingController.view.clipsToBounds = true

        addChild(hostingController)
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController.didMove(toParent: self)
        onboardingHostingController = hostingController
    }

    func dismissOnboarding(completion: (() -> Void)? = nil) {
        settings.markContextualOnboardingSeen()

        guard let hostingController = onboardingHostingController else {
            completion?()
            return
        }

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn) {
            hostingController.view.transform = CGAffineTransform(translationX: 0, y: hostingController.view.bounds.height)
        } completion: { [weak self] _ in
            hostingController.willMove(toParent: nil)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
            self?.onboardingHostingController = nil
            self?.isModalInPresentation = false
            completion?()
        }
    }
}
