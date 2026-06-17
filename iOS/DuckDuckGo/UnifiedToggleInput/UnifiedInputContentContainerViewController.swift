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
import SwiftUI
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
    func unifiedInputEditingStateDidSelectViewAllChats()
    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: Tab)
    func unifiedInputEditingStateDidRequestTabSwitcher()
    func unifiedInputEditingStateDidRequestTryFireMode()
    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode)
    func unifiedInputEditingStateDidRequestSyncSetup()
}

final class UnifiedInputContentContainerViewController: UIViewController {


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
    private let aiChatSyncCleaner: AIChatSyncCleaning?
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
    /// The lazily-attached duck.ai surface (source + fetchers + state feed); nil while detached.
    private var duckAISurface: DuckAISuggestionsSurfaceProvider?
    /// Stable merge input for the inputs publisher; the surface's state is relayed into it while
    /// attached, and it reverts to nil on detach (the merger treats nil as no recents / nothing pending).
    private let duckAIStateRelay = CurrentValueSubject<UnifiedSuggestionsInputsMerger.DuckAIState?, Never>(nil)
    /// Bridges `duckAISurface.statePublisher → duckAIStateRelay`; cleared on detach.
    private var duckAIRelayCancellables = Set<AnyCancellable>()
    /// In-flight search history-delete task; cancelled on deinit so its post-delete refetch can't
    /// run against a torn-down loader (parity with the duck.ai surface's `deleteTask`).
    private var searchDeleteTask: Task<Void, Never>?
    /// The Search surface's loader; held so a Duck.ai-side URL delete can refresh it too.
    private var searchLoader: SearchSuggestionsLoader?
    /// The Search surface's data source; held so its bookmark cache can be refreshed each session.
    private var searchDataSource: AutocompleteSuggestionsDataSource?
    /// Duck.ai sync-promo presenter; nil when there's no sync service.
    private lazy var aiChatSyncPromoViewModel: AIChatSyncPromoViewModel? =
        syncPromoManager.map { AIChatSyncPromoViewModel(syncPromoManager: $0) }
    /// Built once — its show/hide is driven reactively by `setSyncPromoVisible`, so there's no need
    /// to reconstruct it on every `updateSyncPromo`.
    private lazy var syncPromoView = AnyView(AIChatSyncPromoView(
        onCTATap: { [weak self] in self?.handleSyncPromoCTATap() },
        onCloseTap: { [weak self] in self?.handleSyncPromoClose() }))
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
         aiChatSyncCleaner: AIChatSyncCleaning? = nil,
         aiChatSyncIntroSheetPresenter: AIChatSyncIntroSheetPresenting = AIChatSyncIntroSheetPresenter()) {
        self.switchBarHandler = switchBarHandler
        self.daxLogoManager = DaxLogoManager(isFireTab: switchBarHandler.isFireTab)
        self.daxLogoManager.usesLottieTransition = true
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.aiChatSettings = aiChatSettings
        self.aiChatSyncCleaner = aiChatSyncCleaner
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

    deinit {
        searchDeleteTask?.cancel()
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

    /// Rebuilds the search suggestions' session-scoped caches (currently the bookmark snapshot) so a
    /// long-lived data source reflects add/remove since the last editing session. Called on each
    /// omnibar-editing show — legacy got this for free by building a fresh data source per session.
    func refreshSuggestionsCaches() {
        searchDataSource?.refreshCaches()
        duckAISurface?.refreshCaches()
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
        refreshVisibleContent(animateContentUpdates: false)
    }

    func setActive(_ active: Bool) {
        guard active != isContentActive else { return }
        isContentActive = active
        markNeedsVisibleRefresh()
        if active {
            duckAISurface?.refreshRecents()
        }
    }

    func refreshVisibleContentIfNeeded() {
        guard isContentActive else { return }
        guard needsVisibleRefresh else { return }

        refreshVisibleContent(animateContentUpdates: false)
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
        modeSwitchSwipeController.install(on: view)
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

    /// Routes the swipe through the coordinator (like a toggle tap) so the toggle UI, content, and
    /// the Dax morph all update — a raw `setToggleState` doesn't propagate the switch at all.
    private lazy var modeSwitchSwipeController = ModeSwitchSwipeGestureController { [weak self] targetMode in
        guard let self, switchBarHandler.currentToggleState != targetMode else { return }
        delegate?.unifiedInputEditingStateDidChangeMode(targetMode)
    }

    /// Suppresses the content mode-switch swipe (e.g. while the toggle pill is being dragged).
    var isSwipeEnabled: Bool {
        get { modeSwitchSwipeController.isEnabled }
        set { modeSwitchSwipeController.isEnabled = newValue }
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
        let loader = SearchSuggestionsLoader(dataSource: dataSource, useUnifiedURLPrediction: featureFlagger.isFeatureOn(.unifiedURLPredictor))
        searchLoader = loader
        searchDataSource = dataSource

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

        let searchStateChanged = dependencies.favoritesViewModel.localUpdates
            .merge(with: dependencies.favoritesViewModel.externalUpdates)
            // Favorites changes fire on the Core Data context queue; marshal here so the merged
            // inputs (and the view model's `@Published content` mutation) stay on main.
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
        let inputsPublisher = makeMergedInputsPublisher(hasFavorites: hasFavorites,
                                                        hasMessages: hasMessages,
                                                        searchStateChanged: searchStateChanged)

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
                self.searchDeleteTask = Task { [weak self] in
                    await SuggestionHistoryDeletion.delete(url, using: dependencies.historyManager)
                    guard let self, !Task.isCancelled else { return }
                    loader?.fetch(query: self.switchBarHandler.currentText)
                    self.duckAISurface?.refreshURLSuggestions()
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
            self?.refreshVisibleContent(animateContentUpdates: true)
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

        // Search only fetches in `.search` mode — in Duck.ai the typed prompt must not hit the search
        // autocomplete endpoint (legacy parity; Duck.ai runs its own URL loader). Filter (pause) rather
        // than mapping to "": dropping off-mode emissions preserves the last results, and toggling back
        // with unchanged text is deduped — so no clear-and-refetch flicker on every toggle.
        let searchTextPublisher = Publishers.CombineLatest(
            switchBarHandler.toggleStatePublisher,
            switchBarHandler.currentTextPublisher)
            .filter { mode, _ in mode == .search }
            .map { _, text in text }
            .removeDuplicates()
            .eraseToAnyPublisher()

        host.start(in: containerView,
                   parentViewController: self,
                   textPublisher: searchTextPublisher)
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
                                           searchStateChanged: AnyPublisher<Void, Never>) -> AnyPublisher<UnifiedSuggestionsInputs, Never> {
        // `searchStateChanged` re-resolves when favorites/messages change without a text/toggle change
        // (e.g. a just-added favorite that loads a beat after a new tab opens, or deleting the last
        // one). The model notifies after refreshing its array, so the reads below are fresh.
        Publishers.CombineLatest4(
            switchBarHandler.toggleStatePublisher,
            Publishers.CombineLatest(switchBarHandler.currentTextPublisher,
                                     switchBarHandler.hasUserInteractedWithTextPublisher),
            duckAIStateRelay,
            searchStateChanged.prepend(())
        )
        .map { mode, textState, duckAIState, _ -> UnifiedSuggestionsInputs in
            let (text, hasUserInteractedWithText) = textState
            return UnifiedSuggestionsInputsMerger.merge(
                mode: mode,
                text: text,
                hasUserInteractedWithText: hasUserInteractedWithText,
                search: .init(hasFavorites: hasFavorites(), hasMessages: hasMessages()),
                duckAI: duckAIState)
        }
        .eraseToAnyPublisher()
    }

    /// Lazily builds `DuckAISuggestionsSurfaceProvider`, relays its state into the merge input, and attaches
    /// it to the single host. No-op if already attached or duck.ai suggestions are disabled.
    private func attachDuckAISurfaceIfNeeded() {
        guard duckAISurface == nil,
              let host = unifiedSuggestionsHost,
              featureFlagger.isFeatureOn(.aiChatSuggestions),
              aiChatSettings.isChatSuggestionsEnabled,
              let dependencies = suggestionTrayDependencies else { return }

        let surface = DuckAISuggestionsSurfaceProvider(
            switchBarHandler: switchBarHandler,
            dependencies: dependencies,
            aiChatSettings: aiChatSettings,
            aiChatSyncCleaner: aiChatSyncCleaner,
            featureFlagger: featureFlagger,
            privacyConfigurationManager: privacyConfigurationManager,
            duckAiNativeStorageHandler: duckAiNativeStorageHandler
        )
        surface.delegate = self
        surface.statePublisher
            .sink { [weak self] in self?.duckAIStateRelay.send($0) }
            .store(in: &duckAIRelayCancellables)
        surface.attach(to: host, textPublisher: switchBarHandler.currentTextPublisher.eraseToAnyPublisher())
        duckAISurface = surface
    }

    /// Detaches the duck.ai surface and reverts the merge input to nil (no recents / nothing pending).
    private func detachDuckAISurfaceFromSingleHost() {
        guard let surface = duckAISurface else { return }
        if let host = unifiedSuggestionsHost { surface.detach(from: host) }
        duckAIRelayCancellables.removeAll()
        duckAIStateRelay.send(nil)
        duckAISurface = nil
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

    private func rebuildDuckAISuggestionsCoordinator() {
        guard duckAISurface != nil else { return }
        detachDuckAISurfaceFromSingleHost()
        attachDuckAISurfaceIfNeeded()
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
                self.refreshVisibleContent(animateContentUpdates: true)
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
                self.refreshVisibleContent(animateContentUpdates: false)
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
        contentContainerView.layoutIfNeeded()
    }

    private func updateDaxVisibility() {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }

        let hasFavorites: Bool
        let hasRemoteMessages: Bool
        if let deps = suggestionTrayDependencies {
            hasFavorites = !deps.favoritesViewModel.favorites.isEmpty
            hasRemoteMessages = !deps.newTabPageDependencies.homePageMessagesConfiguration.homeMessages.isEmpty
        } else {
            hasFavorites = false
            hasRemoteMessages = false
        }

        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: view.bounds.size)
        let text = switchBarHandler.currentText
        let searchState = UnifiedSuggestionsInputsMerger.SearchState(hasFavorites: hasFavorites, hasMessages: hasRemoteMessages)
        let duckAIState = duckAIStateRelay.value

        // The dax derives from the SAME resolver that decides content: a side shows its logo exactly
        // when it resolves to `.logo`. Resolving both modes keeps the swipe-morph's two empty states
        // available; landscape suppresses both.
        func resolvesToLogo(_ mode: TextEntryMode) -> Bool {
            let inputs = UnifiedSuggestionsInputsMerger.merge(
                mode: mode,
                text: text,
                hasUserInteractedWithText: switchBarHandler.hasUserInteractedWithText,
                search: searchState,
                duckAI: duckAIState)
            return UnifiedSuggestionsContentResolver.resolve(inputs, previous: nil) == .logo
        }

        let isHomeDaxVisible = !isHorizontallyCompactLayoutEnabled && resolvesToLogo(.search)
        let isAIDaxVisible = !isHorizontallyCompactLayoutEnabled && resolvesToLogo(.aiChat)

        daxLogoManager.updateVisibility(isHomeDaxVisible: isHomeDaxVisible, isAIDaxVisible: isAIDaxVisible, committedMode: switchBarHandler.currentToggleState)
        daxLogoManager.setEscapeHatchBaseOffset(daxVerticalOffset(hasEscapeHatch: escapeHatchModel != nil))
        updateSyncPromo()
    }

    /// Shows the Duck.ai sync-promo card below the escape hatch in the not-typing state, mirroring
    /// the legacy Duck.ai suggestions header. Gated by the sync-promo manager + recents count.
    private func updateSyncPromo() {
        guard let promoViewModel = aiChatSyncPromoViewModel, let host = unifiedSuggestionsHost else { return }
        // Install the card once (the host guards on presence); its show/hide is then a reactive
        // view-model change driven by `setSyncPromoVisible`.
        host.setSyncPromo(syncPromoView)

        let isTyping = !switchBarHandler.currentText.isEmpty
        let shouldShow = switchBarHandler.currentToggleState == .aiChat
            && !switchBarHandler.isFireTab
            && (duckAISurface?.isAttached ?? false)
            && promoViewModel.shouldShowPromo(isQueryActive: isTyping, chatCount: duckAISurface?.recentsCount ?? 0)

        host.setSyncPromoVisible(shouldShow)
        promoViewModel.recordImpressionIfNeeded(isVisibleContent: isContentActive, isPromoVisible: shouldShow)
    }

    private func handleSyncPromoCTATap() {
        if aiChatSyncPromoViewModel?.handleCTATap() == .requestSyncSetup {
            duckAISuggestionsDidRequestSyncSetup()
        }
        updateSyncPromo()
    }

    private func handleSyncPromoClose() {
        aiChatSyncPromoViewModel?.handleCloseTap()
        updateSyncPromo()
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
                self.refreshVisibleContent(animateContentUpdates: false)
            }
            .store(in: &cancellables)
    }


    private func refreshVisibleContent(animateContentUpdates: Bool) {
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

// MARK: - DuckAISuggestionsSurfaceProviderDelegate

extension UnifiedInputContentContainerViewController: DuckAISuggestionsSurfaceProviderDelegate {

    func duckAISurfaceDidSelect(_ selection: DuckAISuggestionsSelection) {
        switch selection {
        case .chat(let chat): duckAISuggestionsDidSelectChat(chat)
        case .url(let suggestion): duckAISuggestionsDidSelectURL(suggestion)
        case .searchDuckDuckGo(let query): duckAISuggestionsDidSelectSearchDuckDuckGo(query: query)
        case .viewAllChats: delegate?.unifiedInputEditingStateDidSelectViewAllChats()
        }
    }

    func duckAISurfaceStateDidChange() {
        updateDaxVisibility()
    }

    func duckAISurfaceDidDeleteURLSuggestion() {
        // The deleted URL was removed from the shared history store; refresh Search so it doesn't
        // linger there (the gated search loader won't re-fetch on a plain mode toggle).
        searchLoader?.fetch(query: switchBarHandler.currentText)
    }

    func duckAISurfaceRequestsChatDeletionConfirmation(for chat: AIChatSuggestion,
                                                       onConfirm: @escaping () -> Void,
                                                       onCancel: @escaping () -> Void) {
        guard let source = unifiedSuggestionsContainerView ?? view else { return }
        FireConfirmationPresenter.presentFireConfirmation(suggestion: chat,
                                                          presenter: self,
                                                          source: source,
                                                          onCancel: onCancel,
                                                          onConfirm: onConfirm)
    }
}

// MARK: - Duck.ai suggestion selection handling

extension UnifiedInputContentContainerViewController {

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
