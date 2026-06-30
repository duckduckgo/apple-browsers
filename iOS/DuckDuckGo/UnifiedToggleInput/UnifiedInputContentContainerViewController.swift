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
    /// Built once and rebound into the pinned chrome by `updatePinnedChrome`; its show/hide rides
    /// `isSyncPromoCardVisible`, so there's no need to reconstruct it each time.
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
    /// The non-typing chrome (escape hatch + Duck.ai sync-promo) is pinned to the bar (not rendered
    /// inside the SwiftUI host) so it rides the bar's animation in the same layout pass — constant gap,
    /// no cross-framework sync. Its measured height is reserved in the content inset.
    private var chromeHostingController: UIHostingController<FocusedChromeView>?
    private var chromeTopConstraint: NSLayoutConstraint?
    private var chromeHeightConstraint: NSLayoutConstraint?
    /// Async-measured chrome height — used only for the variable-height sync-promo case (Duck.ai).
    private var chromeMeasuredHeight: CGFloat = 0
    private var isSyncPromoCardVisible = false

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
        rebuildDuckAISuggestionsCoordinator()
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
            unifiedSuggestionsHost?.setIsFireTab(switchBarHandler.isFireTab)
            unifiedSuggestionsHost?.setLandscape(isLandscapeOrientation)
            unifiedSuggestionsHost?.prepareForActivation()
            // Re-resolve now (synchronously, before the host is shown) so the prior session's stale
            // content isn't flashed. Runs after `prepareForActivation` clears the dismiss freeze.
            activationResolveTrigger.send(())
            duckAISurface?.refreshRecents()
        }
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

        refreshVisibleContent(animateContentUpdates: false)
    }

    private var sessionOpenedAfterIdle: Bool {
        suggestionTrayDependencies?.tabsModelProvider().currentTab?.openedAfterIdle ?? false
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        let hatchPresenceChanged = (escapeHatchModel != nil) != (model != nil)
        escapeHatchModel = model
        unifiedSuggestionsHost?.updateOpenedAfterIdle(sessionOpenedAfterIdle)
        // The chrome (hatch + sync-promo) is pinned to the bar (see below), not rendered in the host.
        updatePinnedChrome()
        updateSingleHostTopOffset()
        // The sync-promo sits below the hatch, so its layout changes when the hatch is added/removed.
        if hatchPresenceChanged {
            refreshSyncPromoIfActive()
        }
        if isContentActive {
            applyRequestedContentInset()
        }
    }

    /// Creates / updates / removes the bar-pinned chrome hosting controller and rebinds its content
    /// (hatch + sync-promo) to the current state.
    private func updatePinnedChrome() {
        let hatchModel = shouldShowPinnedHatch ? escapeHatchModel : nil
        let promo: AnyView? = isSyncPromoCardVisible ? syncPromoView : nil
        guard hatchModel != nil || promo != nil || chromeHostingController != nil else { return }

        let rootView = FocusedChromeView(
            hatchModel: hatchModel,
            syncPromo: promo,
            topInset: chromeTopInsetForPosition,
            onHeightChange: { [weak self] height in
                guard let self, self.chromeMeasuredHeight != height else { return }
                self.chromeMeasuredHeight = height
                // Only the sync-promo case relies on the measured height; the hatch-only case uses a
                // synchronous known height (so favorites slide without a late jump).
                guard self.isSyncPromoCardVisible else { return }
                self.chromeHeightConstraint?.constant = self.currentChromeReservedHeight
                self.applyHostContentInsets()
            })

        if let hostingController = chromeHostingController {
            hostingController.rootView = rootView
        } else {
            installPinnedChrome(rootView: rootView)
        }
    }

    private func installPinnedChrome(rootView: FocusedChromeView) {
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hostingController)
        contentContainerView.addSubview(hostingController.view)
        let top = hostingController.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor, constant: pinnedChromeTopConstant)
        chromeTopConstraint = top
        let height = hostingController.view.heightAnchor.constraint(equalToConstant: currentChromeReservedHeight)
        chromeHeightConstraint = height
        NSLayoutConstraint.activate([
            top,
            height,
            hostingController.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)
        contentContainerView.bringSubviewToFront(hostingController.view)
        chromeHostingController = hostingController
    }

    private var chromeTopInsetForPosition: CGFloat {
        isUsingTopBarPosition ? Metrics.hatchTopInsetTopBar : Metrics.hatchTopInsetBottomBar
    }

    /// Pins the chrome at the bar's edge. `requestedContentInset.top` is the bar height on a top bar
    /// (so the chrome tracks it) and 0 on a bottom bar (chrome sits at the content top).
    private var pinnedChromeTopConstant: CGFloat {
        topBarContentGap + requestedContentInset.top
    }

    /// The hatch shows in the non-typing empty/branding states — using the same not-typing rule as the
    /// resolver so it never diverges from the host's content (e.g. a pre-filled, unedited URL).
    private var shouldShowPinnedHatch: Bool {
        escapeHatchModel != nil
            && !switchBarHandler.isFireTab
            && !UnifiedSuggestionsInputsMerger.isTyping(text: switchBarHandler.currentText,
                                                        hasUserInteractedWithText: switchBarHandler.hasUserInteractedWithText)
    }

    /// Height to reserve below the bar for the pinned chrome. The hatch is a fixed height (reserved
    /// synchronously so favorites slide without a late jump); the variable sync-promo uses the
    /// async-measured height (Duck.ai only, where favorites never show).
    private var currentChromeReservedHeight: CGFloat {
        if isSyncPromoCardVisible {
            return chromeMeasuredHeight
        } else if shouldShowPinnedHatch {
            return chromeTopInsetForPosition + TabSwitcherPill.compactSize + FocusedChromeView.Metrics.bottomInset
        } else {
            return 0
        }
    }

    /// Sets the host's content inset so the list/favorites start below the bar + pinned chrome.
    private func applyHostContentInsets() {
        unifiedSuggestionsHost?.setContentInsets(UIEdgeInsets(top: requestedContentInset.top + currentChromeReservedHeight,
                                                              left: 0,
                                                              bottom: requestedContentInset.bottom,
                                                              right: 0))
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
            // Orientation changes the bar position, hatch suppression and chrome insets, but only a
            // bar push or mode toggle re-runs the inset pipeline — so rotation left the host's
            // safe-area insets stale. Re-apply it here for the new orientation.
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
            // The activation trigger is already on main (fired from `setActive`) — kept after the hop
            // so the re-resolve it drives stays synchronous, landing before the host becomes visible.
            .merge(with: activationResolveTrigger)
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
        host.setIsFireTab(switchBarHandler.isFireTab)
        host.setLandscape(isLandscapeOrientation)
        updateSingleHostTopOffset()
        unifiedSuggestionsHost = host
        updatePinnedChrome()
    }

    /// Single-host path: the suggestions container aligns with the new-tab page (the favorites
    /// surface IS the NTP, and the hatch lines up with the NTP hatch), so it rides the requested
    /// inset directly. The constant animates natively, so the hatch glides with the input.
    private func updateSingleHostTopOffset() {
        // EXPERIMENT (uti-host-stable-frame): the host FRAME stays fixed; the bar-height top inset is
        // applied as the host's safe-area top inset instead (see `applyRequestedContentInset`). This
        // keeps the frame from moving when the bar height changes on a Search↔Duck.ai toggle.
        unifiedSuggestionsTopConstraint?.constant = topBarContentGap
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
            openedAfterIdle: sessionOpenedAfterIdle,
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
        // The escape hatch and the empty-state logo are UTI chrome (bar-pinned hatch + the host's
        // `FocusedDaxLogoView`), not the NTP's — leave the NTP's own hatch unset so we never get two.
        controller.setLogoHidden(true)
        return controller
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
        // The host frame stays fixed (uti-host-stable-frame); the bar-height offset rides the host's
        // safe-area inset (top for a top bar, bottom for a bottom bar) so the scroll view animates it
        // in lockstep with the bar.
        updateSingleHostTopOffset()

        // Pinned chrome: track the bar (the constant updates inside the bar's animation here, so it
        // glides in the same pass), rebind its content for the current state, and reserve its measured
        // height in the content inset so the list/favorites start below it.
        chromeTopConstraint?.constant = pinnedChromeTopConstant
        updatePinnedChrome()
        chromeHeightConstraint?.constant = currentChromeReservedHeight
        applyHostContentInsets()
        contentContainerView.layoutIfNeeded()
    }

    /// Refreshes derived bar chrome (the Duck.ai sync-promo) after a content/visibility change. The
    /// focused empty state itself now renders in the SwiftUI host, so there's no logo to update here.
    private func refreshSyncPromoIfActive() {
        guard isContentActive else {
            markNeedsVisibleRefresh()
            return
        }
        updateSyncPromo()
    }

    /// Shows the Duck.ai sync-promo card below the escape hatch in the not-typing state, mirroring
    /// the legacy Duck.ai suggestions header. Gated by the sync-promo manager + recents count.
    private func updateSyncPromo() {
        guard let promoViewModel = aiChatSyncPromoViewModel else { return }

        let isTyping = UnifiedSuggestionsInputsMerger.isTyping(text: switchBarHandler.currentText,
                                                              hasUserInteractedWithText: switchBarHandler.hasUserInteractedWithText)
        let shouldShow = switchBarHandler.currentToggleState == .aiChat
            && !switchBarHandler.isFireTab
            && (duckAISurface?.isAttached ?? false)
            && promoViewModel.shouldShowPromo(isQueryActive: isTyping, chatCount: duckAISurface?.recentsCount ?? 0)

        // The sync-promo rides the bar-pinned chrome (not the host), so toggling its visibility just
        // rebinds the chrome; the content inset follows from the chrome's reported height.
        let wasVisible = isSyncPromoCardVisible
        isSyncPromoCardVisible = shouldShow
        updatePinnedChrome()
        // On hide, the reserved height was the promo's async-measured one and `onHeightChange` is gated
        // to the visible case — so re-apply the now-synchronous reserved height (hatch or 0) here, or
        // the content (recents) stays pushed down where the promo was.
        if wasVisible && !shouldShow {
            chromeHeightConstraint?.constant = currentChromeReservedHeight
            applyHostContentInsets()
            contentContainerView.layoutIfNeeded()
        }
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
        /// Brings the card's 8pt bottom margin up to the design's 12pt UTI bottom margin on the top bar
        /// (content then adds its own 6pt top → 18pt UTI→content, per Figma).
        static let topBarContentClearance: CGFloat = 4
        /// Gap between the bar's edge and the pinned chrome (Figma). The chrome owns its other metrics.
        static let hatchTopInsetTopBar: CGFloat = 6
        /// Bottom bar: the focused content top coincides with the NTP content top, so this must equal the
        /// NTP's `contentTopInset` (`NewTabPageLayoutConfiguration.unifiedToggleInput.contentTopInsetOverride`)
        /// for the focused and NTP hatches to land on the same line. Keep the two in sync.
        static let hatchTopInsetBottomBar: CGFloat = 10
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
            self.refreshSyncPromoIfActive()
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
