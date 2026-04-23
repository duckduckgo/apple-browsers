//
//  UnifiedInputContentContainerViewController.swift
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
import DesignResourcesKit
import Combine
import PrivacyConfig
import Bookmarks
import Persistence
import History
import Core
import Suggestions
import AIChat
import RemoteMessaging

protocol UnifiedInputContentContainerViewControllerDelegate: AnyObject {
    func unifiedInputEditingStateDidSubmitQuery(_ query: String)
    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?)
    func unifiedInputEditingStateDidSelectFavorite(_ favorite: BookmarkEntity)
    func unifiedInputEditingStateDidEditFavorite(_ favorite: BookmarkEntity)
    func unifiedInputEditingStateDidSelectSuggestion(_ suggestion: Suggestion)
    func unifiedInputEditingStateDidSelectChatHistory(url: URL)
    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: Tab)
    func unifiedInputEditingStateDidRequestTryFireMode()
    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode)
}

final class UnifiedInputContentContainerViewController: UIViewController {

    /// Selects how visible content should refresh without spreading query and tray logic across multiple call sites.
    private enum SuggestionRefreshStrategy {
        case none
        case currentQuery(animated: Bool)
        case currentState
    }

    // MARK: - Properties

    var suggestionTrayDependencies: SuggestionTrayDependencies?
    weak var delegate: UnifiedInputContentContainerViewControllerDelegate?
    var onDismissRequested: (() -> Void)?
    var onSwipeDownRequested: (() -> Void)?

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    private lazy var contentContainerView = UIView()
    private lazy var floatingDismissButton: UIButton = {
        let button: UIButton
        if #available(iOS 26, *) {
            var config = UIButton.Configuration.glass()
            config.image = UIImage(systemName: "xmark")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            button = UIButton(configuration: config)
        } else {
            button = UIButton(type: .system)
            let image = UIImage(systemName: "xmark")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            button.setImage(image, for: .normal)
            button.tintColor = UIColor(designSystemColor: .textPrimary)
            button.backgroundColor = UIColor(designSystemColor: .surface)
            button.layer.cornerRadius = 22
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.1
            button.layer.shadowRadius = 4
            button.layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleFloatingDismissTap), for: .primaryActionTriggered)
        return button
    }()

    private var isLandscapeOrientation: Bool = false {
        didSet {
            isUsingTopBarPosition = !forceBottomBarLayout && (appSettings.currentAddressBarPosition == .top || isLandscapeOrientation)
        }
    }
    var forceBottomBarLayout: Bool = false {
        didSet {
            isUsingTopBarPosition = !forceBottomBarLayout && (appSettings.currentAddressBarPosition == .top || isLandscapeOrientation)
        }
    }
    private var isUsingTopBarPosition: Bool
    private var isAdjustedForTopBar: Bool
    private(set) var currentSectionTitle: String?

    private weak var contentContainerViewLeadingConstraint: NSLayoutConstraint?
    private weak var contentContainerViewTrailingConstraint: NSLayoutConstraint?

    let appSettings: AppSettings
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let aiChatSettings: AIChatSettingsProvider
    private let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?

    // MARK: - Manager Components

    private var swipeContainerManager: SwipeContainerManager?
    private var suggestionTrayManager: SuggestionTrayManager?
    private var aiChatHistoryManager: AIChatHistoryManager?
    private var isShowingURLFallback = false
    private var isContentActive = false
    private var needsVisibleRefresh = true
    private var requestedContentInset: (top: CGFloat, bottom: CGFloat) = (0, 0)
    private var escapeHatchModel: EscapeHatchModel?
    private var escapeHatchTapHandler: (() -> Void)?

    private var chatHasSuggestions: Bool {
        aiChatHistoryManager?.hasSuggestions ?? false
    }

    private let daxLogoManager: DaxLogoManager
    private var notificationCancellable: AnyCancellable?

    private weak var contentAnimator: UIViewPropertyAnimator?

    // MARK: - Initialization

    init(switchBarHandler: SwitchBarHandling,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil) {
        self.switchBarHandler = switchBarHandler
        self.daxLogoManager = DaxLogoManager()
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.aiChatSettings = aiChatSettings
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
        self.isUsingTopBarPosition = appSettings.currentAddressBarPosition == .top
        self.isAdjustedForTopBar = self.isUsingTopBarPosition

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        installComponents()
        setupSubscriptions()
        observeRemoteMessagesChanges()
        observeAddressBarPositionChanges()

        suggestionTrayManager?.showInitialSuggestions()
        updateDaxVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if aiChatHistoryManager == nil && featureFlagger.isFeatureOn(.aiChatSuggestions) && aiChatSettings.isChatSuggestionsEnabled {
            installChatHistoryList()
        }
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

    func setLogoYOffset(_ offset: CGFloat) {
        daxLogoManager.containerYCenterConstraint?.constant = offset
    }

    func setLogoHidden(_ hidden: Bool) {
        daxLogoManager.setForcedHidden(hidden)
    }

    var isSwipeEnabled: Bool = true {
        didSet { swipeContainerManager?.isSwipeEnabled = isSwipeEnabled }
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool = true) {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        let didModeChange = switchBarHandler.currentToggleState != mode
        if !animated {
            swipeContainerManager?.animateProgrammaticModeChanges = false
        }
        if didModeChange {
            switchBarHandler.setToggleState(mode)
        }
        let suggestionRefresh: SuggestionRefreshStrategy = mode == .search ? .currentState : .none
        refreshVisibleContent(suggestionRefresh: suggestionRefresh, visibleModeAnimation: animated, animateContentUpdates: false)
        swipeContainerManager?.animateProgrammaticModeChanges = true
    }

    func setDismissButtonVisible(_ visible: Bool) {
        floatingDismissButton.isHidden = !visible
    }

    func setActive(_ active: Bool) {
        guard active != isContentActive else { return }
        isContentActive = active
        markNeedsVisibleRefresh()
    }

    func refreshVisibleContentIfNeeded() {
        guard isContentActive else { return }
        guard needsVisibleRefresh else { return }

        refreshVisibleContent(
            suggestionRefresh: currentModeSuggestionRefresh(),
            visibleModeAnimation: false,
            animateContentUpdates: false
        )
    }

    func setEscapeHatch(_ model: EscapeHatchModel?, onTapped: (() -> Void)?) {
        escapeHatchModel = model
        escapeHatchTapHandler = onTapped
        suggestionTrayManager?.setEscapeHatch(model)
        aiChatHistoryManager?.setEscapeHatch(model, onTapped: onTapped)
        updateEscapeHatchTopInset()
    }

    /// Updates top insets for escape hatch positioning on both suggestion tray and chat history.
    /// The two tabs use different view technologies (SwiftUI NTP vs UITableView) that handle
    /// safe area differently, so chat history needs per-position compensation to align visually.
    private func updateEscapeHatchTopInset() {
        let insets = Self.computeEscapeHatchInsets(
            hasEscapeHatch: escapeHatchModel != nil,
            isBottomBar: !isUsingTopBarPosition,
            chatHasSuggestions: chatHasSuggestions,
            isLandscape: isLandscapeOrientation
        )
        suggestionTrayManager?.setAdditionalTopInset(insets.tray)
        aiChatHistoryManager?.setAdditionalTopInset(insets.chat)
    }

    static func computeEscapeHatchInsets(hasEscapeHatch: Bool,
                                         isBottomBar: Bool,
                                         chatHasSuggestions: Bool,
                                         isLandscape: Bool) -> (tray: CGFloat, chat: CGFloat) {
        // Tray: bottom bar needs space for dismiss button; top bar gets a small pull-up.
        let suggestionInsetBase: CGFloat = hasEscapeHatch && isBottomBar ? Metrics.escapeHatchBaseTopInset : 0
        let trayTopBarPullUp: CGFloat = hasEscapeHatch && !isBottomBar ? Metrics.escapeHatchTopBarTrayPullUp : 0
        let tray = suggestionInsetBase + trayTopBarPullUp

        // Chat history uses the same base, then applies corrections:
        // - compensation: UITableView vs SwiftUI NTP safe-area difference in bottom bar
        // - emptyListBoost: vertical centering of hatch when chat list is empty (portrait top bar only)
        // - landscapeAlignment: small pull-up so chat hatch aligns with Search tray in landscape
        let compensation: CGFloat = hasEscapeHatch && isBottomBar ? Metrics.chatHistoryBottomBarCompensation : 0
        let emptyListBoost: CGFloat = hasEscapeHatch && !chatHasSuggestions && !isBottomBar && !isLandscape
            ? Metrics.escapeHatchEmptyListBoost : 0
        let landscapeAlignment: CGFloat = hasEscapeHatch && isLandscape ? Metrics.landscapeDuckAiAlignmentPullUp : 0
        let chat = suggestionInsetBase - compensation + emptyListBoost + landscapeAlignment

        return (tray: tray, chat: chat)
    }

    func setText(_ text: String) {
        switchBarHandler.updateCurrentText(text)
        if !isContentActive {
            markNeedsVisibleRefresh()
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        adjustLayoutForViewSize(view.bounds.size)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { _ in
            self.adjustLayoutForViewSize(size)
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Private Methods

    private func requiresHorizontallyCompactLayout(for size: CGSize) -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }

        if let orientation = view.window?.windowScene?.interfaceOrientation {
            return orientation.isLandscape
        }

        if let sceneOrientation = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.interfaceOrientation })
            .first {
            return sceneOrientation.isLandscape
        }

        return false
    }

    private func adjustLayoutForViewSize(_ size: CGSize) {
        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: size)
        self.isLandscapeOrientation = isHorizontallyCompactLayoutEnabled

        let horizontalMargin: CGFloat = isHorizontallyCompactLayoutEnabled ? Metrics.horizontalMarginForCompactLayout : 0
        self.contentContainerViewLeadingConstraint?.constant = horizontalMargin
        self.contentContainerViewTrailingConstraint?.constant = -horizontalMargin
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        self.updateDaxVisibility()
        self.updateLayoutForCurrentOrientation()
    }

    private func setupView() {
        view.backgroundColor = Metrics.backgroundColor
        setUpContentContainer()
        setUpFloatingDismissButton()
        setUpSwipeDownGesture()
    }

    private func setUpContentContainer() {
        view.addSubview(contentContainerView)
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false

        contentContainerViewLeadingConstraint = contentContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        contentContainerViewLeadingConstraint?.isActive = true
        contentContainerViewTrailingConstraint = contentContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        contentContainerViewTrailingConstraint?.isActive = true
        contentContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true

        NSLayoutConstraint.activate([
            contentContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setUpFloatingDismissButton() {
        view.addSubview(floatingDismissButton)
        NSLayoutConstraint.activate([
            floatingDismissButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            floatingDismissButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            floatingDismissButton.widthAnchor.constraint(equalToConstant: 44),
            floatingDismissButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setUpSwipeDownGesture() {
        let swipeDownGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDownGesture.direction = .down
        swipeDownGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(swipeDownGesture)
    }

    private func installComponents() {
        installSwipeContainer()
        installSuggestionsTray()
        installDaxLogoView()
    }

    private func updateSectionTitle() {
        let text = computedSectionTitleText()
        currentSectionTitle = text.isEmpty ? nil : text

        let mode = switchBarHandler.currentToggleState
        switch mode {
        case .search:
            let hasFavorites = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
            if hasFavorites {
                suggestionTrayManager?.setFavoritesSectionTitle(currentSectionTitle)
                suggestionTrayManager?.setSuggestionsSectionTitle(nil)
            } else {
                suggestionTrayManager?.setSuggestionsSectionTitle(currentSectionTitle)
                suggestionTrayManager?.setFavoritesSectionTitle(nil)
            }
            aiChatHistoryManager?.setSectionTitle(nil)
        case .aiChat:
            let isURLFallbackShowingContent = isShowingURLFallback && (suggestionTrayManager?.isShowingSuggestionTray ?? false)
            suggestionTrayManager?.setSuggestionsSectionTitle(isURLFallbackShowingContent ? currentSectionTitle : nil)
            suggestionTrayManager?.setFavoritesSectionTitle(nil)
            aiChatHistoryManager?.setSectionTitle(isURLFallbackShowingContent ? nil : currentSectionTitle)
        }
    }

    private func computedSectionTitleText() -> String {
        let mode = switchBarHandler.currentToggleState
        let hasFavorites = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
        let hasAutocomplete = suggestionTrayManager?.shouldDisplaySuggestionTray == true && !hasFavorites
        let hasChatHistory = aiChatHistoryManager?.hasSuggestions == true
        let isURLFallbackShowingContent = isShowingURLFallback && (suggestionTrayManager?.isShowingSuggestionTray ?? false)
        switch mode {
        case .search:
            if hasFavorites { return UserText.sectionTitleFavorites }
            if hasAutocomplete { return UserText.sectionTitleSuggestions }
            return ""
        case .aiChat:
            if isURLFallbackShowingContent { return UserText.sectionTitleSuggestions }
            if hasChatHistory {
                return switchBarHandler.currentText.isEmpty ? UserText.aiChatRecentChatsTitle : UserText.aiChatSuggestedChatsTitle
            }
            return ""
        }
    }

    private func installSwipeContainer() {
        let manager = SwipeContainerManager(switchBarHandler: switchBarHandler)
        let containerVC = manager.containerViewController
        addChild(containerVC)
        contentContainerView.addSubview(containerVC.view)
        containerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            containerVC.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            containerVC.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            containerVC.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            containerVC.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])
        containerVC.didMove(toParent: self)
        manager.delegate = self
        manager.fadeOutDelegate = self
        manager.isSwipeEnabled = isSwipeEnabled
        swipeContainerManager = manager
    }

    private func installSuggestionsTray() {
        guard let dependencies = suggestionTrayDependencies,
              let containerViewController = swipeContainerManager?.containerViewController,
              let searchContainer = swipeContainerManager?.searchPageContainer else { return }

        let manager = SuggestionTrayManager(switchBarHandler: switchBarHandler, dependencies: dependencies)
        manager.delegate = self
        let trayEscapeHatch = switchBarHandler.isFireTab ? nil : escapeHatchModel
        manager.installInContainerView(searchContainer, parentViewController: containerViewController, escapeHatch: trayEscapeHatch)
        suggestionTrayManager = manager
    }

    private func installChatHistoryList() {
        guard let swipeContainerManager else { return }

        let manager = makeAIChatHistoryManager()
        manager.delegate = self
        manager.titleLayoutConfiguration = .unifiedInput
        swipeContainerManager.installChatHistory(using: manager)
        manager.subscribeToTextChanges(switchBarHandler.currentTextPublisher)
        manager.onFetchCompleted = { [weak self] _, _ in
            guard let self else { return }
            self.updateDaxVisibility()
        }
        aiChatHistoryManager = manager
        if let escapeHatchModel, !switchBarHandler.isFireTab {
            manager.setEscapeHatch(escapeHatchModel, onTapped: escapeHatchTapHandler)
        }

        manager.hasSuggestionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshVisibleContent(suggestionRefresh: .none, animateContentUpdates: true)
            }
            .store(in: &cancellables)
    }

    /// Creates an `AIChatHistoryManager` configured for the current tab.
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
        daxLogoManager.installInViewController(self, asSubviewOf: contentContainerView, anchorView: contentContainerView, isTopBarPosition: false)
    }

    private func setupSubscriptions() {
        setupSwitchBarSubscriptions()
        setupFavoritesSubscriptions()
    }

    private func setupSwitchBarSubscriptions() {
        switchBarHandler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshVisibleContent(suggestionRefresh: .currentQuery(animated: true), animateContentUpdates: true)
            }
            .store(in: &cancellables)

    }

    private func updateLayoutForCurrentOrientation() {
        guard isUsingTopBarPosition != isAdjustedForTopBar else { return }
        isAdjustedForTopBar = isUsingTopBarPosition
        updateSectionTitle()
        updateEscapeHatchTopInset()
    }

    private func observeAddressBarPositionChanges() {
        NotificationCenter.default
            .publisher(for: AppUserDefaults.Notifications.addressBarPositionChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onAddressBarPositionChanged() }
            .store(in: &cancellables)
    }

    private func onAddressBarPositionChanged() {
        isUsingTopBarPosition = !forceBottomBarLayout && (appSettings.currentAddressBarPosition == .top || isLandscapeOrientation)
        updateLayoutForCurrentOrientation()
    }

    private func observeRemoteMessagesChanges() {
        notificationCancellable = NotificationCenter.default.publisher(for: RemoteMessagingStore.Notifications.remoteMessagesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshVisibleContent(
                    suggestionRefresh: self.currentModeSuggestionRefresh(),
                    animateContentUpdates: false
                )
            }
    }

    private func markNeedsVisibleRefresh() {
        needsVisibleRefresh = true
    }

    private func scheduleAnimation(_ animation: @escaping () -> Void, completion: ((UIViewAnimatingPosition) -> Void)? = nil) {
        if contentAnimator?.state == .stopped {
            contentAnimator = nil
        }

        let animator = self.contentAnimator ?? UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.73)
        contentAnimator = animator

        animator.addAnimations(animation)
        if let completion {
            animator.addCompletion(completion)
        }

        animator.startAnimation()
    }

    // MARK: - Action Handlers

    private func handleMicrophoneButtonTapped() {
        guard isViewLoaded, view.window != nil, !view.isHidden, !(view.superview?.isHidden ?? true) else { return }
        SpeechRecognizer.requestMicAccess { [weak self] permission in
            guard let self,
                  self.view.window != nil,
                  self.view.superview?.isHidden != true else { return }
            if permission {
                let preferredTarget: VoiceSearchTarget? = (self.switchBarHandler.currentToggleState == .aiChat) ? .AIChat : .SERP
                self.showVoiceSearch(preferredTarget: preferredTarget)
            } else {
                self.showNoMicrophonePermissionAlert()
            }
        }
    }

    @objc private func handleSwipeDown() {
        onSwipeDownRequested?()
    }

    func setContentInset(top: CGFloat, bottom: CGFloat) {
        guard requestedContentInset.top != top || requestedContentInset.bottom != bottom else { return }
        requestedContentInset = (top, bottom)
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        applyRequestedContentInset()
    }

    private func applyRequestedContentInset() {
        var insets = UIEdgeInsets(
            top: requestedContentInset.top,
            left: 0,
            bottom: requestedContentInset.bottom,
            right: 0
        )
        insets.top += Metrics.contentTopInset
        guard swipeContainerManager?.containerViewController.additionalSafeAreaInsets != insets else { return }
        swipeContainerManager?.containerViewController.additionalSafeAreaInsets = insets
    }

    @objc private func handleFloatingDismissTap() {
        onDismissRequested?()
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

    private func updateDaxVisibility() {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        let shouldDisplaySuggestionTray = suggestionTrayManager?.shouldDisplaySuggestionTray == true
        let isShowingTray = suggestionTrayManager?.isShowingSuggestionTray ?? false
        let shouldDisplayFavoritesOverlay = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: view.bounds.size)
        let isShowingChatHistory = aiChatHistoryManager?.hasSuggestions == true
        let isChatHistoryPending = aiChatHistoryManager != nil
            && aiChatHistoryManager?.hasCompletedInitialFetch != true
            && switchBarHandler.currentToggleState == .aiChat
        let isURLFallbackShowingContent = isShowingURLFallback && isShowingTray

        let hasContent = (shouldDisplaySuggestionTray && isShowingTray) || isHorizontallyCompactLayoutEnabled
        let homeDaxInputs = HomeDaxInputs(
            hasContent: hasContent,
            shouldDisplayFavoritesOverlay: shouldDisplayFavoritesOverlay,
            hasEscapeHatch: escapeHatchModel != nil,
            hasFavorites: suggestionTrayManager?.hasFavorites ?? false,
            hasRemoteMessages: suggestionTrayManager?.hasRemoteMessages ?? false
        )
        let isHomeDaxVisible = daxLogoManager.shouldShowHomeDax(homeDaxInputs)
        let isAIDaxVisible = !hasContent && !isShowingChatHistory && !isChatHistoryPending && !isURLFallbackShowingContent

        daxLogoManager.updateVisibility(isHomeDaxVisible: isHomeDaxVisible, isAIDaxVisible: isAIDaxVisible)
        let escapeHatchOffset: CGFloat = (escapeHatchModel != nil && !switchBarHandler.isFireTab) ? Metrics.escapeHatchLogoOffset : 0
        daxLogoManager.setEscapeHatchBaseOffset(escapeHatchOffset)
        updateSectionTitle()
    }

    // MARK: - URL Fallback Suggestions

    private func restoreFullSuggestions() {
        guard isShowingURLFallback else { return }
        suggestionTrayManager?.resetSuggestionFilter()
        swipeContainerManager?.setSearchPageVisible(false, animated: false)
        isShowingURLFallback = false
    }

    private func updateURLFallbackSuggestions(hasSuggestions: Bool, mode: TextEntryMode) {
        guard mode == .aiChat else {
            restoreFullSuggestions()
            return
        }
        let query = switchBarHandler.currentText
        let shouldShow = !hasSuggestions && !query.isBlank
        if shouldShow {
            let wasShowingURLFallback = isShowingURLFallback
            isShowingURLFallback = true
            suggestionTrayManager?.showURLOnlySuggestions(for: query, animated: false)
            if !wasShowingURLFallback {
                swipeContainerManager?.setSearchPageVisible(true, animated: false)
            }
        } else if isShowingURLFallback {
            isShowingURLFallback = false
            suggestionTrayManager?.hideURLOnlySuggestions(animated: true)
            swipeContainerManager?.setSearchPageVisible(false, animated: true)
            swipeContainerManager?.restoreChatPageVisibility()
        }
    }

    private enum Metrics {
        static let horizontalMarginForCompactLayout: CGFloat = 108
        static let backgroundColor = UIColor(designSystemColor: .panel)
        static let contentTopInset: CGFloat = 10
        static let escapeHatchBaseTopInset: CGFloat = 44
        static let chatHistoryBottomBarCompensation: CGFloat = 1
        static let escapeHatchLogoOffset: CGFloat = 120
        // Vertically centers the escape hatch card when the chat history list is empty (no recent chats)
        static let escapeHatchEmptyListBoost: CGFloat = 165
        // Pulls the suggestion tray (NTP/Favorites) upward in UTI top bar to tighten gap between UTI input and hatch.
        static let escapeHatchTopBarTrayPullUp: CGFloat = -10
        // Landscape-only small alignment pull-up for chat history hatch so it visually matches Search tray position.
        static let landscapeDuckAiAlignmentPullUp: CGFloat = -1
    }
}

