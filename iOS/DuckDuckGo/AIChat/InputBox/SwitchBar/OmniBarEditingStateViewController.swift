//
//  OmniBarEditingStateViewController.swift
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

import UIKit
import DesignResourcesKit
import Combine
import PrivacyConfig
import Bookmarks
import Persistence
import History
import Core
import Suggestions
import SwiftUI
import AIChat
import RemoteMessaging

protocol OmniBarEditingStateViewControllerDelegate: AnyObject {
    func onQueryUpdated(_ query: String)
    func onQuerySubmitted(_ query: String)
    func onPromptSubmitted(_ query: String, tools: [AIChatRAGTool]?)
    func onSelectFavorite(_ favorite: BookmarkEntity)
    func onEditFavorite(_ favorite: BookmarkEntity)
    func onSelectSuggestion(_ suggestion: Suggestion)
    func onVoiceSearchRequested(from mode: TextEntryMode)
    func onChatHistorySelected(url: URL)
    func onDismissRequested()
    func onSwitchToTab(_ tab: Tab)
    func onTabSwitcherRequested()
    func onTryFireModeRequested()
    func onToggleModeSwitched(to mode: TextEntryMode)
    func onVoiceModeRequested()
}

/// Main coordinator for the OmniBar editing state, managing multiple specialized components
final class OmniBarEditingStateViewController: UIViewController, OmniBarEditingStateTransitioning {

    // MARK: - Properties

    var actionBarView: UIView? { navigationActionBarManager?.view }

    var suggestionTrayDependencies: SuggestionTrayDependencies?

    weak var delegate: OmniBarEditingStateViewControllerDelegate?
    var automaticallySelectsTextOnAppear = false
    var useNewTransitionBehaviour = false

    /// Container used for swipe/fade-out content stack (search/chat/history/Dax content).
    var contentStackContainerView: UIView {
        contentContainerView
    }

    /// Anchor below the switch bar, used when mounting additional content without covering omnibar controls.
    var contentStackTopAnchor: NSLayoutYAxisAnchor {
        switchBarVC.view.bottomAnchor
    }

    /// Anchor above the switch bar, used when mounting content for bottom address bar mode.
    var contentStackBottomAnchor: NSLayoutYAxisAnchor {
        switchBarVC.view.topAnchor
    }

    /// Distance between the segmented Search/Duck.ai toggle and the address bar input.
    var addressBarToToggleSpacing: CGFloat {
        switchBarVC.addressBarToToggleSpacing
    }

    var isUsingTopBarPositionForLayout: Bool {
        isUsingTopBarPosition
    }

    // MARK: - Core Components
    private lazy var contentContainerView = UIView()

    private lazy var bottomLocationSwitchBarBackgroundMaskView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.backgroundColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    private var isUsingTopBarPosition: Bool
    private var isLandscapeOrientation: Bool = false {
        didSet {
            isUsingTopBarPosition = appSettings.currentAddressBarPosition == .top || isLandscapeOrientation
            switchBarHandler.updateBarPosition(isTop: isUsingTopBarPosition)
        }
    }
    private var isAdjustedForTopBar: Bool

    lazy var switchBarVC = SwitchBarViewController(switchBarHandler: switchBarHandler,
                                                   showsSeparator: !isUsingTopBarPosition,
                                                   reduceTopPaddings: !isUsingTopBarPosition)

    private weak var contentContainerViewLeadingConstraint: NSLayoutConstraint?
    private weak var contentContainerViewTrailingConstraint: NSLayoutConstraint?

    let appSettings: AppSettings
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let aiChatSettings: AIChatSettingsProvider
    private let voiceShortcutFeature: DuckAIVoiceShortcutFeatureProviding
    private let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?

    // MARK: - Manager Components

    private var swipeContainerManager: SwipeContainerManager?
    private var navigationActionBarManager: NavigationActionBarManager?
    private var suggestionTrayManager: SuggestionTrayManager?
    private var aiChatHistoryManager: AIChatHistoryManager?
    /// Held in a dedicated property (not `cancellables`) so each new chat-history install
    /// auto-cancels the previous subscription on assignment — avoids stale viewModels firing.
    private var chatHistoryHasSuggestionsCancellable: AnyCancellable?
    private var isShowingURLFallback = false

