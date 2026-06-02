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
import DDGSync
import Suggestions
import AIChat
import RemoteMessaging

protocol UnifiedInputContentContainerViewControllerDelegate: AnyObject {
    func unifiedInputEditingStateDidSubmitQuery(_ query: String)
    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?)
    func unifiedInputEditingStateDidSelectFavorite(_ favorite: BookmarkEntity)
    func unifiedInputEditingStateDidEditFavorite(_ favorite: BookmarkEntity)
    func unifiedInputEditingStateDidSelectSuggestion(_ suggestion: Suggestion)
    func unifiedInputEditingStateDidRequestTextUpdate(_ text: String)
    func unifiedInputEditingStateDidSelectChatHistory(url: URL)
    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: Tab)
    func unifiedInputEditingStateDidRequestTabSwitcher()
    func unifiedInputEditingStateDidRequestTryFireMode()
    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode)
    func unifiedInputEditingStateDidRequestSyncSetup()
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
    private let syncService: DDGSyncing?
    private let syncPromoManager: SyncPromoManaging?
    private let aiChatSyncIntroSheetPresenter: AIChatSyncIntroSheetPresenting

    // MARK: - Manager Components

    private var swipeContainerManager: SwipeContainerManager?
    private var suggestionTrayManager: SuggestionTrayManager?
    private var duckAISuggestionsCoordinator: DuckAISuggestionsCoordinator?
    private var urlAutocompleteTask: URLSessionDataTask?
    private var isContentActive = false
    private var needsVisibleRefresh = true
    private var requestedContentInset: (top: CGFloat, bottom: CGFloat) = (0, 0)
    private var escapeHatchModel: EscapeHatchModel?

    private(set) var daxLogoManager: DaxLogoManager
    private var isDaxLogoForcedHidden = false
    private var notificationCancellable: AnyCancellable?

    private weak var contentAnimator: UIViewPropertyAnimator?

    // MARK: - Initialization

    init(switchBarHandler: SwitchBarHandling,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
         syncService: DDGSyncing? = nil,
         aiChatSyncIntroSheetPresenter: AIChatSyncIntroSheetPresenting = AIChatSyncIntroSheetPresenter()) {
        self.switchBarHandler = switchBarHandler
        self.daxLogoManager = DaxLogoManager(isFireTab: switchBarHandler.isFireTab)
        self.daxLogoManager.usesLottieTransition = true
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.aiChatSettings = aiChatSettings
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
        self.syncService = syncService
        self.syncPromoManager = syncService.map { SyncPromoManager(syncService: $0,
                                                                  featureFlagger: featureFlagger,
                                                                  privacyConfigurationManager: privacyConfigurationManager) }
        self.aiChatSyncIntroSheetPresenter = aiChatSyncIntroSheetPresenter
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

        installDuckAISuggestionsIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        duckAISuggestionsCoordinator?.tearDown()
        duckAISuggestionsCoordinator = nil
        urlAutocompleteTask?.cancel()
        urlAutocompleteTask = nil
    }

    // MARK: - Public Methods

    @objc func dismissAnimated(_ completion: (() -> Void)? = nil) {
        if self.presentingViewController != nil {
            self.dismiss(animated: true, completion: completion)
        }
    }

    func setLogoYOffset(_ offset: CGFloat) {
        daxLogoManager.setLogoYOffset(offset)
    }

    func setLogoHidden(_ hidden: Bool) {
        isDaxLogoForcedHidden = hidden
        daxLogoManager.setForcedHidden(hidden)
    }

    func refreshFireMode(fireMode: Bool) {
        rebuildDaxLogoManager(isFireTab: fireMode)
        rebuildDuckAISuggestionsCoordinator()
    }

    private func rebuildDaxLogoManager(isFireTab: Bool) {
        daxLogoManager.tearDown()
        daxLogoManager = DaxLogoManager(isFireTab: isFireTab)
        daxLogoManager.usesLottieTransition = true
        // Replay cached forcedHidden so rebuilds don't silently un-hide the dax logo / fire empty state.
        daxLogoManager.setForcedHidden(isDaxLogoForcedHidden)
        guard isViewLoaded else { return }
        installDaxLogoView()
        applyRequestedContentInset()
        updateDaxVisibility()
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

    func setActive(_ active: Bool) {
        guard active != isContentActive else { return }
        isContentActive = active
        markNeedsVisibleRefresh()
        updateDuckAISuggestionsActiveState()
    }

    private func updateDuckAISuggestionsActiveState() {
        duckAISuggestionsCoordinator?.setIsVisibleContent(
            isContentActive && switchBarHandler.currentToggleState == .aiChat
        )
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

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        escapeHatchModel = model
        // The model self-updates `openTabCount` from `TabManaging.tabsModel(for:).tabsPublisher`, so SwiftUI consumers redraw reactively.
        suggestionTrayManager?.setEscapeHatch(model)
        // Fire tabs render their own empty state via DaxLogoManager — suppress the hatch to avoid stacking affordances.
        let duckAIHatchModel = switchBarHandler.isFireTab ? nil : model
        duckAISuggestionsCoordinator?.setEscapeHatch(duckAIHatchModel)
        updateEscapeHatchTopInset()
    }

    private var escapeHatchTopInset: CGFloat {
        Self.computeSuggestionTrayEscapeHatchInset(hasEscapeHatch: escapeHatchModel != nil)
    }

    /// Updates both surfaces' top insets so the escape hatch aligns with the NTP hatch.
    private func updateEscapeHatchTopInset() {
        let inset = escapeHatchTopInset
        suggestionTrayManager?.setAdditionalTopInset(inset)
        duckAISuggestionsCoordinator?.setAdditionalTopInset(inset)
    }

    /// Returns the top inset needed so the UTI escape hatch lines up with the NTP
    /// escape hatch. The suggestion tray container chain positions the UTI hatch
    /// ~10pt below the NTP equivalent; this pull-up corrects for that in both
    /// top and bottom bar positions.
    static func computeSuggestionTrayEscapeHatchInset(hasEscapeHatch: Bool) -> CGFloat {
        hasEscapeHatch ? Metrics.escapeHatchTrayPullUp : 0
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

    /// Suppresses suggestion-tray section headers per the unified-input redesign.
    /// Flip to `true` to restore headers; selection logic below is preserved.
    /// Consider removing this and the code it guards after release.
    private static let areSectionHeadersEnabled = false

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
        case .aiChat:
            // The Duck.ai multi-section VC handles its own internal section grouping; the container
            // doesn't impose a single overarching title.
            suggestionTrayManager?.setSuggestionsSectionTitle(nil)
            suggestionTrayManager?.setFavoritesSectionTitle(nil)
        }
    }

    /// Returns the header label for the currently visible tray, or `""` when none applies
    /// (and unconditionally while `areSectionHeadersEnabled` is `false`).
    private func computedSectionTitleText() -> String {
        guard Self.areSectionHeadersEnabled else { return "" }

        let mode = switchBarHandler.currentToggleState
        let hasFavorites = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
        let hasAutocomplete = suggestionTrayManager?.shouldDisplaySuggestionTray == true && !hasFavorites
        switch mode {
        case .search:
            if hasFavorites { return UserText.sectionTitleFavorites }
            if hasAutocomplete { return UserText.sectionTitleSuggestions }
            return ""
        case .aiChat:
            return ""
        }
    }

    private func installSwipeContainer() {
        let manager = SwipeContainerManager(switchBarHandler: switchBarHandler, contentTransition: .crossfade)
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

        let manager = SuggestionTrayManager(
            switchBarHandler: switchBarHandler,
            dependencies: dependencies,
            autocompleteHorizontalInset: Metrics.suggestionsHorizontalInset)
        manager.delegate = self
        let trayEscapeHatchModel = switchBarHandler.isFireTab ? nil : escapeHatchModel
        manager.installInContainerView(searchContainer, parentViewController: containerViewController, escapeHatchModel: trayEscapeHatchModel)
        suggestionTrayManager = manager
    }

    private func installDuckAISuggestionsIfNeeded() {
        guard duckAISuggestionsCoordinator == nil,
              featureFlagger.isFeatureOn(.aiChatSuggestions),
              aiChatSettings.isChatSuggestionsEnabled else { return }
        installDuckAISuggestions()
    }

    private func rebuildDuckAISuggestionsCoordinator() {
        guard duckAISuggestionsCoordinator != nil else { return }
        duckAISuggestionsCoordinator?.tearDown()
        duckAISuggestionsCoordinator = nil
        installDuckAISuggestionsIfNeeded()
    }

    private func installDuckAISuggestions() {
        guard let swipeContainerManager,
              let dependencies = suggestionTrayDependencies else { return }

        // Build the chat-side fetcher (existing infrastructure, fire-tab uses no-op reader).
        let chatViewModel: AIChatSuggestionsViewModel
        let chatManager: AIChatHistoryManager
        let chatSuggestionsReader: AIChatSuggestionsReading
        if switchBarHandler.isFireTab {
            chatSuggestionsReader = NilSuggestionsReader()
        } else {
            let reader = SuggestionsReader(
                featureFlagger: featureFlagger,
                privacyConfig: privacyConfigurationManager,
                nativeStorageHandler: duckAiNativeStorageHandler,
                featureFlagProvider: AIChatFeatureFlagProvider(featureFlagger: featureFlagger)
            )
            let historySettings = AIChatHistorySettings(privacyConfig: privacyConfigurationManager)
            chatSuggestionsReader = AIChatSuggestionsReader(suggestionsReader: reader, historySettings: historySettings)
        }
        chatViewModel = AIChatSuggestionsViewModel(maxSuggestions: chatSuggestionsReader.maxHistoryCount)
        chatManager = AIChatHistoryManager(
            suggestionsReader: chatSuggestionsReader,
            aiChatSettings: aiChatSettings,
            viewModel: chatViewModel
        )

        // Build the URL-side fetcher reusing the Search-side suggestion stream + ranking.
        let dataSource = AutocompleteSuggestionsDataSource(
            historyManager: dependencies.historyManager,
            bookmarksDatabase: dependencies.bookmarksDatabase,
            featureFlagger: dependencies.featureFlagger,
            tabsModel: dependencies.tabsModelProvider()
        ) { [weak self] request, completion in
            self?.urlAutocompleteTask?.cancel()
            self?.urlAutocompleteTask = URLSession.shared.dataTask(with: request) { data, _, error in
                completion(data, error)
            }
            self?.urlAutocompleteTask?.resume()
        }
        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: dataSource)

        let coordinator = DuckAISuggestionsCoordinator(
            chatManager: chatManager,
            urlLoader: urlLoader,
            chatViewModel: chatViewModel,
            queryProvider: { [weak self] in self?.switchBarHandler.currentText ?? "" },
            layoutConfiguration: .unifiedToggleInput,
            syncPromoManager: switchBarHandler.isFireTab ? nil : syncPromoManager,
            syncService: switchBarHandler.isFireTab ? nil : syncService
        )
        coordinator.delegate = self
        coordinator.onContentChanged = { [weak self] in
            // Dax visibility and section composition depend on coordinator content.
            self?.refreshVisibleContent(suggestionRefresh: .none, animateContentUpdates: true)
        }

        chatManager.onFetchCompleted = { [weak self] _, _ in
            self?.updateDaxVisibility()
        }

        swipeContainerManager.installDuckAISuggestions(using: coordinator, textPublisher: switchBarHandler.currentTextPublisher)
        coordinator.setAdditionalTopInset(escapeHatchTopInset)
        coordinator.setEscapeHatch(switchBarHandler.isFireTab ? nil : escapeHatchModel)

        duckAISuggestionsCoordinator = coordinator
        updateDuckAISuggestionsActiveState()
    }

    private func installDaxLogoView() {
        daxLogoManager.installInViewController(self, asSubviewOf: contentContainerView, isTopBarPosition: false)
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
        daxLogoManager.setFireTabContentInsets(insets)
        guard swipeContainerManager?.containerViewController.additionalSafeAreaInsets != insets else { return }
        swipeContainerManager?.containerViewController.additionalSafeAreaInsets = insets
        // layoutIfNeeded inside the active CATransaction so the inset change animates with the parent.
        swipeContainerManager?.containerViewController.view.layoutIfNeeded()
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
        let isShowingDuckAISuggestions = duckAISuggestionsCoordinator?.hasContent == true
        // Suppress the Duck.ai empty state (Dax) whenever fetchers haven't settled for the
        // current query — covers both the initial-load window and the keystroke-to-result lag,
        // which would otherwise cause Dax to flash when the user backspaces to empty after
        // a no-match query (one fetcher's empty result lands before the other's).
        let isDuckAISuggestionsPending = duckAISuggestionsCoordinator != nil
            && duckAISuggestionsCoordinator?.hasSettled(forQuery: switchBarHandler.currentText) != true
            && switchBarHandler.currentToggleState == .aiChat
            && !switchBarHandler.isFireTab

        let hasContent = (shouldDisplaySuggestionTray && isShowingTray) || isHorizontallyCompactLayoutEnabled
        let homeDaxInputs = HomeDaxInputs(
            hasContent: hasContent,
            shouldDisplayFavoritesOverlay: shouldDisplayFavoritesOverlay,
            hasEscapeHatch: escapeHatchModel != nil,
            hasFavorites: suggestionTrayManager?.hasFavorites ?? false,
            hasRemoteMessages: suggestionTrayManager?.hasRemoteMessages ?? false
        )
        let isSearchMode = switchBarHandler.currentToggleState == .search
        let isHomeDaxVisible = isSearchMode && daxLogoManager.shouldShowHomeDax(homeDaxInputs)
        let isAIDaxVisible = !hasContent && !isShowingDuckAISuggestions && !isDuckAISuggestionsPending

        daxLogoManager.updateVisibility(isHomeDaxVisible: isHomeDaxVisible, isAIDaxVisible: isAIDaxVisible)
        // The toolbar is still in the hierarchy under the unified input, so the keyboard-relative
        // centering sits visually too high — shift the dax down by this constant to compensate.
        // The escape hatch sits in the suggestion tray above the logo and doesn't push it down.
        daxLogoManager.setEscapeHatchBaseOffset(Metrics.toolbarCompensationOffset)
        updateSectionTitle()
    }

    private enum Metrics {
        static let horizontalMarginForCompactLayout: CGFloat = 108
        static let backgroundColor = UIColor(designSystemColor: .panel)
        static let contentTopInset: CGFloat = 10
        // Pulls both the search and duck.ai suggestion trays up so the UTI escape
        // hatch lines up with the NTP escape hatch. The suggestion tray container
        // chain positions the UTI hatch ~10pt below the NTP equivalent.
        static let escapeHatchTrayPullUp: CGFloat = -10
        static let toolbarCompensationOffset: CGFloat = 80
        static let suggestionsHorizontalInset: CGFloat = 8
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
        // Duck.ai mode now renders chats / URLs / search-DDG inline via DuckAISuggestionsCoordinator,
        // so there's no fallback toggling to do here. Search mode is unchanged — the suggestion tray
        // decides its own visibility from query state.
        updateDuckAISuggestionsActiveState()
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
        // URL fallback is gone — Duck.ai mode no longer needs the Search page kept visible.
        return false
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
        delegate?.unifiedInputEditingStateDidRequestTextUpdate(text)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsEditFavorite favorite: BookmarkEntity) {
        delegate?.unifiedInputEditingStateDidEditFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsSwitchToTab tab: Tab) {
        delegate?.unifiedInputEditingStateDidRequestSwitchTab(tab)
    }

    func suggestionTrayManagerDidRequestTabSwitcher(_ manager: SuggestionTrayManager) {
        delegate?.unifiedInputEditingStateDidRequestTabSwitcher()
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

// MARK: - DuckAISuggestionsCoordinatorDelegate

extension UnifiedInputContentContainerViewController: DuckAISuggestionsCoordinatorDelegate {

    func duckAISuggestionsDidSelectChat(_ chat: AIChatSuggestion) {
        let pixel: Pixel.Event = chat.isPinned ? .aiChatRecentChatSelectedPinned : .aiChatRecentChatSelected
        DailyPixel.fireDailyAndCount(pixel: pixel)
        Pixel.fire(pixel: .autocompleteDuckAIClickChatHistory)

        let url = aiChatSettings.aiChatURL.withChatID(chat.chatId)
        delegate?.unifiedInputEditingStateDidSelectChatHistory(url: url)
    }

    func duckAISuggestionsDidSelectURL(_ suggestion: Suggestion) {
        fireDuckAISuggestionClickPixel(for: suggestion)
        delegate?.unifiedInputEditingStateDidSelectSuggestion(suggestion)
    }

    func duckAISuggestionsDidSelectSearchDuckDuckGo(query: String) {
        Pixel.fire(pixel: .autocompleteDuckAIClickSearchDuckDuckGo)
        // Symmetric with Search-side "Ask privately" (which calls openAIChat with autoSend:true):
        // flip toggle to Search and submit the query in one step.
        switchBarHandler.setToggleState(.search)
        delegate?.unifiedInputEditingStateDidSubmitQuery(query)
    }

    func duckAISuggestionsDidRequestSyncSetup() {
        aiChatSyncIntroSheetPresenter.present(from: self) { [weak self] in
            self?.delegate?.unifiedInputEditingStateDidRequestSyncSetup()
        }
    }

    private func fireDuckAISuggestionClickPixel(for suggestion: Suggestion) {
        switch suggestion {
        case .website:
            Pixel.fire(pixel: .autocompleteDuckAIClickWebsite)
        case .bookmark(_, _, let isFavorite, _):
            Pixel.fire(pixel: isFavorite ? .autocompleteDuckAIClickFavorite : .autocompleteDuckAIClickBookmark)
        case .historyEntry(_, let url, _):
            Pixel.fire(pixel: url.isDuckDuckGoSearch ? .autocompleteDuckAIClickHistorySearch : .autocompleteDuckAIClickHistorySite)
        case .openTab:
            Pixel.fire(pixel: .autocompleteDuckAIClickSwitchToTab)
        case .phrase, .internalPage, .unknown, .askAIChat:
            break
        }
    }
}
