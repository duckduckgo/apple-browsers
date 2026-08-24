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
import BrowserServicesKit
import PrivacyConfig
import Bookmarks
import Persistence
import History
import Core
import DDGSync
import Suggestions
import AIChat
import RemoteMessaging
import FeatureFlags_iOS
import os.log

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
    private let isFloatingUIEnabled: Bool
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let aiChatSettings: AIChatSettingsProvider
    private let aiChatSyncCleaner: AIChatSyncCleaning?
    private let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?
    private let syncService: DDGSyncing?
    private let syncPromoManager: SyncPromoManaging?
    private let recentModalPromptStatusProvider: RecentModalPromptStatusProviding?
    private let featureDiscovery: FeatureDiscovery
    private let autocompletePixels = AutocompleteSuggestionsPixels()

    // MARK: - Manager Components

    /// The one resolver-driven host that serves both surfaces; its container pinned directly in
    /// `contentContainerView`.
    private var unifiedSuggestionsHost: UnifiedSuggestionsHost?
    private var unifiedSuggestionsContainerView: UIView?
    /// Keeps the suggestions viewport fixed while the host's safe-area inset tracks the input height.
    /// The constraint only carries the small per-state content gap.
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
        syncPromoManager.map { AIChatSyncPromoViewModel(syncPromoManager: $0,
                                                        recentModalPromptStatusProvider: recentModalPromptStatusProvider) }
    /// Built once and inserted into the recent-chats list when eligible.
    private lazy var syncPromoView = AnyView(AIChatSyncPromoView(
        onCTATap: { [weak self] in self?.handleSyncPromoCTATap() },
        onCloseTap: { [weak self] in self?.handleSyncPromoClose() }))
    private var isContentActive = false
    /// Fires on each focus to force a fresh content resolve before the host is shown, so the prior
    /// session's stale content (a suggestion list, a logo at the wrong mark) is never flashed.
    private let activationResolveTrigger = PassthroughSubject<Void, Never>()
    private var needsVisibleRefresh = true
    private var requestedContentInset: (top: CGFloat, bottom: CGFloat) = (0, 0)
    private var escapeHatchModel: EscapeHatchModel?

    private var notificationCancellable: AnyCancellable?

    // MARK: - Initialization

    init(switchBarHandler: SwitchBarHandling,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
         syncService: DDGSyncing? = nil,
         aiChatSyncCleaner: AIChatSyncCleaning? = nil,
         recentModalPromptStatusProvider: RecentModalPromptStatusProviding? = nil,
         featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery()) {
        self.switchBarHandler = switchBarHandler
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
        self.isFloatingUIEnabled = FloatingUIManager(featureFlagger: featureFlagger).isFloatingUIEnabled
        self.privacyConfigurationManager = privacyConfigurationManager
        self.aiChatSettings = aiChatSettings
        self.aiChatSyncCleaner = aiChatSyncCleaner
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
        self.syncService = syncService
        self.syncPromoManager = syncService.map { SyncPromoManager(syncService: $0,
                                                                  featureFlagger: featureFlagger,
                                                                  privacyConfigurationManager: privacyConfigurationManager) }
        self.recentModalPromptStatusProvider = recentModalPromptStatusProvider
        self.featureDiscovery = featureDiscovery
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

        refreshSyncPromoIfActive()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        attachDuckAISurfaceIfNeeded()
    }

    /// Rebuilds the search suggestions' session-scoped caches (currently the bookmark snapshot) so a
    /// long-lived data source reflects add/remove since the last editing session. Called on each
    /// omnibar-editing show — legacy got this for free by building a fresh data source per session.
    func refreshSuggestionsCaches() {
        // Drop the persistent Search loader's stale results so they don't flash for the new query
        // (e.g. after burning all tabs). The Duck.ai surface is rebuilt per session, so it needs none.
        searchLoader?.reset()
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

    func refreshFireMode(fireMode: Bool) {
        // The fire empty state is a SwiftUI host content state now — just flip the flag; no manager rebuild.
        unifiedSuggestionsHost?.setIsFireTab(fireMode)
        refreshVisibleContent()
        rebuildDuckAISuggestionsCoordinator()

        guard isContentActive,
              let homePageMessagesConfiguration = suggestionTrayDependencies?.newTabPageDependencies.homePageMessagesConfiguration,
              homePageMessagesConfiguration.mode == .coordinated else {
            return
        }

        guard !fireMode else { return }
        homePageMessagesConfiguration.prepareForNTP(openedAfterIdle: escapeHatchModel != nil)
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool = true) {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        let didModeChange = switchBarHandler.currentToggleState != mode
        if didModeChange {
            // Publish the destination promo before the mode changes the list content, so SwiftUI
            // animates the promo and recents in one pass beneath the persistent Escape Hatch.
            updateSyncPromo(for: mode)
            switchBarHandler.setToggleState(mode)
        }
        refreshVisibleContent()
    }

    func setActive(_ active: Bool) {
        guard active != isContentActive else { return }
        isContentActive = active
        markNeedsVisibleRefresh()
        if active {
            if let homePageMessagesConfiguration = suggestionTrayDependencies?.newTabPageDependencies.homePageMessagesConfiguration,
               homePageMessagesConfiguration.mode == .coordinated,
               !switchBarHandler.isFireTab {
                homePageMessagesConfiguration.prepareForNTP(openedAfterIdle: escapeHatchModel != nil)
            }
            unifiedSuggestionsHost?.setIsFireTab(switchBarHandler.isFireTab)
            unifiedSuggestionsHost?.setLandscape(isLandscapeOrientation)
            unifiedSuggestionsHost?.prepareForActivation()
            // Re-resolve now (synchronously, before the host is shown) so the prior session's stale
            // content isn't flashed. Runs after `prepareForActivation` clears the dismiss freeze.
            activationResolveTrigger.send(())
            syncDuckAISurfaceWithSettings()
            duckAISurface?.refreshRecents()
        } else {
            fireSearchSuggestionsDisplayPixels()
        }
    }

    /// Fires the local-suggestion display pixels over the results shown this session. The `setActive`
    /// guard dedups the repeated dismiss calls, so a normal editing session fires these once.
    private func fireSearchSuggestionsDisplayPixels() {
        autocompletePixels.fireDisplayPixels(for: searchLoader?.result.all ?? [])
    }

    /// Re-checks the Chat Suggestions gate on every focus: this VC is built once per browser session
    /// (`viewWillAppear` only fires once), so without this, toggling the setting wouldn't take effect
    /// until the app restarts.
    private func syncDuckAISurfaceWithSettings() {
        guard shouldAttachDuckAISurface else {
            detachDuckAISurfaceFromSingleHost()
            return
        }
        // Rebuild a stale surface so each sub-source's gate re-evaluates and content from a
        // now-disabled sub-source is cleared; otherwise attach on first focus.
        if let duckAISurface, !duckAISurface.reflectsCurrentSettings {
            rebuildDuckAISuggestionsCoordinator()
        } else {
            attachDuckAISurfaceIfNeeded()
        }
    }

    /// The surface hosts both Duck.ai sub-sources (chat recents + URL/search hits), so it attaches
    /// when *either* toggle is on; each sub-source then gates itself independently.
    private var shouldAttachDuckAISurface: Bool {
        featureFlagger.isFeatureOn(.aiChatSuggestions)
            && (aiChatSettings.isChatSuggestionsEnabled || appSettings.autocomplete)
    }

    /// The host's current content state, so the dismiss path can pick the right NTP handoff.
    var isShowingLogoContent: Bool { unifiedSuggestionsHost?.isShowingLogo ?? false }
    var isShowingFavoritesContent: Bool { unifiedSuggestionsHost?.isShowingFavorites ?? false }

    /// Fades the focused content (logo / suggestion list) out as the UTI collapses, so the NTP
    /// content takes over cleanly.
    func beginDismissFade() {
        unifiedSuggestionsHost?.beginDismissFade()
    }

    /// Logo→logo collapse: morph the focused logo to the Dax mark and keep it visible, so it hands
    /// off to the (identical) NTP logo without crossfading two different logos. Sped up to finish
    /// within the bar's `collapseDuration`.
    func morphLogoHomeForDismiss(matching collapseDuration: TimeInterval) {
        unifiedSuggestionsHost?.morphLogoHomeForDismiss(matching: collapseDuration)
    }

    func refreshVisibleContentIfNeeded() {
        guard isContentActive else { return }
        guard needsVisibleRefresh else { return }

        refreshVisibleContent()
    }

    private var sessionOpenedAfterIdle: Bool {
        suggestionTrayDependencies?.tabsModelProvider().currentTab?.openedAfterIdle ?? false
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        escapeHatchModel = model
        applyEscapeHatchPlacement()
        updateSingleHostTopOffset()
        if isContentActive {
            applyRequestedContentInset()
        }
    }

    enum EscapeHatchPlacement: Equatable {
        /// Does not display the Escape Hatch.
        case none
        /// Embeds the Escape Hatch in the current scrollable content.
        case embedded

        static func resolve(hasEscapeHatch: Bool,
                            isFireTab: Bool,
                            isTyping: Bool) -> EscapeHatchPlacement {
            guard hasEscapeHatch, !isFireTab, !isTyping else {
                return .none
            }
            return .embedded
        }
    }

    private var escapeHatchPlacement: EscapeHatchPlacement {
        EscapeHatchPlacement.resolve(
            hasEscapeHatch: escapeHatchModel != nil,
            isFireTab: switchBarHandler.isFireTab,
            isTyping: UnifiedSuggestionsInputsMerger.isTyping(text: switchBarHandler.currentText,
                                                               hasUserInteractedWithText: switchBarHandler.hasUserInteractedWithText))
    }

    private var embeddedEscapeHatchModel: EscapeHatchModel? {
        escapeHatchPlacement == .embedded ? escapeHatchModel : nil
    }

    private func applyEscapeHatchPlacement() {
        unifiedSuggestionsHost?.setEscapeHatch(embeddedEscapeHatchModel, openedAfterIdle: sessionOpenedAfterIdle)
    }

    /// Keeps the List viewport full-height while resting content starts below the UTI.
    private func applyHostContentInsets() {
        unifiedSuggestionsHost?.setContentInsets(UIEdgeInsets(top: isUsingTopBarPosition ? requestedContentInset.top : 0,
                                                              left: 0,
                                                              bottom: requestedContentInset.bottom,
                                                              right: 0))
        let logoChromeInset = requestedContentInset.top
            + (isUsingTopBarPosition && embeddedEscapeHatchModel == nil ? Metrics.topBarContentClearance : 0)
        unifiedSuggestionsHost?.setLogoChromeInsetTop(logoChromeInset)
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
            // Orientation changes the bar position, hatch suppression, host offset and bottom inset,
            // but only a bar push or mode toggle re-runs the pipeline. Re-apply it for the new orientation.
            if self.isContentActive {
                self.applyRequestedContentInset()
            }
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
        unifiedSuggestionsHost?.setLandscape(isHorizontallyCompactLayoutEnabled)

        let horizontalMargin: CGFloat = isHorizontallyCompactLayoutEnabled ? Metrics.horizontalMarginForCompactLayout : 0
        self.contentContainerViewLeadingConstraint?.constant = horizontalMargin
        self.contentContainerViewTrailingConstraint?.constant = -horizontalMargin
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        self.refreshSyncPromoIfActive()
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
        let topAnchor: NSLayoutYAxisAnchor = isFloatingUIEnabled
            ? view.topAnchor
            : view.safeAreaLayoutGuide.topAnchor

        contentContainerViewLeadingConstraint = contentContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        contentContainerViewLeadingConstraint?.isActive = true
        contentContainerViewTrailingConstraint = contentContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        contentContainerViewTrailingConstraint?.isActive = true
        contentContainerView.topAnchor.constraint(equalTo: topAnchor).isActive = true

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
        Logger.unifiedInputState.debug("[UTITransition] source=swipe current=\(String(describing: self.switchBarHandler.currentToggleState), privacy: .public) target=\(String(describing: targetMode), privacy: .public) insetTop=\(self.requestedContentInset.top, privacy: .public) insetBottom=\(self.requestedContentInset.bottom, privacy: .public)")
        delegate?.unifiedInputEditingStateDidChangeMode(targetMode)
    }

    /// Suppresses the content mode-switch swipe (e.g. while the toggle pill is being dragged).
    var isSwipeEnabled: Bool {
        get { modeSwitchSwipeController.isEnabled }
        set { modeSwitchSwipeController.isEnabled = newValue }
    }

    private func installComponents() {
        installUnifiedSuggestionsHost()
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
            // Empty when "Search Suggestions" is off, else `effectiveTopHits` falls back to a phrase row.
            query: { [weak self] in self?.appSettings.autocomplete == true ? (self?.switchBarHandler.currentText ?? "") : "" },
            showAskAIChat: aiChatSettings.isAIChatEnabled
        )

        let hasFavorites: () -> Bool = {
            !dependencies.favoritesViewModel.favorites.isEmpty
        }
        let hasMessages: () -> Bool = {
            !dependencies.newTabPageDependencies.homePageMessagesConfiguration.homeMessages.isEmpty
        }

        var searchStateChanged = dependencies.favoritesViewModel.localUpdates
            .merge(with: dependencies.favoritesViewModel.externalUpdates)
            // Favorites changes fire on the Core Data context queue; marshal here so the merged
            // inputs (and the view model's `@Published content` mutation) stay on main.
            .receive(on: DispatchQueue.main)
            // The activation trigger is already on main (fired from `setActive`) — kept after the hop
            // so the re-resolve it drives stays synchronous, landing before the host becomes visible.
            .merge(with: activationResolveTrigger)
            .eraseToAnyPublisher()
        let homePageMessagesConfiguration = dependencies.newTabPageDependencies.homePageMessagesConfiguration
        if homePageMessagesConfiguration.mode == .coordinated {
            searchStateChanged = searchStateChanged
                .merge(with: homePageMessagesConfiguration.contentDidChangePublisher)
                .eraseToAnyPublisher()
        }
        let inputsPublisher = makeMergedInputsPublisher(hasFavorites: hasFavorites,
                                                        hasMessages: hasMessages,
                                                        searchStateChanged: searchStateChanged)

        let ntpDependencies = dependencies.newTabPageDependencies
        let favoritesViewModel = FavoritesViewModel(
            isFocussedState: true,
            favoriteDataSource: FavoritesListInteractingAdapter(favoritesListInteracting: ntpDependencies.favoritesModel,
                                                                appSettings: ntpDependencies.appSettings),
            faviconLoader: ntpDependencies.faviconLoader,
            faviconsCache: ntpDependencies.faviconsCache)
        favoritesViewModel.onFavoriteURLSelected = { [weak self] favorite in
            guard let self else { return }
            if let favoriteURL = favorite.url,
               let url = URL(string: favoriteURL),
               ntpDependencies.internalUserCommands.handle(url: url) {
                return
            }
            self.delegate?.unifiedInputEditingStateDidSelectFavorite(favorite)
        }
        favoritesViewModel.onFavoriteEdit = { [weak self] favorite in
            self?.delegate?.unifiedInputEditingStateDidEditFavorite(favorite)
        }

        let messagesModel = NewTabPageMessagesModel(
            homePageMessagesConfiguration: ntpDependencies.homePageMessagesConfiguration,
            subscriptionDataReporter: ntpDependencies.subscriptionDataReporting,
            messageActionHandler: ntpDependencies.remoteMessagingActionHandler,
            imageLoader: ntpDependencies.remoteMessagingImageLoader,
            pixelReporter: ntpDependencies.remoteMessagingPixelReporter,
            isOpenedAfterIdle: { [weak self] in self?.sessionOpenedAfterIdle ?? false })
        messagesModel.load()

        let config = UnifiedSuggestionsHostConfig(
            source: source,
            inputsPublisher: inputsPublisher,
            isAddressBarAtBottom: !isUsingTopBarPosition,
            favoritesViewModel: favoritesViewModel,
            messagesModel: messagesModel,
            onSelectRow: { [weak self] id in
                guard let self, let suggestion = source.suggestion(forRowID: id) else { return }
                self.fireSearchSuggestionClickPixel(for: suggestion)
                self.delegate?.unifiedInputEditingStateDidSelectSuggestion(suggestion)
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
            }
        )

        let host = UnifiedSuggestionsHost(config: config)
        host.onContentChanged = { [weak self] in
            guard let self, isContentActive else { return }
            applyRequestedContentInset()
        }

        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(containerView)
        // Floating UI's content container starts at the screen edge, so compose its system safe area
        // with the UTI-height offset. The standard layout already starts at the safe-area edge.
        let topAnchor = isFloatingUIEnabled
            ? contentContainerView.safeAreaLayoutGuide.topAnchor
            : contentContainerView.topAnchor
        let topConstraint = containerView.topAnchor.constraint(equalTo: topAnchor)
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
            .map { [weak self] _, text in self?.appSettings.autocomplete == true ? text : "" }
            .removeDuplicates()
            .eraseToAnyPublisher()

        host.start(in: containerView,
                   logoContainerView: contentContainerView,
                   parentViewController: self,
                   textPublisher: searchTextPublisher)
        unifiedSuggestionsHost = host
        host.setIsFireTab(switchBarHandler.isFireTab)
        host.setLandscape(isLandscapeOrientation)
        updateSingleHostTopOffset()
        applyEscapeHatchPlacement()
    }

    /// Keep the viewport fixed; the host's safe-area inset moves resting content with the input.
    private func updateSingleHostTopOffset() {
        unifiedSuggestionsTopConstraint?.constant = topBarContentGap
    }

    /// Duck.ai's no-hatch list keeps main's 4pt clearance. Search content owns its NTP-aligned spacing.
    private var topBarContentGap: CGFloat {
        isUsingTopBarPosition && switchBarHandler.currentToggleState == .aiChat && embeddedEscapeHatchModel == nil
            ? Metrics.topBarContentClearance
            : 0
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
              shouldAttachDuckAISurface,
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

    private func rebuildDuckAISuggestionsCoordinator() {
        guard duckAISurface != nil else { return }
        detachDuckAISurfaceFromSingleHost()
        attachDuckAISurfaceIfNeeded()
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
                self.refreshVisibleContent()
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
        guard let configuration = suggestionTrayDependencies?.newTabPageDependencies.homePageMessagesConfiguration,
              configuration.mode == .legacy else { return }

        notificationCancellable = NotificationCenter.default.publisher(for: RemoteMessagingStore.Notifications.remoteMessagesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshVisibleContent()
            }
    }

    private func markNeedsVisibleRefresh() {
        needsVisibleRefresh = true
    }

    // MARK: - Action Handlers

    @objc private func handleSwipeDown() {
        onSwipeDownRequested?()
    }

    func setContentInset(top: CGFloat, bottom: CGFloat) {
        guard requestedContentInset.top != top || requestedContentInset.bottom != bottom else { return }
        let hostTop = topBarContentGap
        Logger.unifiedInputState.debug("[UTITransition] contentInset mode=\(String(describing: self.switchBarHandler.currentToggleState), privacy: .public) oldTop=\(self.requestedContentInset.top, privacy: .public) oldBottom=\(self.requestedContentInset.bottom, privacy: .public) newTop=\(top, privacy: .public) newBottom=\(bottom, privacy: .public) hostTop=\(hostTop, privacy: .public) active=\(self.isContentActive, privacy: .public)")
        requestedContentInset = (top, bottom)
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        applyRequestedContentInset()
    }

    private func applyRequestedContentInset() {
        // The host frame stays fixed while safe-area insets move resting content with the UTI.
        updateSingleHostTopOffset()

        applyHostContentInsets()
        contentContainerView.layoutIfNeeded()
    }

    /// Refreshes the Duck.ai sync promo after a content/visibility change.
    private func refreshSyncPromoIfActive() {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        updateSyncPromo()
    }

    /// Shows the Duck.ai sync-promo card above recent chats in their scrollable list. Gated by the
    /// sync-promo manager + recents count.
    private func updateSyncPromo(for mode: TextEntryMode? = nil) {
        guard let promoViewModel = aiChatSyncPromoViewModel else { return }

        let isTyping = UnifiedSuggestionsInputsMerger.isTyping(text: switchBarHandler.currentText,
                                                              hasUserInteractedWithText: switchBarHandler.hasUserInteractedWithText)
        let shouldShow = (mode ?? switchBarHandler.currentToggleState) == .aiChat
            && !switchBarHandler.isFireTab
            && (duckAISurface?.isAttached ?? false)
            && promoViewModel.shouldShowPromo(isQueryActive: isTyping, chatCount: duckAISurface?.recentsCount ?? 0)

        unifiedSuggestionsHost?.setSyncPromo(shouldShow ? syncPromoView : nil)
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

    private enum Metrics {
        static let horizontalMarginForCompactLayout: CGFloat = 108
        static let backgroundColor = UIColor(designSystemColor: .panel)
        static let topBarContentClearance: CGFloat = 4
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
                self.refreshVisibleContent()
            }
            .store(in: &cancellables)
    }

    private func refreshVisibleContent() {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }

        needsVisibleRefresh = false

        applyEscapeHatchPlacement()
        refreshSyncPromoIfActive()
        updateSingleHostTopOffset()
        applyRequestedContentInset()
        view.layoutIfNeeded()
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
        refreshSyncPromoIfActive()
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
        delegate?.unifiedInputEditingStateDidRequestSyncSetup()
    }

    /// Fires the click pixel for a tapped Search-surface suggestion. `.askAIChat` gets its own daily
    /// pixel (needs feature-discovery params), so it's fired here after the standard mapping.
    private func fireSearchSuggestionClickPixel(for suggestion: Suggestion) {
        autocompletePixels.fireClickPixel(for: suggestion)
        guard case .askAIChat = suggestion else { return }
        autocompletePixels.fireAskAIChatClickPixel(
            isExperimentalExperience: aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
            additionalParameters: featureDiscovery.addToParams([:], forFeature: .aiChat))
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