    private var chatHasResults: Bool {
        aiChatHistoryManager?.hasSuggestions ?? false
    }

    private var shouldShowURLFallback: Bool {
        !chatHasResults && !switchBarHandler.currentText.isBlank
    }
    private let daxLogoManager: DaxLogoManager
    private var notificationCancellable: AnyCancellable?
    private let switchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding

    // MARK: - Escape Hatch
    private var escapeHatchModel: EscapeHatchModel?

    /// When true, the Dax logo view is not added to the hierarchy during `installDaxLogoView()`.
    /// Used by the chat-path onboarding completion flow so the logo never flashes during the
    /// editing-state transition. Cleared on the first `setLogoHidden(false)` call, which also
    /// installs the view lazily so later visibility updates work as normal.
    private var isDaxLogoInstallSuppressed = false

    private weak var contentAnimator: UIViewPropertyAnimator?

    // MARK: - Initialization

    internal init(switchBarHandler: any SwitchBarHandling,
                  switchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding = SwitchBarSubmissionMetrics(),
                  appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
                  featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
                  privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
                  aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
                  voiceShortcutFeature: DuckAIVoiceShortcutFeatureProviding = DuckAIVoiceShortcutFeature(),
                  duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
                  escapeHatchModel: EscapeHatchModel? = nil,
                  initialLogoHidden: Bool = false) {
        self.switchBarHandler = switchBarHandler
        self.switchBarSubmissionMetrics = switchBarSubmissionMetrics
        self.isDaxLogoInstallSuppressed = initialLogoHidden
        self.daxLogoManager = DaxLogoManager(isFireTab: switchBarHandler.isFireTab)
        if initialLogoHidden {
            self.daxLogoManager.setForcedHidden(true)
        }
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.aiChatSettings = aiChatSettings
        self.voiceShortcutFeature = voiceShortcutFeature
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
        self.escapeHatchModel = escapeHatchModel
        self.isUsingTopBarPosition = appSettings.currentAddressBarPosition == .top || isLandscapeOrientation
        self.isAdjustedForTopBar = self.isUsingTopBarPosition

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        if switchBarHandler.isUsingFadeOutAnimation {
            switchBarHandler.updateBarPosition(isTop: isUsingTopBarPosition)
        }
        setupView()
        installComponents()
        setupSubscriptions()
        observeRemoteMessagesChanges()

        suggestionTrayManager?.showInitialSuggestions()

        updateDaxVisibility()
        updateSwipeContainerSafeArea()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if aiChatHistoryManager == nil {
            installChatHistoryList()
        }

        switchBarVC.focusTextField()
        if automaticallySelectsTextOnAppear {
            DispatchQueue.main.async {
                self.switchBarVC.textEntryViewController.selectAllText()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DailyPixel.fireDailyAndCount(pixel: .aiChatInternalSwitchBarDisplayed)
        DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarShown)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        aiChatHistoryManager?.tearDown()
        aiChatHistoryManager = nil
    }

    // MARK: - Public Methods

    @objc func dismissAnimated(_ completion: (() -> Void)? = nil) {
        if self.presentingViewController != nil {
            self.dismiss(animated: true, completion: completion)
        }
    }

    var isEscapeHatchCardVisible: Bool {
        escapeHatchModel != nil
    }

    func setLogoYOffset(_ offset: CGFloat) {
        daxLogoManager.setLogoYOffset(offset)
    }

    func setLogoHidden(_ hidden: Bool) {
        // If we suppressed the initial install (chat-path EOJ handoff), lazily install the Dax now
        // so subsequent visibility updates can show it normally.
        if !hidden && isDaxLogoInstallSuppressed {
            isDaxLogoInstallSuppressed = false
            if isViewLoaded {
                installDaxLogoView()
            }
        }
        daxLogoManager.setForcedHidden(hidden)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        adjustLayoutForViewSize(view.bounds.size)
    }

    private func requiresHorizontallyCompactLayout(for size: CGSize) -> Bool {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        return isPhone && size.width > size.height
    }

    private func adjustLayoutForViewSize(_ size: CGSize) {

        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: size)
        self.isLandscapeOrientation = isHorizontallyCompactLayoutEnabled

        let horizontalMargin: CGFloat = isHorizontallyCompactLayoutEnabled ? Constants.horizontalMarginForCompactLayout : 0
        self.contentContainerViewLeadingConstraint?.constant = horizontalMargin
        self.contentContainerViewTrailingConstraint?.constant = -horizontalMargin
        self.updateDaxVisibility()
        self.updateLayoutForCurrentOrientation()

        self.navigationActionBarManager?.navigationActionBarViewController?.isShowingGradient = !isHorizontallyCompactLayoutEnabled && isUsingTopBarPosition
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { _ in
            self.adjustLayoutForViewSize(size)
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Private Methods

    private func setupView() {
        setUpContentContainer()

        view.backgroundColor = Constants.backgroundColor
    }

    private func setUpContentContainer() {
        view.addSubview(contentContainerView)
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false

        contentContainerViewLeadingConstraint = contentContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        contentContainerViewLeadingConstraint?.isActive = true
        contentContainerViewTrailingConstraint = contentContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        contentContainerViewTrailingConstraint?.isActive = true

        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func installComponents() {
        installSwitchBarVC()
        installSwipeContainer()
        installSuggestionsTray()
        installChatHistoryList()
        installDaxLogoView()
        installNavigationActionBar()

        contentContainerView.bringSubviewToFront(switchBarVC.view)
    }

    private func installSwitchBarVC() {
        addChild(switchBarVC)
        let container = contentContainerView
        container.addSubview(switchBarVC.view)
        switchBarVC.view.translatesAutoresizingMaskIntoConstraints = false
        switchBarVC.view.setContentHuggingPriority(.defaultHigh, for: .vertical)

        // Prevent showing scrollable content under the switcher
        switchBarVC.view.backgroundColor = Constants.backgroundColor

        NSLayoutConstraint.activate([
            switchBarVC.view.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
            switchBarVC.view.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor)
        ])

        if isUsingTopBarPosition {
            switchBarVC.view.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8).isActive = true
        } else {

            switchBarVC.view.bottomAnchor.constraint(equalTo: container.keyboardLayoutGuide.topAnchor, constant: -8).isActive = true

            // Add content mask
            // Prevents content overflow from being visible under text input.
            container.addSubview(bottomLocationSwitchBarBackgroundMaskView)
            NSLayoutConstraint.activate([
                bottomLocationSwitchBarBackgroundMaskView.topAnchor.constraint(equalTo: switchBarVC.view.bottomAnchor),
                bottomLocationSwitchBarBackgroundMaskView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bottomLocationSwitchBarBackgroundMaskView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bottomLocationSwitchBarBackgroundMaskView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        }

        switchBarVC.textEntryViewController.isUsingIncreasedButtonPadding = !isUsingTopBarPosition
        switchBarVC.didMove(toParent: self)
        switchBarVC.backButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
    }

    private func installSwipeContainer() {
        let manager = SwipeContainerManager(switchBarHandler: switchBarHandler)
        manager.installInViewController(self, asSubviewOf: contentContainerView, barView: switchBarVC.view, isTopBarPosition: isUsingTopBarPosition)
        manager.delegate = self
        manager.fadeOutDelegate = self
        swipeContainerManager = manager
    }

    private func installSuggestionsTray() {
        guard let dependencies = suggestionTrayDependencies,
              let containerViewController = swipeContainerManager?.containerViewController,
              let searchContainer = swipeContainerManager?.searchPageContainer else { return }

        let manager = SuggestionTrayManager(switchBarHandler: switchBarHandler, dependencies: dependencies)
        manager.delegate = self
        let suggestionTrayEscapeHatch = switchBarHandler.isFireTab ? nil : escapeHatchModel
        manager.installInContainerView(searchContainer, parentViewController: containerViewController, escapeHatchModel: suggestionTrayEscapeHatch)
        suggestionTrayManager = manager
    }

    private func installChatHistoryList() {
        guard featureFlagger.isFeatureOn(.aiChatSuggestions),
              aiChatSettings.isChatSuggestionsEnabled,
              let swipeContainerManager else { return }
        aiChatHistoryManager?.tearDown()
        aiChatHistoryManager = nil
        let manager = makeAIChatHistoryManager()
        
        manager.delegate = self
        swipeContainerManager.installChatHistory(using: manager)
        manager.subscribeToTextChanges(switchBarHandler.currentTextPublisher)
        chatHistoryHasSuggestionsCancellable = manager.hasSuggestionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasSuggestions in
                guard let self else { return }
                self.updateURLFallbackSuggestions(chatHasSuggestions: hasSuggestions)
                self.scheduleAnimation {
                    self.updateDaxVisibility()
                    self.view.layoutIfNeeded()
                }
            }
        manager.onFetchCompleted = { [weak self] _, _ in
            guard let self else { return }
            self.scheduleAnimation {
                self.updateDaxVisibility()
                self.view.layoutIfNeeded()
            }
        }
        aiChatHistoryManager = manager

        manager.setEscapeHatch(escapeHatchModel)
    }
    
    /// Creates ad configured for the current tab.
    /// Fire tabs use a no-op reader that always returns empty results,
    /// preventing chat history from being fetched or displayed.
    private func makeAIChatHistoryManager() -> AIChatHistoryManager {
        let suggestionsReader: AIChatSuggestionsReading
        if switchBarHandler.isFireTab {
            suggestionsReader = NilSuggestionsReader()
        } else {
            let reader = SuggestionsReader(
                featureFlagger: featureFlagger,
                privacyConfig: privacyConfigurationManager,
                nativeStorageHandler: duckAiNativeStorageHandler,
                featureFlagProvider: AIChatFeatureFlagProvider(featureFlagger: featureFlagger)
            )
            let historySettings = AIChatHistorySettings(privacyConfig: privacyConfigurationManager)
            suggestionsReader = AIChatSuggestionsReader(suggestionsReader: reader, historySettings: historySettings)
        }

        return AIChatHistoryManager(suggestionsReader: suggestionsReader,
                                    aiChatSettings: aiChatSettings,
                                    viewModel: AIChatSuggestionsViewModel(maxSuggestions: suggestionsReader.maxHistoryCount))
    }

    private func installDaxLogoView() {
        // Chat-path EOJ handoff: skip the install entirely so nothing can render during the
        // editing-state transition. The view is installed lazily in `setLogoHidden(false)`.
        guard !isDaxLogoInstallSuppressed else { return }
        if switchBarHandler.isFireTab {
            daxLogoManager.installInViewController(self,
                                                   asSubviewOf: contentContainerView,
                                                   anchorView: switchBarVC.view,
                                                   isTopBarPosition: isUsingTopBarPosition)
        } else if let view = switchBarVC.segmentedPickerView {
            daxLogoManager.installInViewController(self,
                                                   asSubviewOf: contentContainerView,
                                                   anchorView: view,
                                                   isTopBarPosition: isUsingTopBarPosition)
        }
    }

    private func installNavigationActionBar() {
        let manager = NavigationActionBarManager(
            switchBarHandler: switchBarHandler,
            isVoiceModeFeatureEnabled: voiceShortcutFeature.isAvailable
        )
        if isUsingTopBarPosition {
            // Note this is not installed in contentContainerView - this is floating over content.
            manager.installInViewController(self)
        } else {
            manager.installInViewController(switchBarVC.textEntryViewController, inView: switchBarVC.textEntryViewController.buttonsContainerView)
        }
        manager.delegate = self
        manager.animationDelegate = self
        navigationActionBarManager = manager
    }

    private var lastKnownToggleState: TextEntryMode?

    private func setupSubscriptions() {
        lastKnownToggleState = switchBarHandler.currentToggleState

        switchBarHandler.toggleStatePublisher
            .dropFirst()
            .sink { [weak self] newState in
                guard let self, newState != self.lastKnownToggleState else { return }
                self.lastKnownToggleState = newState
                self.delegate?.onToggleModeSwitched(to: newState)
                self.prepareURLFallbackForModeTransition(to: newState)
            }
            .store(in: &cancellables)

        switchBarVC.textEntryViewController.textHeightChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in

                self?.scheduleAnimation({
                    self?.updateSwipeContainerSafeArea()
                    self?.view.layoutIfNeeded()
                }, completion: nil)

            }
            .store(in: &cancellables)

        switchBarHandler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentText in

                guard let self else { return }

                self.delegate?.onQueryUpdated(currentText)

                self.updateURLFallbackForCurrentText()
                self.suggestionTrayManager?.handleQueryUpdate(currentText, animated: true)

                scheduleAnimation {
                    self.updateDaxVisibility()
                    self.updateSwipeContainerSafeArea()
                    self.view.layoutIfNeeded()
                }

            }
            .store(in: &cancellables)

        switchBarHandler.textSubmissionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] submission in
                guard let self = self else { return }