private extension UnifiedInputContentContainerViewController {

    func setupFavoritesSubscriptions() {
        guard let favoritesViewModel = suggestionTrayDependencies?.favoritesViewModel else { return }

        favoritesViewModel.localUpdates
            .merge(with: favoritesViewModel.externalUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.refreshVisibleContent(
                    suggestionRefresh: self.currentModeSuggestionRefresh(),
                    animateContentUpdates: false
                )
            }
            .store(in: &cancellables)
    }

    private func currentModeSuggestionRefresh() -> SuggestionRefreshStrategy {
        switch switchBarHandler.currentToggleState {
        case .search:
            .currentState
        case .aiChat:
            .none
        }
    }

    private func refreshVisibleContent(
        suggestionRefresh: SuggestionRefreshStrategy,
        visibleModeAnimation: Bool? = nil,
        animateContentUpdates: Bool
    ) {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }

        needsVisibleRefresh = false

        switch suggestionRefresh {
        case .none:
            break
        case .currentQuery(let animated):
            suggestionTrayManager?.handleQueryUpdate(switchBarHandler.currentText, animated: animated)
        case .currentState:
            suggestionTrayManager?.showInitialSuggestions()
        }

        refreshContentPresentationState()

        let applyContentUpdates = {
            self.updateDaxVisibility()
            self.updateEscapeHatchTopInset()
            self.applyRequestedContentInset()
            if let visibleModeAnimation {
                self.swipeContainerManager?.syncVisibleMode(animated: visibleModeAnimation)
            }
            self.view.layoutIfNeeded()
        }

