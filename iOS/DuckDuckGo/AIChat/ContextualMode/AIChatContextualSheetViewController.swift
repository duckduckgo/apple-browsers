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
import Lottie
import OSLog
import PrivacyConfig
import SwiftUI
import UIKit

/// Delegate protocol for contextual sheet related actions
@MainActor
protocol AIChatContextualSheetViewControllerDelegate: AnyObject {

    /// Called when the user requests to load a URL externally (e.g., tapping a link)
    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestToLoad url: URL)

    /// Called when the sheet should be dismissed
    func aiChatContextualSheetViewControllerDidRequestDismiss(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user taps expand to open duck.ai in a new tab with the current chat URL
    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestExpandWithURL url: URL)

    /// Called when the user requests to open AI Chat settings
    func aiChatContextualSheetViewControllerDidRequestOpenSettings(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user requests to open sync settings
    func aiChatContextualSheetViewControllerDidRequestOpenSyncSettings(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user taps the "Attach Page" button and context needs to be collected
    func aiChatContextualSheetViewControllerDidRequestAttachPage(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user removes the context chip and it should downgrade to placeholder
    func aiChatContextualSheetViewControllerDidRequestRemoveChip(_ viewController: AIChatContextualSheetViewController)

    /// Called when the contextual chat URL changes (e.g., user gets a chatID after prompt submission)
    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didUpdateContextualChatURL url: URL?)

    /// Called when the user requests to open a downloaded file
    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestOpenDownloadWithFileName fileName: String)

    /// Called when the sheet has been dismissed (either by user action or programmatically)
    func aiChatContextualSheetViewControllerDidDismiss(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user taps the "New Chat" button to start a fresh conversation
    func aiChatContextualSheetViewControllerDidRequestNewChat(_ viewController: AIChatContextualSheetViewController)

    /// Called when the user submits a prompt from native input
    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didSubmitPrompt prompt: String)

    /// Called when the user confirms chat deletion from the fire button confirmation
    func aiChatContextualSheetViewControllerDidConfirmDeleteChat(_ viewController: AIChatContextualSheetViewController)
}

