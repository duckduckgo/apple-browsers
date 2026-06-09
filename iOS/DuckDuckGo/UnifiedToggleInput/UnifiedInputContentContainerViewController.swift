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
import os

let utiTransitionLog = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "UTITransition")

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
    private var isUsingTopBarPosition: Bool {
        didSet {
            updateSingleHostTopOffset()
            unifiedSuggestionsHost?.setIsAddressBarAtBottom(!isUsingTopBarPosition)
        }
    }
    private var isAdjustedForTopBar: Bool

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

    /// The one resolver-driven host that serves both surfaces; its container pinned directly in
    /// `contentContainerView`.
    private var unifiedSuggestionsHost: UnifiedSuggestionsHost?
    private var unifiedSuggestionsContainerView: UIView?
    /// Single-host path: the suggestions container's top offset (input height + hatch) lives on this
    /// constraint, not the hosting view's safe-area inset — so the whole content (incl. the escape
    /// hatch) glides natively with the input instead of SwiftUI snapping the safe-area reposition.
    private var unifiedSuggestionsTopConstraint: NSLayoutConstraint?
    /// Feeds the merged inputs publisher with the duck.ai facts; nil while the duck.ai surface is
    /// detached (the merger treats absent facts as no recents / nothing pending).
    private let duckAIFactsSubject = CurrentValueSubject<UnifiedSuggestionsInputsMerger.DuckAIFacts?, Never>(nil)
    /// Reads the live duck.ai settle/content facts for `updateDaxVisibility` on the single-host path.
    private var duckAIHasContent: (() -> Bool)?
    private var duckAIHasSettled: ((String) -> Bool)?
    /// Re-reads the duck.ai recent chats from storage. Called on each activation so a chat removed
    /// elsewhere (e.g. burned) doesn't linger — the surface is built once, so it won't re-read itself.
    private var refreshDuckAIRecents: (() -> Void)?
    /// Held only while the duck.ai surface is attached on the single host; cleared on detach.
    private var duckAISurfaceCancellables = Set<AnyCancellable>()
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

        updateDaxVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        attachDuckAISurfaceIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        detachDuckAISurfaceFromSingleHost()
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

    func setInputMode(_ mode: TextEntryMode, animated: Bool = true) {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        let didModeChange = switchBarHandler.currentToggleState != mode
        if didModeChange {
            switchBarHandler.setToggleState(mode)
        }
        let suggestionRefresh: SuggestionRefreshStrategy = mode == .search ? .currentState : .none
        refreshVisibleContent(suggestionRefresh: suggestionRefresh, animateContentUpdates: false)
    }

    func setActive(_ active: Bool) {
        guard active != isContentActive else { return }
        isContentActive = active
        markNeedsVisibleRefresh()
        if active {
            refreshDuckAIRecents?()
        }
    }

    func refreshVisibleContentIfNeeded() {
        guard isContentActive else { return }
        guard needsVisibleRefresh else { return }

        refreshVisibleContent(
            suggestionRefresh: currentModeSuggestionRefresh(),
            animateContentUpdates: false
        )
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        let hatchPresenceChanged = (escapeHatchModel != nil) != (model != nil)
        escapeHatchModel = model
        // Fire tabs render their own empty state via DaxLogoManager — suppress the hatch to avoid stacking affordances.
        let nonFireHatchModel = switchBarHandler.isFireTab ? nil : model
        unifiedSuggestionsHost?.setEscapeHatch(nonFireHatchModel)
        updateSingleHostTopOffset()
        // The dax offset depends on hatch presence (`hatchClearance` is added when present),
        // so refresh visibility when the hatch is added or removed mid-session.
        if hatchPresenceChanged {
            updateDaxVisibility()
        }
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
        setUpModeSwitchSwipeGestures()
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

    /// Horizontal swipe over the content switches Search↔Duck.ai (Search is the left page), mirroring
    /// a toggle tap. A quick flick triggers it; slow horizontal drags (e.g. row swipe-to-delete) don't.
    private func setUpModeSwitchSwipeGestures() {
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleModeSwitchSwipe(_:)))
            swipe.direction = direction
            swipe.cancelsTouchesInView = false
            view.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleModeSwitchSwipe(_ gesture: UISwipeGestureRecognizer) {
        let targetMode: TextEntryMode = gesture.direction == .left ? .aiChat : .search
        guard switchBarHandler.currentToggleState != targetMode else { return }
        // Route through the coordinator (like a toggle tap) so the toggle UI, content, and the Dax
        // logo morph all update — a raw `setToggleState` doesn't propagate the switch at all.
        delegate?.unifiedInputEditingStateDidChangeMode(targetMode)
    }

    private func installComponents() {
        installUnifiedSuggestionsHost()
        installDaxLogoView()
    }

    // MARK: - Single suggestions host

    /// Builds ONE resolver-driven host serving both surfaces. The search source is permanent; the
    /// duck.ai source is attached lazily (mirroring the legacy lifecycle). Both keep their OWN
    /// `AutocompleteRequestRunner`/loaders so the Part 2b mutual DDG-request cancellation fix holds.
    private func installUnifiedSuggestionsHost() {
        guard let dependencies = suggestionTrayDependencies else { return }

        let requestRunner = AutocompleteRequestRunner()
        let dataSource = AutocompleteSuggestionsDataSource(
            historyManager: dependencies.historyManager,
            bookmarksDatabase: dependencies.bookmarksDatabase,
            featureFlagger: dependencies.featureFlagger,
            tabsModel: dependencies.tabsModelProvider()
        ) { request, completion in
            requestRunner.run(request, completion: completion)
        }
        let loader = SearchSuggestionsLoader(dataSource: dataSource)

        let source = SearchSuggestionsSource(
            loader: loader,
            query: { [weak self] in self?.switchBarHandler.currentText ?? "" },
            showAskAIChat: aiChatSettings.isAIChatEnabled
        )

        let hasFavorites: () -> Bool = {
            !dependencies.favoritesViewModel.favorites.isEmpty
        }
        let hasMessages: () -> Bool = {
            !dependencies.newTabPageDependencies.homePageMessagesConfiguration.homeMessages.isEmpty
        }

        let searchFactsChanged = dependencies.favoritesViewModel.localUpdates
            .merge(with: dependencies.favoritesViewModel.externalUpdates)
            .eraseToAnyPublisher()
        let inputsPublisher = makeMergedInputsPublisher(hasFavorites: hasFavorites,
                                                        hasMessages: hasMessages,
                                                        searchFactsChanged: searchFactsChanged)

        let config = UnifiedSuggestionsHostConfig(
            source: source,
            inputsPublisher: inputsPublisher,
            isAddressBarAtBottom: !isUsingTopBarPosition,
            favoritesProvider: { [weak self] in self?.makeSearchFavoritesController() },
            onSelectRow: { [weak self] id in
                guard let suggestion = source.suggestion(forRowID: id) else { return }
                self?.delegate?.unifiedInputEditingStateDidSelectSuggestion(suggestion)
            },
            onDeleteRow: { [weak self, weak loader] id in
                guard let self,
                      let suggestion = source.suggestion(forRowID: id),
                      case .historyEntry(_, let url, _) = suggestion else { return }
                Task {
                    await dependencies.historyManager.deleteHistoryForURL(url)
                    loader?.fetch(query: self.switchBarHandler.currentText)
                }
            },
            onTapAheadRow: { [weak self] id in
                guard let suggestion = source.suggestion(forRowID: id) else { return }
                switch suggestion {
                case .phrase(let phrase): self?.delegate?.unifiedInputEditingStateDidRequestTextUpdate(phrase)
                case .website(let url): self?.delegate?.unifiedInputEditingStateDidRequestTextUpdate(url.absoluteString)
                default: break
                }
            },
            hasContent: { [weak self] in
                !(self?.switchBarHandler.currentText.isEmpty ?? true)
            },
            hasSettled: { [weak loader] query in
                loader?.lastCompletedFetchQuery == query
            }
        )

        let host = UnifiedSuggestionsHost(config: config)
        host.onContentChanged = { [weak self] in
            self?.refreshVisibleContent(suggestionRefresh: .none, animateContentUpdates: true)
        }

        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(containerView)
        let topConstraint = containerView.topAnchor.constraint(equalTo: contentContainerView.topAnchor)
        unifiedSuggestionsTopConstraint = topConstraint
        NSLayoutConstraint.activate([
            topConstraint,
            containerView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])
        unifiedSuggestionsContainerView = containerView

        host.start(in: containerView,
                   parentViewController: self,
                   textPublisher: switchBarHandler.currentTextPublisher)
        // The top offset rides the container constraint (UIKit glide); the hosting view keeps no
        // top safe-area inset of its own.
        host.setAdditionalTopInset(0)
        updateSingleHostTopOffset()
        host.setEscapeHatch(switchBarHandler.isFireTab ? nil : escapeHatchModel)
        unifiedSuggestionsHost = host
    }

    /// Single-host path: the suggestions container aligns with the new-tab page (the favorites
    /// surface IS the NTP, and the hatch lines up with the NTP hatch), so it rides the requested
    /// inset directly. The constant animates natively, so the hatch glides with the input.
    private func updateSingleHostTopOffset() {
        unifiedSuggestionsTopConstraint?.constant = requestedContentInset.top + topBarContentGap
    }

    /// With a top address bar the input sits above the content, so the content needs a small gap
    /// beneath it. With a bottom bar the content is anchored to the top of the screen (the input is
    /// below it), so no gap applies — and adding one there pushes the favorites below the NTP.
    private var topBarContentGap: CGFloat {
        isUsingTopBarPosition ? Metrics.topBarContentClearance : 0
    }

    /// One merged inputs stream feeding the single host: mode + text + search facts (always) +
    /// duck.ai facts (nil while detached). Combines via the pure `UnifiedSuggestionsInputsMerger`.
    private func makeMergedInputsPublisher(hasFavorites: @escaping () -> Bool,
                                           hasMessages: @escaping () -> Bool,
                                           searchFactsChanged: AnyPublisher<Void, Never>) -> AnyPublisher<UnifiedSuggestionsInputs, Never> {
        // `searchFactsChanged` re-resolves when favorites/messages change without a text/toggle change
        // (e.g. a just-added favorite that loads a beat after a new tab opens, or deleting the last
        // one). The model notifies after refreshing its array, so the reads below are fresh.
        Publishers.CombineLatest4(
            switchBarHandler.toggleStatePublisher,
            switchBarHandler.currentTextPublisher,
            duckAIFactsSubject,
            searchFactsChanged.prepend(())
        )
        .map { mode, text, duckAIFacts, _ -> UnifiedSuggestionsInputs in
            UnifiedSuggestionsInputsMerger.merge(
                mode: mode,
                text: text,
                search: .init(hasFavorites: hasFavorites(), hasMessages: hasMessages()),
                duckAI: duckAIFacts)
        }
        .eraseToAnyPublisher()
    }

    /// Builds the duck.ai source with its OWN runner/loaders, wires its facts into
    /// `duckAIFactsSubject`, and attaches it to the single host.
    private func attachDuckAISurfaceToSingleHost() {
        guard let host = unifiedSuggestionsHost,
              duckAIHasContent == nil,
              let dependencies = suggestionTrayDependencies else { return }

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

        let requestRunner = AutocompleteRequestRunner()
        let dataSource = AutocompleteSuggestionsDataSource(
            historyManager: dependencies.historyManager,
            bookmarksDatabase: dependencies.bookmarksDatabase,
            featureFlagger: dependencies.featureFlagger,
            tabsModel: dependencies.tabsModelProvider()
        ) { request, completion in
            requestRunner.run(request, completion: completion)
        }
        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: dataSource)

        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            chatManager: chatManager,
            query: { [weak self] in self?.switchBarHandler.currentText ?? "" }
        )
        chatManager.onFetchCompleted = { [weak self] _, _ in self?.updateDaxVisibility() }

        Publishers.CombineLatest(
            chatViewModel.$filteredSuggestions.map { !$0.isEmpty },
            urlLoader.$topURLs.map { _ in () }.prepend(())
        )
        .map { [weak chatManager, weak urlLoader, weak self] hasRecents, _ -> UnifiedSuggestionsInputsMerger.DuckAIFacts in
            let query = self?.switchBarHandler.currentText ?? ""
            let settled = chatManager?.lastCompletedFetchQuery == query
                && urlLoader?.lastCompletedFetchQuery == query
            return .init(hasRecents: hasRecents, settled: settled)
        }
        .sink { [weak self] facts in self?.duckAIFactsSubject.send(facts) }
        .store(in: &duckAISurfaceCancellables)

        let queryProvider = { [weak self] in self?.switchBarHandler.currentText ?? "" }
        let surface = UnifiedSuggestionsDuckAISurface(
            source: source,
            onSelectRow: { [weak self] id in self?.handleDuckAISuggestionSelect(id, source: source) },
            onDeleteRow: { [weak self] id in self?.handleDuckAISuggestionDelete(id, source: source, queryProvider: queryProvider, dependencies: dependencies) },
            onTapAheadRow: { [weak self] id in self?.handleDuckAISuggestionSelect(id, source: source) }
        )

        duckAIHasContent = { [weak chatViewModel, weak urlLoader, weak self] in
            !(chatViewModel?.filteredSuggestions.isEmpty ?? true)
                || !(urlLoader?.topURLs.isEmpty ?? true)
                || !(self?.switchBarHandler.currentText.isEmpty ?? true)
        }
        duckAIHasSettled = { [weak chatManager, weak urlLoader] query in
            chatManager?.lastCompletedFetchQuery == query
                && urlLoader?.lastCompletedFetchQuery == query
        }
        refreshDuckAIRecents = { [weak chatManager, weak self] in
            chatManager?.refreshSuggestions(query: self?.switchBarHandler.currentText ?? "")
        }

        host.attachDuckAISurface(surface)
    }

    /// Single-host duck.ai detach: tears down the source/VM and clears its facts so the merger
    /// reverts to no-recents/nothing-pending. Mirrors `viewDidDisappear`'s host teardown.
    private func detachDuckAISurfaceFromSingleHost() {
        guard duckAIHasContent != nil else { return }
        duckAISurfaceCancellables.removeAll()
        unifiedSuggestionsHost?.detachDuckAISurface()
        duckAIFactsSubject.send(nil)
        duckAIHasContent = nil
        duckAIHasSettled = nil
        refreshDuckAIRecents = nil
    }

    private func makeSearchFavoritesController() -> NewTabPageViewController? {
        guard let dependencies = suggestionTrayDependencies else { return nil }
        let ntpDeps = dependencies.newTabPageDependencies
        let controller = NewTabPageViewController(
            isFocussedState: true,
            dismissKeyboardOnScroll: aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
            tab: Tab(fireTab: dependencies.tabsModelProvider().shouldCreateFireTabs),
            interactionModel: ntpDeps.favoritesModel,
            homePageMessagesConfiguration: ntpDeps.homePageMessagesConfiguration,
            subscriptionDataReporting: ntpDeps.subscriptionDataReporting,
            newTabDialogFactory: ntpDeps.newTabDialogFactory,
            daxDialogsManager: ntpDeps.newTabDaxDialogManager,
            onboardingFlowProvider: ntpDeps.onboardingFlowProvider,
            faviconLoader: ntpDeps.faviconLoader,
            remoteMessagingActionHandler: ntpDeps.remoteMessagingActionHandler,
            remoteMessagingImageLoader: ntpDeps.remoteMessagingImageLoader,
            remoteMessagingPixelReporter: ntpDeps.remoteMessagingPixelReporter,
            fireModePromotionEligibility: ntpDeps.fireModePromotionEligibility,
            appSettings: ntpDeps.appSettings,
            faviconsCache: ntpDeps.faviconsCache,
            subscriptionManager: ntpDeps.subscriptionManager,
            internalUserCommands: ntpDeps.internalUserCommands
        )
        controller.hideBorderView()
        // Route favorite taps / edits / tab actions to the host's delegate so they open like the
        // standalone NTP (the embedded controller has no owner to set this otherwise).
        controller.delegate = self
        // The escape hatch and the empty-state Dax logo are UTI chrome (the unified view's hatch +
        // DaxLogoManager), not the NTP's — suppress the NTP's own so we never get two Dax logos.
        controller.setEscapeHatch(nil)
        controller.setLogoHidden(true)
        return controller
    }

    private func attachDuckAISurfaceIfNeeded() {
        guard duckAIHasContent == nil,
              featureFlagger.isFeatureOn(.aiChatSuggestions),
              aiChatSettings.isChatSuggestionsEnabled else { return }
        attachDuckAISurfaceToSingleHost()
    }

    private func rebuildDuckAISuggestionsCoordinator() {
        guard duckAIHasContent != nil else { return }
        detachDuckAISurfaceFromSingleHost()
        attachDuckAISurfaceIfNeeded()
    }

    private func handleDuckAISuggestionSelect(_ id: String, source: DuckAISuggestionsSource) {
        switch source.selection(forRowID: id) {
        case .chat(let chat): duckAISuggestionsDidSelectChat(chat)
        case .url(let suggestion): duckAISuggestionsDidSelectURL(suggestion)
        case .searchDuckDuckGo(let query): duckAISuggestionsDidSelectSearchDuckDuckGo(query: query)
        case .none: break
        }
    }

    private func handleDuckAISuggestionDelete(_ id: String,
                                               source: DuckAISuggestionsSource,
                                               queryProvider: @escaping () -> String,
                                               dependencies: SuggestionTrayDependencies) {
        guard case .url(let suggestion) = source.selection(forRowID: id),
              case .historyEntry(_, let url, _) = suggestion else { return }
        Task {
            await dependencies.historyManager.deleteHistoryForURL(url)
            source.fetchURLSuggestions(query: queryProvider())
        }
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
        updateSingleHostTopOffset()
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
        // Top offset → container constraint (UIKit glide); only the bottom inset stays on the
        // hosting view. layoutIfNeeded inside the active animation makes the constraint glide.
        updateSingleHostTopOffset()
        unifiedSuggestionsHost?.setContentInsets(UIEdgeInsets(top: 0, left: 0, bottom: insets.bottom, right: 0))
        utiTransitionLog.debug("applyContentInset(single) topConst=\(self.unifiedSuggestionsTopConstraint?.constant ?? -1, privacy: .public) animated=\(UIView.inheritedAnimationDuration > 0, privacy: .public) mode=\(String(describing: self.switchBarHandler.currentToggleState), privacy: .public)")
        contentContainerView.layoutIfNeeded()
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

        let shouldDisplaySuggestionTray: Bool
        let isShowingTray: Bool
        let shouldDisplayFavoritesOverlay: Bool
        let hasFavorites: Bool
        let hasRemoteMessages: Bool

        if let deps = suggestionTrayDependencies {
            // Facts come from dependencies directly; tray is not installed.
            let isTyping = !switchBarHandler.currentText.isBlank
            let favs = !deps.favoritesViewModel.favorites.isEmpty
            let msgs = !deps.newTabPageDependencies.homePageMessagesConfiguration.homeMessages.isEmpty
            shouldDisplaySuggestionTray = isTyping
            isShowingTray = isTyping
            hasFavorites = favs
            hasRemoteMessages = msgs
            shouldDisplayFavoritesOverlay = !switchBarHandler.isFireTab && !isTyping && (favs || msgs)
        } else {
            shouldDisplaySuggestionTray = false
            isShowingTray = false
            shouldDisplayFavoritesOverlay = false
            hasFavorites = false
            hasRemoteMessages = false
        }

        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: view.bounds.size)
        let duckAIIsAttached = duckAIHasContent != nil
        let isShowingDuckAISuggestions = duckAIHasContent?() == true
        let isDuckAISettled = duckAIHasSettled?(switchBarHandler.currentText) == true
        // Suppress the Duck.ai empty state (Dax) whenever fetchers haven't settled for the
        // current query — covers both the initial-load window and the keystroke-to-result lag,
        // which would otherwise cause Dax to flash when the user backspaces to empty after
        // a no-match query (one fetcher's empty result lands before the other's).
        let isDuckAISuggestionsPending = duckAIIsAttached
            && !isDuckAISettled
            && switchBarHandler.currentToggleState == .aiChat
            && !switchBarHandler.isFireTab

        let hasContent = (shouldDisplaySuggestionTray && isShowingTray) || isHorizontallyCompactLayoutEnabled
        let homeDaxInputs = HomeDaxInputs(
            hasContent: hasContent,
            shouldDisplayFavoritesOverlay: shouldDisplayFavoritesOverlay,
            hasEscapeHatch: escapeHatchModel != nil,
            hasFavorites: hasFavorites,
            hasRemoteMessages: hasRemoteMessages
        )
        let isSearchMode = switchBarHandler.currentToggleState == .search
        let isHomeDaxVisible = isSearchMode && daxLogoManager.shouldShowHomeDax(homeDaxInputs)
        let isAIDaxVisible = !hasContent && !isShowingDuckAISuggestions && !isDuckAISuggestionsPending

        utiTransitionLog.debug("updateDaxVisibility mode=\(String(describing: self.switchBarHandler.currentToggleState), privacy: .public) homeDax=\(isHomeDaxVisible, privacy: .public) aiDax=\(isAIDaxVisible, privacy: .public) duckAttached=\(duckAIIsAttached, privacy: .public) showingDuck=\(isShowingDuckAISuggestions, privacy: .public) duckPending=\(isDuckAISuggestionsPending, privacy: .public) duckSettled=\(isDuckAISettled, privacy: .public) hasContent=\(hasContent, privacy: .public) favsOverlay=\(shouldDisplayFavoritesOverlay, privacy: .public)")
        daxLogoManager.updateVisibility(isHomeDaxVisible: isHomeDaxVisible, isAIDaxVisible: isAIDaxVisible)
        daxLogoManager.setEscapeHatchBaseOffset(daxVerticalOffset(hasEscapeHatch: escapeHatchModel != nil))
    }

    /// `toolbarCompensationOffset` shifts the dax down because the toolbar still sits under the
    /// unified input — without it, the keyboard-relative centering reads visually too high.
    /// `hatchClearance` adds extra padding when the escape hatch is present so the two don't crowd.
    private func daxVerticalOffset(hasEscapeHatch: Bool) -> CGFloat {
        Metrics.toolbarCompensationOffset + (hasEscapeHatch ? Metrics.hatchClearance : 0)
    }

    private enum Metrics {
        static let horizontalMarginForCompactLayout: CGFloat = 108
        static let backgroundColor = UIColor(designSystemColor: .panel)
        static let contentTopInset: CGFloat = 10
        /// Brings the card's 8pt bottom margin up to the design's 12pt UTI bottom margin on the top bar
        /// (content then adds its own 6pt top → 18pt UTI→content, per Figma).
        static let topBarContentClearance: CGFloat = 4
        static let toolbarCompensationOffset: CGFloat = 80
        static let hatchClearance: CGFloat = 50
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
        animateContentUpdates: Bool
    ) {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }

        needsVisibleRefresh = false

        let applyContentUpdates = {
            self.updateDaxVisibility()
            self.updateSingleHostTopOffset()
            self.applyRequestedContentInset()
            self.view.layoutIfNeeded()
        }

        if animateContentUpdates {
            scheduleAnimation(applyContentUpdates)
        } else {
            applyContentUpdates()
        }
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