        if animateContentUpdates {
            scheduleAnimation(applyContentUpdates)
        } else {
            applyContentUpdates()
        }
    }

    func refreshContentPresentationState() {
        let mode = switchBarHandler.currentToggleState
        if mode == .aiChat {
            updateURLFallbackSuggestions(hasSuggestions: chatHasSuggestions, mode: mode)
        } else {
            restoreFullSuggestions()
        }
    }
}

// MARK: - SwipeContainerViewControllerDelegate

extension UnifiedInputContentContainerViewController: SwipeContainerViewControllerDelegate {

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didSwipeToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
        delegate?.unifiedInputEditingStateDidChangeMode(mode)
        let suggestionRefresh: SuggestionRefreshStrategy = mode == .search ? .currentState : .none
        refreshVisibleContent(suggestionRefresh: suggestionRefresh, animateContentUpdates: false)
    }

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didUpdateScrollProgress progress: CGFloat) {
        daxLogoManager.updateSwipeProgress(progress)
    }
}

// MARK: - FadeOutContainerViewControllerDelegate

extension UnifiedInputContentContainerViewController: FadeOutContainerViewControllerDelegate {

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didTransitionToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
        delegate?.unifiedInputEditingStateDidChangeMode(mode)
        let suggestionRefresh: SuggestionRefreshStrategy = mode == .search ? .currentState : .none
        refreshVisibleContent(suggestionRefresh: suggestionRefresh, animateContentUpdates: false)
    }

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didUpdateTransitionProgress progress: CGFloat) {
        daxLogoManager.updateSwipeProgress(progress)
    }

    func fadeOutContainerViewControllerIsShowingSuggestions(_ controller: FadeOutContainerViewController) -> Bool {
        return suggestionTrayManager?.shouldDisplaySuggestionTray ?? false
    }

    func fadeOutContainerViewControllerShouldKeepSearchVisible(_ controller: FadeOutContainerViewController) -> Bool {
        return isShowingURLFallback
    }
}