                let text = submission.text

                if self.switchBarHandler.isCurrentTextValidURL {
                    self.delegate?.onQuerySubmitted(text)
                    return
                }

                switch submission.mode {
                case .search:
                    switchBarSubmissionMetrics.process(text, for: .search)
                    self.delegate?.onQuerySubmitted(text)

                case .aiChat:
                    switchBarSubmissionMetrics.process(text, for: .aiChat)
                    // If we (re)add the web rag button, then we need to add it to the array of tools Duck.ai should use
                    //  for this submission.
                    self.delegate?.onPromptSubmitted(text, tools: nil)
                }
            }
            .store(in: &cancellables)

        switchBarHandler.microphoneButtonTappedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleMicrophoneButtonTapped()
            }
            .store(in: &cancellables)
    }

    private func updateSwipeContainerSafeArea() {
        if isUsingTopBarPosition {
            swipeContainerManager?.containerViewController.additionalSafeAreaInsets.bottom = 0
        } else {
            switchBarVC.view.layoutIfNeeded()
            let barHeigthAboveSafeArea = switchBarVC.view.bounds.height - switchBarVC.view.safeAreaInsets.bottom
            swipeContainerManager?.containerViewController.additionalSafeAreaInsets.bottom = barHeigthAboveSafeArea
        }
    }

    private func updateLayoutForCurrentOrientation() {

        guard isUsingTopBarPosition != isAdjustedForTopBar else { return }

        var currentSelection: UITextRange?
        if switchBarVC.textEntryViewController.isFocused {
            currentSelection = switchBarVC.textEntryViewController.currentTextSelection
        }

        contentContainerView.subviews.forEach { $0.removeFromSuperview() }
        navigationActionBarManager?.navigationActionBarViewController?.willMove(toParent: nil)
        navigationActionBarManager?.navigationActionBarViewController?.view.removeFromSuperview()
        navigationActionBarManager?.navigationActionBarViewController?.removeFromParent()

        switchBarVC.showsSeparator = !isUsingTopBarPosition

        installComponents()

        if let currentSelection {
            switchBarVC.textEntryViewController.focusTextField()
            switchBarVC.textEntryViewController.currentTextSelection = currentSelection
        }

        isAdjustedForTopBar = isUsingTopBarPosition
    }

    private func observeRemoteMessagesChanges() {
        notificationCancellable = NotificationCenter.default.publisher(for: RemoteMessagingStore.Notifications.remoteMessagesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.suggestionTrayManager?.showInitialSuggestions()
                self.updateDaxVisibility()
            }
    }

    private func scheduleAnimation(_ animation: @escaping () -> Void, completion: ((UIViewAnimatingPosition) -> Void)? = nil) {

        // Skip animation when off-window to prevent spring from capturing unsettled bounds.
        guard view.window != nil else {
            UIView.performWithoutAnimation { animation() }
            completion?(.end)
            return
        }

        if contentAnimator?.state == .stopped {
            contentAnimator = nil
        }

        let animator = self.contentAnimator ?? UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.73)

        contentAnimator = animator

        animator.addAnimations(animation)
        if let completion {
            animator.addCompletion(completion)
        }

        // Starts the animation. No effect if it's already running.
        animator.startAnimation()
    }

    // MARK: - Action Handlers

    @objc private func dismissButtonTapped(_ sender: UIButton) {
        Pixel.fire(pixel: .aiChatExperimentalOmnibarBackButtonPressed, withAdditionalParameters: switchBarHandler.modeParameters)
        switchBarVC.unfocusTextField()
        delegate?.onDismissRequested()
        dismissAnimated()
    }

    private func handleMicrophoneButtonTapped() {
        // Do not dismiss the OmniBar. Just dismiss the keyboard and present Voice Search above.
        switchBarVC.unfocusTextField()
        SpeechRecognizer.requestMicAccess { [weak self] permission in
            guard let self = self else { return }
            if permission {
                let preferredTarget: VoiceSearchTarget? = (self.switchBarHandler.currentToggleState == .aiChat) ? .AIChat : .SERP
                self.showVoiceSearch(preferredTarget: preferredTarget)
            } else {
                self.showNoMicrophonePermissionAlert()
            }
        }
    }

    private func showVoiceSearch(preferredTarget: VoiceSearchTarget? = nil) {
        let voiceSearchController = VoiceSearchViewController(preferredTarget: preferredTarget)
        voiceSearchController.delegate = self
        voiceSearchController.modalTransitionStyle = .crossDissolve
        voiceSearchController.modalPresentationStyle = .overFullScreen
        present(voiceSearchController, animated: true)
    }

    private func showNoMicrophonePermissionAlert() {
        let alertController = NoMicPermissionAlert.buildAlert()
        present(alertController, animated: true)
    }

    // MARK: - URL Fallback Suggestions

    /// Applies the URL filter immediately when switching to duck.ai so the suggestion
    /// list transitions naturally from full results to URL-only during the fade animation.
    private func prepareURLFallbackForModeTransition(to mode: TextEntryMode) {
        guard mode == .aiChat, shouldShowURLFallback else { return }
        daxLogoManager.updateVisibility(isHomeDaxVisible: false, isAIDaxVisible: false)
        suggestionTrayManager?.showURLOnlySuggestions(for: switchBarHandler.currentText, animated: false)
    }

    /// Called after the fade animation completes to finalize URL fallback state.
    private func finalizeURLFallbackAfterModeTransition() {
        updateURLFallbackSuggestions(chatHasSuggestions: chatHasResults)
        updateDaxVisibility()
    }

    /// Updates URL fallback on every keystroke in duck.ai mode — the chat history
    /// publisher only fires on state changes, not per-character.
    private func updateURLFallbackForCurrentText() {
        guard switchBarHandler.currentToggleState == .aiChat else { return }
        updateURLFallbackSuggestions(chatHasSuggestions: chatHasResults)
    }

    /// When in duck.ai mode and chat history has no matches, show URL-only
    /// autocomplete as a fallback so users can still navigate to websites.
    private func updateURLFallbackSuggestions(chatHasSuggestions: Bool) {
        guard switchBarHandler.currentToggleState == .aiChat else {
            if isShowingURLFallback {
                // Just reset the filter — don't hide the tray. The normal search flow
                // (handleQueryUpdate) will immediately show full results, avoiding a flash.
                suggestionTrayManager?.resetSuggestionFilter()
                isShowingURLFallback = false
            }
            return
        }
        let query = switchBarHandler.currentText
        let shouldShow = !chatHasSuggestions && !query.isBlank
        if shouldShow {
            // Apply filter first, then reveal the container — prevents flash of old unfiltered content.
            suggestionTrayManager?.showURLOnlySuggestions(for: query, animated: false)
            if !isShowingURLFallback {
                swipeContainerManager?.setSearchPageVisible(true, animated: false)
            }
            isShowingURLFallback = true
        } else if isShowingURLFallback {
            suggestionTrayManager?.hideURLOnlySuggestions(animated: true)
            swipeContainerManager?.setSearchPageVisible(false, animated: true)
            // Restore the chat container — keepSearchVisible prevented it from fading in.
            swipeContainerManager?.restoreChatPageVisibility()
            isShowingURLFallback = false
        }
    }

    private func updateDaxVisibility() {

        let shouldDisplaySuggestionTray = suggestionTrayManager?.shouldDisplaySuggestionTray == true
        let shouldDisplayFavoritesOverlay = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: view.bounds.size)
        let isShowingChatHistory = aiChatHistoryManager?.hasSuggestions == true
        let isAIChatHistoryPending = aiChatHistoryManager != nil
            && aiChatHistoryManager?.hasSettled(forQuery: switchBarHandler.currentText) != true
            && switchBarHandler.currentToggleState == .aiChat
            && !switchBarHandler.isFireTab

        let hasRemoteMessages = suggestionTrayManager?.hasRemoteMessages ?? false
        let hasEscapeHatchWithoutFavoritesOrMessages = escapeHatchModel != nil && !(suggestionTrayManager?.hasFavorites ?? false) && !hasRemoteMessages
        let isHomeDaxVisible = !shouldDisplaySuggestionTray && (!shouldDisplayFavoritesOverlay || hasEscapeHatchWithoutFavoritesOrMessages) && !isHorizontallyCompactLayoutEnabled

        let isURLFallbackShowingContent = isShowingURLFallback && (suggestionTrayManager?.isShowingSuggestionTray ?? false)

        let isAIDaxVisible = Self.isAIDaxVisible(
            isHorizontallyCompactLayoutEnabled: isHorizontallyCompactLayoutEnabled,
            isShowingChatHistory: isShowingChatHistory,
            isURLFallbackShowingContent: isURLFallbackShowingContent,
            shouldDisplaySuggestionTray: shouldDisplaySuggestionTray,
            isAIChatHistoryPending: isAIChatHistoryPending
        )

        daxLogoManager.updateVisibility(isHomeDaxVisible: isHomeDaxVisible, isAIDaxVisible: isAIDaxVisible)
        let escapeHatchOffset: CGFloat = (escapeHatchModel != nil && !switchBarHandler.isFireTab) ? Constants.escapeHatchLogoZoneHeight : 0
        daxLogoManager.setEscapeHatchBaseOffset(escapeHatchOffset)
    }

    static func isAIDaxVisible(isHorizontallyCompactLayoutEnabled: Bool,
                               isShowingChatHistory: Bool,
                               isURLFallbackShowingContent: Bool,
                               shouldDisplaySuggestionTray: Bool,
                               isAIChatHistoryPending: Bool) -> Bool {
        !isAIChatHistoryPending
        && !isHorizontallyCompactLayoutEnabled
        && !isShowingChatHistory
        && !isURLFallbackShowingContent
        && !shouldDisplaySuggestionTray
    }

}