/// Contextual sheet view controller. Configures UX and actions.
final class AIChatContextualSheetViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        static let headerTopPadding: CGFloat = 16
        static let headerHeight: CGFloat = 44
        static let headerButtonSize: CGFloat = 44
        static let headerHorizontalPadding: CGFloat = 16
        static let daxIconSize: CGFloat = 24
        static let titleSpacing: CGFloat = 8
        static let sheetCornerRadius: CGFloat = 24
        static let contentTopPadding: CGFloat = 8
        static let dimmingAlpha: CGFloat = 0.3
    }

    // MARK: - Types

    /// Factory closure for creating web view controllers, eliminating prop drilling
    typealias WebViewControllerFactory = () -> AIChatContextualWebViewController?

    // MARK: - Properties

    weak var delegate: AIChatContextualSheetViewControllerDelegate?

    private let sessionState: AIChatContextualChatSessionState
    private let aiChatSettings: AIChatSettingsProvider
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let webViewControllerFactory: WebViewControllerFactory
    private let pixelHandler: AIChatContextualModePixelFiring
    private let appSettings: AppSettings
    private let featureFlagger: FeatureFlagger

    private lazy var contextualInputViewController = AIChatContextualInputViewController(voiceSearchHelper: voiceSearchHelper)
    private var cancellables = Set<AnyCancellable>()

    /// The single web view controller for this sheet, created once and reused
    private var webViewController: AIChatContextualWebViewController?

    /// Whether the web view is currently visible (vs native input being visible)
    private var isWebViewVisible = false

    /// Tracks the current sheet detent for syncing with web view
    private var isCurrentlyMediumDetent = true

    /// Dimming view added to the presenting view controller's view for contrast
    private var dimmingView: UIView?

    /// Whether the fire confirmation is currently shown
    private var isShowingFireConfirmation = false

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

    private lazy var rightButtonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var fireButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.fire, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textPrimary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(fireButtonTapped), for: .touchUpInside)
        button.accessibilityTraits = .button
        return button
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

    private lazy var topSeparator: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .lines)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Initialization

    init(sessionState: AIChatContextualChatSessionState,
         aiChatSettings: AIChatSettingsProvider,
         voiceSearchHelper: VoiceSearchHelperProtocol,
         webViewControllerFactory: @escaping WebViewControllerFactory,
         pixelHandler: AIChatContextualModePixelFiring,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.sessionState = sessionState
        self.aiChatSettings = aiChatSettings
        self.voiceSearchHelper = voiceSearchHelper
        self.webViewControllerFactory = webViewControllerFactory
        self.pixelHandler = pixelHandler
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
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
        createAndConfigureWebViewController(restoreURL: sessionState.contextualChatURL)
        bindViewModel()
    }

    /// Creates a web VC and starts loading the appropriate URL.
    /// - Parameter restoreURL: If provided, loads this URL (for restoring an existing chat). If nil, loads the default contextual URL.
    private func createAndConfigureWebViewController(restoreURL: URL? = nil) {
        guard let webVC = webViewControllerFactory() else {
            Logger.aiChat.debug("[SheetVC] Failed to create web VC from factory")
            return
        }

        webVC.delegate = self
        webVC.aiChatContentHandlingDelegate = self

        // Use provided restore URL, or default contextual URL for new chat
        webVC.initialURL = restoreURL ?? aiChatSettings.aiChatURL.appendingParameter(name: "placement", value: "sidebar")

        webViewController = webVC
        webVC.loadViewIfNeeded()

        if restoreURL != nil {
            pixelHandler.fireSessionRestored()
        }

        Logger.aiChat.debug("[SheetVC] Web VC created with URL: \(webVC.initialURL?.absoluteString ?? "nil")")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureSheetPresentation()
        pixelHandler.fireSheetOpened()
        addKeyboardObserver()
        showDimmingView(animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.endEditing(true)
        removeKeyboardObserver()
        pixelHandler.fireSheetDismissed()
        hideDimmingView(animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateButtonContainerCornerRadii()
        updateShadowPath()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    // MARK: - Actions

    @objc private func expandButtonTapped() {
        pixelHandler.fireExpandButtonTapped()
        let url = sessionState.contextualChatURL ?? aiChatSettings.aiChatURL
        Logger.aiChat.debug("[AIChatContextual] Expand tapped with URL: \(url.absoluteString)")
        delegate?.aiChatContextualSheetViewController(self, didRequestExpandWithURL: url)
    }

    @objc private func newChatButtonTapped() {
        pixelHandler.fireNewChatButtonTapped()
        delegate?.aiChatContextualSheetViewControllerDidRequestNewChat(self)
    }

    @objc private func fireButtonTapped() {
        showFireConfirmation()
    }

    @objc private func closeButtonTapped() {
        delegate?.aiChatContextualSheetViewControllerDidRequestDismiss(self)
    }

}

// MARK: - Private Methods

private extension AIChatContextualSheetViewController {

    func showContextualInput() {
        contextualInputViewController.delegate = self
        embedChildViewController(contextualInputViewController)
    }

    func showNativeInputUI() {
        removeCurrentChildViewController()
        showContextualInput()
        updateChipUI(chipState: sessionState.chipState)
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

    func transitionToWebView() {
        guard let webVC = webViewController else { return }
        removeCurrentChildViewController()
        embedChildViewController(webVC)
        isWebViewVisible = true
    }

    func showWebViewWithPrompt(_ prompt: String, pageContext: AIChatPageContextData?) {
        Logger.aiChat.debug("[SheetVC] showWebViewWithPrompt called")

        guard let webVC = webViewController else {
            Logger.aiChat.debug("[SheetVC] showWebViewWithPrompt - no web VC available")
            return
        }

        // Don't transition immediately - wait for delegate callback after prompt is submitted
        // This prevents showing the initial duck.ai page before the prompt navigates it
        webVC.submitPrompt(prompt, pageContext: pageContext)
        expandToLargeDetent()
    }

    func expandToLargeDetent() {
        guard let sheet = sheetPresentationController else { return }
        sheet.animateChanges {
            sheet.selectedDetentIdentifier = .large
        }
    }

    /// Called when user taps the X button on a chip.
    /// For attached chips: downgrade to placeholder state.
    /// For placeholder chips: do nothing (X is hidden, placeholder can never be removed).
    private func handleChipRemoved() {
        delegate?.aiChatContextualSheetViewControllerDidRequestRemoveChip(self)
    }

    func updateChipUI(chipState: ChipState) {
        switch chipState {
        case .placeholder:
            if contextualInputViewController.isContextChipVisible {
                contextualInputViewController.updateContextChipState(.placeholder)
                contextualInputViewController.setChipTapCallback { [weak self] in
                    guard let self else { return }
                    self.pixelHandler.firePageContextPlaceholderTapped()
                    self.delegate?.aiChatContextualSheetViewControllerDidRequestAttachPage(self)
                }
            } else {
                let chipView = createPlaceholderChipView(
                    onTapToAttach: { [weak self] in
                        guard let self else { return }
                        self.pixelHandler.firePageContextPlaceholderTapped()
                        self.delegate?.aiChatContextualSheetViewControllerDidRequestAttachPage(self)
                    },
                    onRemove: { [weak self] in
                        self?.handleChipRemoved()
                    }
                )
                contextualInputViewController.showContextChip(chipView)
                pixelHandler.firePageContextPlaceholderShown()
            }
        case .attached(let context):
            if contextualInputViewController.isContextChipVisible {
                contextualInputViewController.updateContextChipState(.attached(title: context.title, favicon: context.favicon))
            } else {
                let chipView = createContextChipView(context: context, onRemove: { [weak self] in
                    self?.handleChipRemoved()
                })
                contextualInputViewController.showContextChip(chipView)
            }
        }
    }

    func createPlaceholderChipView(onTapToAttach: @escaping () -> Void, onRemove: @escaping () -> Void) -> AIChatContextChipView {
        let chipView = AIChatContextChipView()
        chipView.configure(state: .placeholder)
        chipView.onTapToAttach = onTapToAttach
        chipView.onRemove = onRemove
        return chipView
    }

    func createContextChipView(context: AIChatPageContext, onRemove: @escaping () -> Void) -> AIChatContextChipView {
        let chipView = AIChatContextChipView()
        chipView.configure(state: .attached(title: context.title, favicon: context.favicon))
        chipView.onRemove = onRemove
        return chipView
    }

    // MARK: - Fire Confirmation

    func showFireConfirmation() {
        isShowingFireConfirmation = true
        expandToLargeDetent()

        let viewModel = ScopedFireConfirmationViewModel(
            tabViewModel: nil,
            source: .browsing,
            fireContext: .contextualChat(onDelete: { [weak self] in
                self?.handleDeleteChatConfirmed()
            }),
            browsingMode: .normal,
            onConfirm: { _ in },
            onCancel: { [weak self] in
                self?.dismissFireConfirmation()
            }
        )

        let confirmationView = ScopedFireConfirmationView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: confirmationView)
        hostingController.view.backgroundColor = UIColor(designSystemColor: .backgroundTertiary)
        hostingController.modalTransitionStyle = .coverVertical
        hostingController.modalPresentationStyle = .pageSheet

        if let sheet = hostingController.sheetPresentationController {
            if #available(iOS 16.0, *) {
                let sizingController = UIHostingController(rootView: confirmationView)
                sizingController.disableSafeArea()
                let contentHeight = sizingController.sizeThatFits(in: CGSize(width: view.frame.width, height: .infinity)).height
                sheet.detents = [.custom { context in
                    min(contentHeight, context.maximumDetentValue * 0.9)
                }]
            } else {
                sheet.detents = [.large()]
            }
            sheet.prefersGrabberVisible = false
            if #unavailable(iOS 26) {
                sheet.preferredCornerRadius = 24
            }
        }

        present(hostingController, animated: true)
    }

    func dismissFireConfirmation() {
        isShowingFireConfirmation = false
        dismiss(animated: true)
    }

    func handleDeleteChatConfirmed() {
        isShowingFireConfirmation = false
        dismiss(animated: true) { [weak self] in
            self?.playFireAnimationAndDismiss()
        }
    }

    func playFireAnimationAndDismiss() {
        let animationType = appSettings.currentFireButtonAnimation
        guard let composition = animationType.composition else {
            delegate?.aiChatContextualSheetViewControllerDidConfirmDeleteChat(self)
            return
        }

        let animationView = LottieAnimationView(animation: composition)
        animationView.contentMode = .scaleAspectFill
        animationView.animationSpeed = CGFloat(animationType.speed)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animationView)

        NSLayoutConstraint.activate([
            animationView.topAnchor.constraint(equalTo: view.topAnchor),
            animationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            animationView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        animationView.play(fromProgress: 0, toProgress: 1) { [weak self] _ in
            guard let self else { return }
            self.delegate?.aiChatContextualSheetViewControllerDidConfirmDeleteChat(self)
        }
    }
}

// MARK: - AIChatContextualInputViewControllerDelegate

extension AIChatContextualSheetViewController: AIChatContextualInputViewControllerDelegate {

    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSubmitPrompt prompt: String) {
        delegate?.aiChatContextualSheetViewController(self, didSubmitPrompt: prompt)
    }

    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSelectQuickAction action: AIChatContextualQuickAction) {
        switch action {
        case .summarize:
            pixelHandler.fireQuickActionSummarizeSelected()
            delegate?.aiChatContextualSheetViewControllerDidRequestAttachPage(self)
        }
        if !action.prompt.isEmpty {
            contextualInputViewController.appendText(action.prompt)
        }
    }

    func contextualInputViewControllerDidTapVoice(_ viewController: AIChatContextualInputViewController) {
        let voiceSearchController = VoiceSearchViewController(preferredTarget: .AIChat, hideToggle: true)
        voiceSearchController.delegate = self
        voiceSearchController.modalTransitionStyle = .crossDissolve
        voiceSearchController.modalPresentationStyle = .overFullScreen
        present(voiceSearchController, animated: true)
    }

    func contextualInputViewControllerDidRemoveContextChip(_ viewController: AIChatContextualInputViewController) {
        handleChipRemoved()
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
        delegate?.aiChatContextualSheetViewController(self, didUpdateContextualChatURL: url)
    }

    func contextualWebViewController(_ viewController: AIChatContextualWebViewController, didRequestOpenDownloadWithFileName fileName: String) {
        delegate?.aiChatContextualSheetViewController(self, didRequestOpenDownloadWithFileName: fileName)
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
        // Coordinator handles state transitions
    }

    func aiChatContentHandlerDidReceivePageContextRequest(_ handler: AIChatContentHandling) {
        webViewController?.markFrontendAsReady()
    }
}