// MARK: - NewTabPageControllerDelegate

/// Forwards the embedded favorites NTP's actions to the host's delegate so favorites open / edit /
/// switch-tab exactly like the standalone NTP.
extension UnifiedInputContentContainerViewController: NewTabPageControllerDelegate {

    func newTabPageDidSelectFavorite(_ controller: NewTabPageViewController, favorite: BookmarkEntity) {
        delegate?.unifiedInputEditingStateDidSelectFavorite(favorite)
    }

    func newTabPageDidEditFavorite(_ controller: NewTabPageViewController, favorite: BookmarkEntity) {
        delegate?.unifiedInputEditingStateDidEditFavorite(favorite)
    }

    func newTabPageDidRequestSwitchToTab(_ controller: NewTabPageViewController, tab: Tab) {
        delegate?.unifiedInputEditingStateDidRequestSwitchTab(tab)
    }

    func newTabPageDidRequestTabSwitcher(_ controller: NewTabPageViewController) {
        delegate?.unifiedInputEditingStateDidRequestTabSwitcher()
    }

    func newTabPageDidRequestTryFireMode(_ controller: NewTabPageViewController) {
        delegate?.unifiedInputEditingStateDidRequestTryFireMode()
    }

    func newTabPageDidRequestFaviconsFetcherOnboarding(_ controller: NewTabPageViewController) {}

    func newTabPageDidDismissDuckAIExperimentCompletion(_ controller: NewTabPageViewController) {}
}