// MARK: - NavigationActionBarViewAnimationDelegate

extension OmniBarEditingStateViewController: NavigationActionBarViewAnimationDelegate {
    func animateActionBarView(_ view: NavigationActionBarView,
                              animations: @escaping () -> Void,
                              completion: ((UIViewAnimatingPosition) -> Void)?) {
        scheduleAnimation({
            animations()
            self.view.layoutIfNeeded()
        }, completion: completion)
    }
}

// MARK: - SwipeContainerManagerDelegate

extension OmniBarEditingStateViewController: SwipeContainerViewControllerDelegate {

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didSwipeToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
    }

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didUpdateScrollProgress progress: CGFloat) {
        // Forward the scroll progress to the switch bar to animate the toggle
        switchBarVC.updateScrollProgress(progress)

        daxLogoManager.updateSwipeProgress(progress)
    }
}

// MARK: - FadeOutContainerViewControllerDelegate

extension OmniBarEditingStateViewController: FadeOutContainerViewControllerDelegate {

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didTransitionToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
        finalizeURLFallbackAfterModeTransition()
    }

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didUpdateTransitionProgress progress: CGFloat) {
        // Forward the transition progress to the switch bar to animate the toggle
        switchBarVC.updateScrollProgress(progress)

        daxLogoManager.updateSwipeProgress(progress)
    }

    func fadeOutContainerViewControllerIsShowingSuggestions(_ controller: FadeOutContainerViewController) -> Bool {
        return suggestionTrayManager?.shouldDisplaySuggestionTray ?? false
    }

    func fadeOutContainerViewControllerShouldKeepSearchVisible(_ controller: FadeOutContainerViewController) -> Bool {
        // When switching to duck.ai with text and no chat results, URL fallback will
        // show in the search container — skip the crossfade so the filtered list
        // stays visible without a blank gap or snap.
        switchBarHandler.currentToggleState == .aiChat && shouldShowURLFallback
    }
}