// MARK: - ViewModel Binding

private extension AIChatContextualSheetViewController {

    func bindViewModel() {
        sessionState.$viewState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] viewState in
                self?.apply(viewState)
            }
            .store(in: &cancellables)

        sessionState.effects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] effect in
                self?.apply(effect)
            }
            .store(in: &cancellables)
    }

    func apply(_ viewState: SheetViewState) {
        expandButton.isEnabled = viewState.isExpandButtonEnabled
        newChatButton.isHidden = !viewState.shouldShowNewChatButton

        switch viewState.content {
        case .nativeInput:
            // When returning to native input (new chat), reload the default URL on existing web VC
            if isWebViewVisible, let webVC = webViewController {
                let defaultURL = aiChatSettings.aiChatURL.appendingParameter(name: "placement", value: "sidebar")
                webVC.loadChatURL(defaultURL)
                isWebViewVisible = false
            }
            if contextualInputViewController.parent != nil {
                updateChipUI(chipState: viewState.chipState)
            } else {
                showNativeInputUI()
            }
        case .webView:
            // Web VC was created in viewDidLoad, just show it if not already visible
            if !isWebViewVisible {
                transitionToWebView()
            }
        }

    }

    func apply(_ effect: SheetEffect) {
        switch effect {
        case .submitPrompt(let prompt, let context):
            showWebViewWithPrompt(prompt, pageContext: context)
        case .reloadWebView:
            webViewController?.reload()
        case .pushContextToFrontend(let context):
            webViewController?.pushPageContext(context)
        case .clearPrompt:
            contextualInputViewController.setText("")
        }
    }
}