// MARK: - SuggestionTrayManagerDelegate

extension UnifiedInputContentContainerViewController: SuggestionTrayManagerDelegate {

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectSuggestion suggestion: Suggestion) {
        delegate?.unifiedInputEditingStateDidSelectSuggestion(suggestion)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectFavorite favorite: BookmarkEntity) {
        delegate?.unifiedInputEditingStateDidSelectFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, shouldUpdateTextTo text: String) {
        switchBarHandler.updateCurrentText(text)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsEditFavorite favorite: BookmarkEntity) {
        delegate?.unifiedInputEditingStateDidEditFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsSwitchToTab tab: Tab) {
        delegate?.unifiedInputEditingStateDidRequestSwitchTab(tab)
    }

    func suggestionTrayManagerDidRequestTryFireMode(_ manager: SuggestionTrayManager) {
        delegate?.unifiedInputEditingStateDidRequestTryFireMode()
    }

    func suggestionTrayManagerDidUpdateVisibility(_ manager: SuggestionTrayManager) {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        updateDaxVisibility()
        view.layoutIfNeeded()
    }
}

// MARK: - VoiceSearchViewControllerDelegate

extension UnifiedInputContentContainerViewController: VoiceSearchViewControllerDelegate {

    func voiceSearchViewController(_ controller: VoiceSearchViewController, didFinishQuery query: String?, target: VoiceSearchTarget) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self, let query else { return }
            let mode: TextEntryMode = (target == .AIChat) ? .aiChat : .search
            self.switchBarHandler.setToggleState(mode)
            self.switchBarHandler.submitText(query)
        }
    }
}

// MARK: - AIChatHistoryManagerDelegate

extension UnifiedInputContentContainerViewController: AIChatHistoryManagerDelegate {

    func aiChatHistoryManager(_ manager: AIChatHistoryManager, didSelectChatURL url: URL) {
        delegate?.unifiedInputEditingStateDidSelectChatHistory(url: url)
    }
}