// MARK: - SuggestionTrayManagerDelegate

extension OmniBarEditingStateViewController: SuggestionTrayManagerDelegate {

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectSuggestion suggestion: Suggestion) {
        delegate?.onSelectSuggestion(suggestion)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectFavorite favorite: BookmarkEntity) {
        delegate?.onSelectFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, shouldUpdateTextTo text: String) {
        switchBarVC.textEntryViewController.setQueryText(text)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsEditFavorite favorite: BookmarkEntity) {
        delegate?.onEditFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsSwitchToTab tab: Tab) {
        delegate?.onSwitchToTab(tab)
    }

    func suggestionTrayManagerDidRequestTabSwitcher(_ manager: SuggestionTrayManager) {
        delegate?.onTabSwitcherRequested()
    }

    func suggestionTrayManagerDidRequestTryFireMode(_ manager: SuggestionTrayManager) {
        delegate?.onTryFireModeRequested()
    }

    func suggestionTrayManagerDidUpdateVisibility(_ manager: SuggestionTrayManager) {
        updateDaxVisibility()
    }

}

// MARK: - NavigationActionBarManagerDelegate

extension OmniBarEditingStateViewController: NavigationActionBarManagerDelegate {

    func navigationActionBarManagerDidTapMicrophone(_ manager: NavigationActionBarManager) {
        handleMicrophoneButtonTapped()
    }