// MARK: - Private UI Setup Methods
private extension AIChatContextualSheetViewController {
    
    func setupUI() {
        view.backgroundColor = UIColor(Color(singleUseColor: .duckAIContextualSheetBackground))

        view.layer.cornerRadius = Constants.sheetCornerRadius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // Top corners only

        view.layer.shadowColor = UIColor(designSystemColor: .shadowPrimary).cgColor
        view.layer.shadowOpacity = 0.08
        view.layer.shadowOffset = CGSize(width: 0, height: -3)
        view.layer.shadowRadius = 10
        view.layer.masksToBounds = false

        view.addSubview(topSeparator)

        view.addSubview(headerView)

        headerView.addSubview(leftButtonContainer)
        leftButtonContainer.addSubview(leftButtonStack)
        leftButtonStack.addArrangedSubview(expandButton)
        leftButtonStack.addArrangedSubview(newChatButton)

        headerView.addSubview(titleContainer)
        titleContainer.addArrangedSubview(daxIcon)
        titleContainer.addArrangedSubview(titleLabel)

        headerView.addSubview(rightButtonContainer)
        rightButtonContainer.addSubview(rightButtonStack)
        if featureFlagger.isFeatureOn(for: FeatureFlag.aiChatContextualFireButton) {
            rightButtonStack.addArrangedSubview(fireButton)
            NSLayoutConstraint.activate([
                fireButton.widthAnchor.constraint(equalToConstant: Constants.headerButtonSize),
                fireButton.heightAnchor.constraint(equalToConstant: Constants.headerButtonSize),
            ])
        }
        rightButtonStack.addArrangedSubview(closeButton)

        view.addSubview(contentContainerView)

        setupConstraints()
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([

            topSeparator.topAnchor.constraint(equalTo: view.topAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

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

            rightButtonStack.topAnchor.constraint(equalTo: rightButtonContainer.topAnchor),
            rightButtonStack.leadingAnchor.constraint(equalTo: rightButtonContainer.leadingAnchor),
            rightButtonStack.trailingAnchor.constraint(equalTo: rightButtonContainer.trailingAnchor),
            rightButtonStack.bottomAnchor.constraint(equalTo: rightButtonContainer.bottomAnchor),

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

    func updateShadowPath() {
        let shadowPath = UIBezierPath(
            roundedRect: view.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: Constants.sheetCornerRadius, height: Constants.sheetCornerRadius)
        )
        view.layer.shadowPath = shadowPath.cgPath
    }

    func configureModalPresentation() {
        modalPresentationStyle = .pageSheet
    }

    func showDimmingView(animated: Bool) {
        guard let presentingView = presentingViewController?.view else { return }

        if dimmingView == nil {
            let dimView = UIView()
            dimView.backgroundColor = .black
            dimView.isUserInteractionEnabled = false
            dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            dimView.frame = presentingView.bounds
            dimmingView = dimView
        }

        guard let dimmingView else { return }
        dimmingView.alpha = 0
        presentingView.addSubview(dimmingView)

        let animations = { dimmingView.alpha = Constants.dimmingAlpha }
        if animated {
            UIView.animate(withDuration: 0.3, animations: animations)
        } else {
            animations()
        }
    }

    func hideDimmingView(animated: Bool) {
        guard let dimmingView else { return }
        let animations = { dimmingView.alpha = 0 }
        let completion = { (_: Bool) in dimmingView.removeFromSuperview() }
        if animated {
            UIView.animate(withDuration: 0.3, animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }

    func addKeyboardObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sheetKeyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
    }

    func removeKeyboardObserver() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
    }

    @objc func sheetKeyboardWillShow() {
        if isWebViewVisible && isCurrentlyMediumDetent {
            expandToLargeDetent()
        }
    }

    func configureSheetPresentation() {
        guard let sheet = sheetPresentationController else { return }

        sheet.delegate = self
        presentationController?.delegate = self
        sheet.detents = [.medium(), .large()]
        sheet.selectedDetentIdentifier = .medium
        sheet.largestUndimmedDetentIdentifier = .medium
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.prefersGrabberVisible = true
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.preferredCornerRadius = Constants.sheetCornerRadius
    }
}

// MARK: - UISheetPresentationControllerDelegate

extension AIChatContextualSheetViewController: UISheetPresentationControllerDelegate {

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        isCurrentlyMediumDetent = sheetPresentationController.selectedDetentIdentifier == .medium
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        delegate?.aiChatContextualSheetViewControllerDidDismiss(self)
    }
}