    func navigationActionBarManagerDidTapNewLine(_ manager: NavigationActionBarManager) {
        Pixel.fire(pixel: .aiChatExperimentalOmnibarFloatingReturnPressed)
        let currentText = switchBarHandler.currentText
        let newText = currentText + "\n"
        switchBarHandler.updateCurrentText(newText)
    }

    func navigationActionBarManagerDidTapSearch(_ manager: NavigationActionBarManager) {
        Pixel.fire(pixel: .aiChatExperimentalOmnibarFloatingSubmitPressed, withAdditionalParameters: switchBarHandler.modeParameters)
        let currentText = switchBarHandler.currentText
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switchBarHandler.submitText(currentText)
        }
    }

    func navigationActionBarManagerDidTapVoiceMode(_ manager: NavigationActionBarManager) {
        delegate?.onVoiceModeRequested()
    }
}

// MARK: - VoiceSearchViewControllerDelegate

extension OmniBarEditingStateViewController: VoiceSearchViewControllerDelegate {

    func voiceSearchViewController(_ controller: VoiceSearchViewController, didFinishQuery query: String?, target: VoiceSearchTarget) {
        if let text = query {
            switchBarHandler.updateCurrentText(text)
        }

        controller.dismiss(animated: true) { [weak self] in
            guard let self = self, let query = query else { return }
            self.handleVoiceSearchCompletion(with: query, for: target)
        }
    }

    private func handleVoiceSearchCompletion(with query: String, for target: VoiceSearchTarget) {
        switch target {
        case .SERP:
            delegate?.onQuerySubmitted(query)

        case .AIChat:
            delegate?.onPromptSubmitted(query, tools: nil)
        }
    }
}

// MARK: - AIChatHistoryManagerDelegate

extension OmniBarEditingStateViewController: AIChatHistoryManagerDelegate {

    func aiChatHistoryManager(_ manager: AIChatHistoryManager, didSelectChatURL url: URL) {
        delegate?.onChatHistorySelected(url: url)
    }
}

private extension OmniBarEditingStateViewController {
    struct Constants {
        // Adjusts for two buttons in the action bar
        static let horizontalMarginForCompactLayout: CGFloat = 108
        static let backgroundColor = UIColor(designSystemColor: .background)
        static let animationDuration: TimeInterval = 0.15
        static let escapeHatchLogoZoneHeight: CGFloat = 70
    }
}
