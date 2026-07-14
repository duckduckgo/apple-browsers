//
//  SuggestionTrayViewController.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Combine
import Core
import Bookmarks
import Suggestions
import Persistence
import History
import BrowserServicesKit
import PrivacyConfig
import UIComponents
import RemoteMessaging
import AIChat
import Subscription
import Onboarding

/// Which suggestions surface the iPad popover currently shows.
enum PopoverSuggestionsMode {
    case search
    case duckAI
}

/// Routes iPad Duck.ai row interactions (resolved by the tray) to the owner for navigation.
@MainActor
protocol SuggestionTrayDuckAINavigationDelegate: AnyObject {
    func suggestionTrayDidSelectDuckAI(_ selection: DuckAISuggestionsSelection)
    /// A Duck.ai URL suggestion's history was deleted; the owner refreshes the search surface too.
    func suggestionTrayDidDeleteDuckAIURLSuggestion()
    /// Present the recent-chat delete confirmation, anchored to `sourceRect` (the 🔥 button's
    /// global frame) for the iPad popover.
    func suggestionTrayRequestsDuckAIChatDeletionConfirmation(for chat: AIChatSuggestion,
                                                              sourceRect: CGRect,
                                                              onConfirm: @escaping () -> Void,
                                                              onCancel: @escaping () -> Void)
}

class SuggestionTrayViewController: UIViewController {

    weak var backgroundView: CompositeShadowView!
    weak var containerView: UIView!
    var variableWidthConstraint: NSLayoutConstraint!
    var fullWidthConstraint: NSLayoutConstraint!
    var topConstraint: NSLayoutConstraint!
    var variableHeightConstraint: NSLayoutConstraint!
    var fullHeightSafeAreaConstraint: NSLayoutConstraint!
    var fullHeightConstraint: NSLayoutConstraint!
    var fullHeightSafeAreaInequalityConstraint: NSLayoutConstraint!


    weak var autocompleteDelegate: AutocompleteViewControllerDelegate?
    weak var newTabPageControllerDelegate: NewTabPageControllerDelegate?

    var dismissHandler: (() -> Void)?

    var isShowingAutocompleteSuggestions: Bool {
        autocompleteController != nil || popoverSearchController != nil
    }

    var isShowingFavorites: Bool {
        newTabPage != nil
    }

    var isShowing: Bool {
        isShowingAutocompleteSuggestions || isShowingFavorites
    }

    /// Called when URL-only fallback visibility changes, so the host can update Dax visibility.
    var onURLFallbackVisibilityChanged: (() -> Void)?

    /// Fires as the iPad Duck.ai list gains/loses rows, so the owner can show/hide the popover
    /// reactively (the list's content loads asynchronously after the query is set).
    var onPopoverDuckAIContentChanged: ((_ hasContent: Bool) -> Void)?

    var suggestionFilter: AutocompleteSuggestionFilter = .all {
        didSet { autocompleteController?.suggestionFilter = suggestionFilter }
    }
    var additionalTopInset: CGFloat = 0 {
        didSet {
            applyTopConstraintForLayoutMode()
        }
    }

    /// Updates the top inset, optionally gliding the popover to its new position in lock-step with the
    /// iPad omnibar's expand/collapse (`DefaultOmniBarView` uses 0.25s `.curveEaseInOut`).
    func setAdditionalTopInset(_ inset: CGFloat, animated: Bool) {
        guard animated, additionalTopInset != inset else {
            additionalTopInset = inset
            return
        }
        additionalTopInset = inset
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.view.layoutIfNeeded()
        }
    }

    private var autocompleteController: AutocompleteViewController?
    /// iPad renders the shared SwiftUI suggestions surface in the popover instead of
    /// `AutocompleteViewController`; its source is retained here for row-tap resolution.
    private var popoverSearchController: PopoverSuggestionsController?
    private var popoverSearchSource: SearchSuggestionsSource?
    /// iPad Duck.ai surface hosted in the same popover; source provided by the owner.
    weak var duckAINavigationDelegate: SuggestionTrayDuckAINavigationDelegate?
    private var popoverDuckAIController: PopoverSuggestionsController?
    private var popoverDuckAISource: DuckAISuggestionsSource?
    private var popoverDuckAIQuery = ""
    private(set) var popoverMode: PopoverSuggestionsMode = .search
    /// Last content height reported per mode, so toggling modes re-applies the right popover height.
    private var popoverContentHeights: [PopoverSuggestionsMode: CGFloat] = [:]
    private var newTabPage: NewTabPageViewController?
    private var willRemoveAutocomplete = false

    /// Allows to defer autocomplete presentation to avoid short UI glitch (blink) when presenting
    /// autocomplete suggestions when unifiedToggleInput flag is on.
    var deferAutocompleteReveal = false
    private var pendingDeferredAutocompleteReveal = false
    private var pendingEscapeHatchModel: EscapeHatchModel?
    private var pendingSuggestionsSectionTitle: String?
    private var pendingFavoritesSectionTitle: String?
    private let bookmarksDatabase: CoreDataDatabase
    private let favoritesModel: FavoritesListInteracting
    private let historyManager: HistoryManaging
    private let tabsModelProvider: () -> TabsModelManaging
    private let featureFlagger: FeatureFlagger
    private let appSettings: AppSettings
    private let aiChatSettings: AIChatSettingsProvider
    private let featureDiscovery: FeatureDiscovery
    private let hideBorder: Bool

    var coversFullScreen: Bool = false

    /// Horizontal inset applied to the autocomplete content only. Favorites and the shared container stay
    /// full width, so switching between favorites and autocomplete doesn't resize/recenter the container
    /// (which would visibly shift the still-mounted favorites view before autocomplete reveals).
    var autocompleteHorizontalInset: CGFloat = 0

    var selectedSuggestion: Suggestion? {
        if let id = popoverSearchController?.selectedRowID {
            return popoverSearchSource?.suggestion(forRowID: id)
        }
        return autocompleteController?.selectedSuggestion
    }


    enum SuggestionType: Equatable {

        case autocomplete(query: String)
        /// iPad Duck.ai mode: the shared SwiftUI list (recents + URL hits + Search row) in the popover.
        case duckAISuggestions(query: String)
        case favorites

        func hideOmnibarSeparator() -> Bool {
            switch self {
            case .autocomplete, .duckAISuggestions: return true
            case .favorites: return false
            }
        }

        static func == (lhs: SuggestionTrayViewController.SuggestionType, rhs: SuggestionTrayViewController.SuggestionType) -> Bool {
            switch (lhs, rhs) {
            case let (.autocomplete(queryLHS), .autocomplete(queryRHS)):
                return queryLHS == queryRHS
            case let (.duckAISuggestions(queryLHS), .duckAISuggestions(queryRHS)):
                return queryLHS == queryRHS
            case (.favorites, .favorites):
                return true
            default:
                return false
            }
        }
    }

    let newTabPageDependencies: NewTabPageDependencies

    struct NewTabPageDependencies {
        let favoritesModel: FavoritesListInteracting
        let homePageMessagesConfiguration: HomePageMessagesConfiguration
        let subscriptionDataReporting: SubscriptionDataReporting?
        let newTabDialogFactory: NewTabDaxDialogsProvider
        let newTabDaxDialogManager: DaxDialogsManaging
        let onboardingFlowProvider: OnboardingFlowProviding
        let faviconLoader: FavoritesFaviconLoading
        let faviconsCache: FavoritesFaviconCaching
        let remoteMessagingActionHandler: RemoteMessagingActionHandling
        let remoteMessagingImageLoader: RemoteMessagingImageLoading
        let remoteMessagingPixelReporter: RemoteMessagingPixelReporting?
        let appSettings: AppSettings
        let subscriptionManager: any SubscriptionManager
        let internalUserCommands: URLBasedDebugCommands
    }

    let productSurfaceTelemetry: ProductSurfaceTelemetry

    required init(
                   favoritesViewModel: FavoritesListInteracting,
                   bookmarksDatabase: CoreDataDatabase,
                   historyManager: HistoryManaging,
                   tabsModelProvider: @escaping () -> TabsModelManaging,
                   featureFlagger: FeatureFlagger,
                   appSettings: AppSettings,
                   aiChatSettings: AIChatSettingsProvider,
                   featureDiscovery: FeatureDiscovery,
                   newTabPageDependencies: NewTabPageDependencies,
                   productSurfaceTelemetry: ProductSurfaceTelemetry,
                   hideBorder: Bool) {
        self.favoritesModel = favoritesViewModel
        self.bookmarksDatabase = bookmarksDatabase
        self.historyManager = historyManager
        self.tabsModelProvider = tabsModelProvider
        self.featureFlagger = featureFlagger
        self.appSettings = appSettings
        self.aiChatSettings = aiChatSettings
        self.newTabPageDependencies = newTabPageDependencies
        self.featureDiscovery = featureDiscovery
        self.productSurfaceTelemetry = productSurfaceTelemetry
        self.hideBorder = hideBorder

       super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        backgroundView = install(CompositeShadowView())
        containerView = install(UIView())

        self.fullHeightSafeAreaConstraint = containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        self.fullHeightSafeAreaInequalityConstraint = containerView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor)
        self.fullHeightConstraint = containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        if isPad {
            self.variableHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: Constant.suggestionTrayInitialHeight)
        } else {
            self.variableHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: max(view.frame.height, view.frame.width))
        }

        self.variableHeightConstraint.priority = UILayoutPriority(999)

        self.variableWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: 100)
        self.variableWidthConstraint.priority = UILayoutPriority(999)

        self.fullWidthConstraint = containerView.widthAnchor.constraint(equalTo: view.widthAnchor)

        self.topConstraint = containerView.topAnchor.constraint(equalTo: view.topAnchor)

        // Full height constraints are activated later depending on how the suggestions are shown.
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: containerView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            self.variableWidthConstraint,
            self.variableHeightConstraint,
            self.topConstraint,
            self.fullWidthConstraint,
        ])

        installDismissHandler()
    }

    private func install<T: UIView>(_ view: T) -> T {
        view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(view)
        return view
    }

    @IBAction func onDismiss() {
        dismissHandler?()
    }
    
    override var canBecomeFirstResponder: Bool { return true }
    
    func canShow(for type: SuggestionType, animated: Bool = true) -> Bool {
        var canShow = false
        switch type {
        case .autocomplete(let query):
            canShow = canDisplayAutocompleteSuggestions(forQuery: query, animated: animated)
        case .duckAISuggestions:
            // Show whenever the Duck.ai list has rows (recents and/or URL hits); height is the proxy.
            canShow = (popoverContentHeights[.duckAI] ?? 0) > 0
        case .favorites:
            canShow = canDisplayFavorites || hasRemoteMessages || pendingEscapeHatchModel != nil
        }
        return canShow
    }

    func show(for type: SuggestionType, animated: Bool = true) {
        self.fullHeightSafeAreaConstraint.constant = appSettings.currentAddressBarPosition == .bottom ? 50 : 0

        switch type {
        case .autocomplete(let query):
            displayAutocompleteSuggestions(forQuery: query, animated: animated)
        case .duckAISuggestions:
            removeNewTabPage(animated: false)
            setPopoverMode(.duckAI)
        case .favorites:
            if isPad {
                removeAutocomplete(animated: animated)
                displayFavoritesIfNeeded(animated: animated)
            } else {
                willRemoveAutocomplete = true
                displayFavoritesIfNeeded(animated: animated) { [weak self] in
                    self?.removeAutocomplete(animated: animated)
                    self?.willRemoveAutocomplete = false
                }
            }
        }
    }
        
    var contentFrame: CGRect {
        return containerView.frame
    }

    func refreshSuggestionsIfNeeded() {
        autocompleteController?.refreshSuggestions()
    }

    func didHide(animated: Bool) {
        removeAutocomplete(animated: animated)
        removeNewTabPage(animated: animated)
        teardownPopoverDuckAIController()
    }
    
    @objc func keyboardMoveSelectionDown() {
        popoverSearchController?.keyboardMoveSelectionDown()
        autocompleteController?.keyboardMoveSelectionDown()
    }

    @objc func keyboardMoveSelectionUp() {
        popoverSearchController?.keyboardMoveSelectionUp()
        autocompleteController?.keyboardMoveSelectionUp()
    }

    // MARK: - Duck.ai keyboard navigation (iPad popover)

    var hasDuckAIHighlight: Bool { popoverDuckAIController?.selectedRowID != nil }

    func duckAIKeyboardMoveSelectionDown() { popoverDuckAIController?.keyboardMoveSelectionDown() }
    func duckAIKeyboardMoveSelectionUp() { popoverDuckAIController?.keyboardMoveSelectionUp() }
    func clearDuckAIKeyboardSelection() { popoverDuckAIController?.clearKeyboardSelection() }

    /// Clears any keyboard/pointer highlight on both surfaces — used when the popover is hidden so a
    /// stale selection can't survive a collapse (which would leave the arrow keys claimed).
    func clearKeyboardSelections() {
        popoverSearchController?.clearKeyboardSelection()
        popoverDuckAIController?.clearKeyboardSelection()
    }

    /// Commits the highlighted Duck.ai row (Enter); returns false when nothing is highlighted.
    func activateHighlightedDuckAISuggestion() -> Bool {
        guard let id = popoverDuckAIController?.selectedRowID else { return false }
        handlePopoverDuckAISelection(rowID: id)
        return true
    }

    func float(withWidth width: CGFloat) {
        let cornerRadius = Constant.popoverCornerRadius
        containerView.layer.cornerRadius = cornerRadius
        containerView.layer.masksToBounds = true

        backgroundView.layer.cornerRadius = cornerRadius
        backgroundView.backgroundColor = UIColor(designSystemColor: .background)
        backgroundView.clipsToBounds = false
        backgroundView.applyActiveShadow()

        let isFirstPresentation = fullHeightConstraint.isActive
        if isFirstPresentation {
            variableHeightConstraint.constant = Constant.suggestionTrayInitialHeight
        }

        variableWidthConstraint.constant = width
        fullWidthConstraint.isActive = false
        fullWidthConstraint.constant = 0
        fullHeightConstraint.isActive = false
        fullHeightSafeAreaConstraint.isActive = false
        fullHeightSafeAreaInequalityConstraint.isActive = true
        applyTopConstraintForLayoutMode()
    }

    func fill(bottomOffset: CGFloat = 0.0) {
        additionalSafeAreaInsets = .init(top: 0, left: 0, bottom: bottomOffset, right: 0)

        containerView.layer.shadowColor = UIColor.clear.cgColor
        containerView.layer.cornerRadius = 0

        containerView.subviews.first?.layer.masksToBounds = false
        containerView.subviews.first?.layer.cornerRadius = 0
        backgroundView.layer.masksToBounds = false
        backgroundView.layer.cornerRadius = 0
        backgroundView.backgroundColor = UIColor.clear

        fullWidthConstraint.isActive = true
        fullWidthConstraint.constant = 0
        fullHeightConstraint.isActive = coversFullScreen
        fullHeightSafeAreaConstraint.isActive = !coversFullScreen
        fullHeightSafeAreaInequalityConstraint.isActive = !coversFullScreen
        applyTopConstraintForLayoutMode()
    }
    
    private func installDismissHandler() {
        let backgroundTap = UITapGestureRecognizer(target: self, action: #selector(onDismiss))
        backgroundTap.cancelsTouchesInView = false
        
        let foregroundTap = UITapGestureRecognizer()
        foregroundTap.cancelsTouchesInView = false
        
        backgroundTap.require(toFail: foregroundTap)
        
        view.addGestureRecognizer(backgroundTap)
        containerView.addGestureRecognizer(foregroundTap)
    }
    
    private var canDisplayFavorites: Bool {
        favoritesModel.favorites.count > 0
    }

    var hasFavorites: Bool {
        canDisplayFavorites
    }

    var hasRemoteMessages: Bool {
        return !newTabPageDependencies.homePageMessagesConfiguration.homeMessages.isEmpty
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        pendingEscapeHatchModel = model
        newTabPage?.setEscapeHatch(model)
    }

    func setSuggestionsSectionTitle(_ title: String?) {
        pendingSuggestionsSectionTitle = title
        autocompleteController?.setSectionTitle(title)
    }

    func setFavoritesSectionTitle(_ title: String?) {
        pendingFavoritesSectionTitle = title
        newTabPage?.setSectionTitle(title)
    }

    private func displayFavoritesIfNeeded(animated: Bool, onInstall: @escaping () -> Void = {}) {
        if newTabPage == nil {
            installNewTabPage(animated: animated, onInstall: onInstall)
        } else {
            onInstall()
        }
    }

    private func installNewTabPage(animated: Bool, onInstall: @escaping () -> Void = {}) {
        let dependencies = newTabPageDependencies
        let controller = NewTabPageViewController(
            isFocussedState: true,
            dismissKeyboardOnScroll: aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
            tab: Tab(fireTab: tabsModelProvider().shouldCreateFireTabs),
            interactionModel: dependencies.favoritesModel,
            homePageMessagesConfiguration: dependencies.homePageMessagesConfiguration,
            subscriptionDataReporting: dependencies.subscriptionDataReporting,
            newTabDialogFactory: dependencies.newTabDialogFactory,
            daxDialogsManager: dependencies.newTabDaxDialogManager,
            onboardingFlowProvider: dependencies.onboardingFlowProvider,
            faviconLoader: dependencies.faviconLoader,
            remoteMessagingActionHandler: dependencies.remoteMessagingActionHandler,
            remoteMessagingImageLoader: dependencies.remoteMessagingImageLoader,
            remoteMessagingPixelReporter: dependencies.remoteMessagingPixelReporter,
            appSettings: dependencies.appSettings,
            faviconsCache: dependencies.faviconsCache,
            subscriptionManager: dependencies.subscriptionManager,
            internalUserCommands: dependencies.internalUserCommands
        )

        controller.delegate = newTabPageControllerDelegate
        if hideBorder {
            controller.hideBorderView()
        }
        controller.setEscapeHatch(pendingEscapeHatchModel)
        if let pendingFavoritesSectionTitle {
            controller.setSectionTitle(pendingFavoritesSectionTitle)
        }

        install(controller: controller,
                animated: animated,
                completion: onInstall)
        newTabPage = controller
    }
    
    private func canDisplayAutocompleteSuggestions(forQuery query: String, animated: Bool) -> Bool {
        let canDisplay = appSettings.autocomplete && !query.isEmpty
        if !canDisplay {
            removeAutocomplete(animated: animated)
        }
        return canDisplay
    }
    
    private func displayAutocompleteSuggestions(forQuery query: String, animated: Bool) {
        if isPad {
            removeNewTabPage(animated: false)
            preparePopoverSearchController()
            popoverSearchController?.updateQuery(query)
        } else {
            if autocompleteController == nil {
                installAutocompleteSuggestions(animated: animated)
            }
            autocompleteController?.updateQuery(query)
        }
    }

    /// Builds the iPad search surface once and keeps it for the whole focus session (so toggling
    /// search↔Duck.ai swaps visibility instead of tearing down + rebuilding, which flashed).
    func preparePopoverSearchController() {
        guard popoverSearchController == nil else { return }
        installPopoverSearchController()
    }

    var hasPopoverDuckAISource: Bool { popoverDuckAISource != nil }

    /// Builds the shared SwiftUI search surface (own request runner/loader, mirroring the UTI
    /// container) and embeds it in the popover. Row taps resolve through `popoverSearchSource`.
    private func installPopoverSearchController() {
        let requestRunner = AutocompleteRequestRunner()
        let dataSource = AutocompleteSuggestionsDataSource(
            historyManager: historyManager,
            bookmarksDatabase: bookmarksDatabase,
            featureFlagger: featureFlagger,
            tabsModel: tabsModelProvider()
        ) { request, completion in
            requestRunner.run(request, completion: completion)
        }
        let loader = SearchSuggestionsLoader(dataSource: dataSource,
                                             useUnifiedURLPrediction: featureFlagger.isFeatureOn(.unifiedURLPredictor))
        let querySubject = CurrentValueSubject<String, Never>("")
        let source = SearchSuggestionsSource(loader: loader,
                                             query: { querySubject.value },
                                             showAskAIChat: aiChatSettings.isAIChatEnabled)
        popoverSearchSource = source

        let controller = PopoverSuggestionsController(
            source: source,
            isAddressBarAtBottom: appSettings.currentAddressBarPosition == .bottom,
            querySubject: querySubject)
        controller.onContentHeightChange = { [weak self] height in
            self?.applyPopoverContentHeight(height, from: .search)
        }
        controller.onSelectRow = { [weak self] id in
            guard let suggestion = source.suggestion(forRowID: id) else { return }
            self?.autocompleteDelegate?.autocomplete(selectedSuggestion: suggestion)
        }
        controller.onTapAheadRow = { [weak self] id in
            guard let suggestion = source.suggestion(forRowID: id) else { return }
            self?.autocompleteDelegate?.autocomplete(pressedPlusButtonForSuggestion: suggestion)
        }
        controller.onHighlightRow = { [weak self] id in
            guard let suggestion = source.suggestion(forRowID: id) else { return }
            self?.autocompleteDelegate?.autocomplete(highlighted: suggestion, for: querySubject.value)
        }
        controller.onClearHighlight = { [weak self] in
            // Selection cleared → restore the user's typed query in place of the last previewed suggestion.
            let query = querySubject.value
            self?.autocompleteDelegate?.autocomplete(highlighted: .phrase(phrase: query), for: query)
        }
        controller.onDeleteRow = { [weak self, weak loader] id in
            guard let self,
                  let suggestion = source.suggestion(forRowID: id),
                  case .historyEntry(_, let url, _) = suggestion else { return }
            Task { @MainActor in
                await SuggestionHistoryDeletion.delete(url, using: self.historyManager)
                loader?.fetch(query: querySubject.value)
                self.autocompleteDelegate?.autocomplete(deletedSuggestion: suggestion)
            }
        }

        install(controller: controller,
                animated: false,
                additionalInsets: UIEdgeInsets(top: 0, left: autocompleteHorizontalInset, bottom: 0, right: autocompleteHorizontalInset))
        controller.view.isHidden = (popoverMode != .search)
        popoverSearchController = controller
    }

    // MARK: - iPad Duck.ai surface

    /// Hosts (or clears) the Duck.ai source in the popover. The tray builds a controller around it,
    /// resolves row taps via the source, and routes navigation to `duckAINavigationDelegate`.
    func setPopoverDuckAISource(_ source: DuckAISuggestionsSource?,
                                querySubject: CurrentValueSubject<String, Never>? = nil) {
        teardownPopoverDuckAIController()
        guard let source, let querySubject else { return }
        popoverDuckAISource = source

        let controller = PopoverSuggestionsController(
            source: source,
            isAddressBarAtBottom: appSettings.currentAddressBarPosition == .bottom,
            querySubject: querySubject)
        controller.onContentHeightChange = { [weak self] height in
            self?.applyPopoverContentHeight(height, from: .duckAI)
        }
        controller.onSelectRow = { [weak self] id in self?.handlePopoverDuckAISelection(rowID: id) }
        controller.onTapAheadRow = { [weak self] id in self?.handlePopoverDuckAISelection(rowID: id) }
        controller.onDeleteRow = { [weak self] id in self?.handlePopoverDuckAIURLDelete(rowID: id) }
        controller.onFireDeleteRow = { [weak self] id, sourceRect in self?.handlePopoverDuckAIChatDelete(rowID: id, sourceRect: sourceRect) }

        install(controller: controller, animated: false,
                additionalInsets: UIEdgeInsets(top: 0, left: autocompleteHorizontalInset, bottom: 0, right: autocompleteHorizontalInset))
        controller.view.isHidden = (popoverMode != .duckAI)
        popoverDuckAIController = controller
    }

    /// Whether the Duck.ai list currently has rows (its last reported content height is non-zero).
    var popoverDuckAIHasContent: Bool { (popoverContentHeights[.duckAI] ?? 0) > 0 }

    func updatePopoverDuckAIQuery(_ query: String) {
        popoverDuckAIQuery = query
        popoverDuckAIController?.updateQuery(query)
    }

    /// Toggles which embedded controller is visible and re-applies that mode's last popover height.
    func setPopoverMode(_ mode: PopoverSuggestionsMode) {
        popoverMode = mode
        popoverSearchController?.view.isHidden = (mode != .search)
        popoverDuckAIController?.view.isHidden = (mode != .duckAI)
        if let height = popoverContentHeights[mode] {
            autocompleteDidChangeContentHeight(height: height)
        }
    }

    private func applyPopoverContentHeight(_ height: CGFloat, from mode: PopoverSuggestionsMode) {
        popoverContentHeights[mode] = height
        if mode == .duckAI {
            onPopoverDuckAIContentChanged?(height > 0)
        }
        guard mode == popoverMode else { return }
        autocompleteDidChangeContentHeight(height: height)
    }

    /// Tears down both iPad suggestion surfaces (search + Duck.ai) without hiding the container —
    /// used on tab switch so the next focus session rebuilds fresh for the current tab.
    func teardownPopoverSuggestions() {
        removeAutocomplete(animated: false)
        teardownPopoverDuckAIController()
    }

    private func teardownPopoverDuckAIController() {
        guard let controller = popoverDuckAIController else { return }
        controller.tearDown()
        removeController(controller, animated: false)
        popoverDuckAIController = nil
        popoverDuckAISource = nil
        popoverContentHeights[.duckAI] = nil
    }

    private func handlePopoverDuckAISelection(rowID id: String) {
        guard let selection = popoverDuckAISource?.selection(forRowID: id) else { return }
        duckAINavigationDelegate?.suggestionTrayDidSelectDuckAI(selection)
    }

    private func handlePopoverDuckAIURLDelete(rowID id: String) {
        guard let source = popoverDuckAISource,
              case .url(let suggestion) = source.selection(forRowID: id),
              case .historyEntry(_, let url, _) = suggestion else { return }
        Task { @MainActor in
            await SuggestionHistoryDeletion.delete(url, using: self.historyManager)
            source.fetchURLSuggestions(query: self.popoverDuckAIQuery)
            self.duckAINavigationDelegate?.suggestionTrayDidDeleteDuckAIURLSuggestion()
        }
    }

    private func handlePopoverDuckAIChatDelete(rowID id: String, sourceRect: CGRect) {
        guard let source = popoverDuckAISource,
              case .chat(let chat) = source.selection(forRowID: id) else { return }
        DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteButtonTapped)
        duckAINavigationDelegate?.suggestionTrayRequestsDuckAIChatDeletionConfirmation(
            for: chat,
            sourceRect: sourceRect,
            onConfirm: { [weak source] in
                source?.deleteChat(chat)
                DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteConfirmed)
            },
            onCancel: {
                DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteCancelled)
            })
    }

    private func installAutocompleteSuggestions(animated: Bool) {
        let controller = AutocompleteViewController(historyManager: historyManager,
                                                    bookmarksDatabase: bookmarksDatabase,
                                                    appSettings: appSettings,
                                                    tabsModel: tabsModelProvider(),
                                                    featureFlagger: featureFlagger,
                                                    aiChatSettings: aiChatSettings,
                                                    featureDiscovery: featureDiscovery,
                                                    productSurfaceTelemetry: productSurfaceTelemetry)
        controller.suggestionFilter = suggestionFilter
        install(controller: controller,
                animated: deferAutocompleteReveal ? false : animated,
                additionalInsets: UIEdgeInsets(top: 0, left: autocompleteHorizontalInset, bottom: 0, right: autocompleteHorizontalInset))
        if deferAutocompleteReveal {
            controller.view.isHidden = true
            pendingDeferredAutocompleteReveal = true
        }
        controller.delegate = autocompleteDelegate
        controller.presentationDelegate = self
        autocompleteController = controller
        if let pendingSuggestionsSectionTitle {
            controller.setSectionTitle(pendingSuggestionsSectionTitle)
        }
    }

    private func removeAutocomplete(animated: Bool) {
        if let popoverController = popoverSearchController {
            popoverController.tearDown()
            removeController(popoverController, animated: animated)
            popoverSearchController = nil
            popoverSearchSource = nil
        }
        guard let controller = autocompleteController else { return }
        removeController(controller, animated: deferAutocompleteReveal ? false : animated)
        autocompleteController = nil
        pendingDeferredAutocompleteReveal = false
    }

    private func removeNewTabPage(animated: Bool) {
        guard let controller = newTabPage else { return }
        removeController(controller, animated: animated)
        newTabPage = nil
    }

    private func removeController(_ controller: UIViewController, animated: Bool) {
        controller.willMove(toParent: nil)

        let finalize = {
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }

        if animated {
            UIView.animate(withDuration: 0.2) {
                controller.view.alpha = 0.0
            } completion: { _ in
                finalize()
            }
        } else {
            finalize()
        }
    }

    private func install(controller: UIViewController,
                         animated: Bool,
                         additionalInsets: UIEdgeInsets = .zero,
                         completion: @escaping () -> Void = {}) {
        addChild(controller)
        controller.view.frame = containerView.bounds
        containerView.addSubview(controller.view)

        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: -additionalInsets.top),
            containerView.leftAnchor.constraint(equalTo: controller.view.leftAnchor, constant: -additionalInsets.left),
            containerView.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: additionalInsets.bottom),
            containerView.rightAnchor.constraint(equalTo: controller.view.rightAnchor, constant: additionalInsets.right)
        ])

        if animated {
            controller.view.alpha = 0
            UIView.animate(withDuration: 0.2, animations: {
                controller.view.alpha = 1
            }, completion: { _ in
                controller.didMove(toParent: self)
                completion()
            })
        } else {
            controller.view.alpha = 1
            controller.didMove(toParent: self)
            completion()
        }
    }

}

extension SuggestionTrayViewController: AutocompleteViewControllerPresentationDelegate {
    
    func autocompleteDidChangeContentHeight(height: CGFloat) {
        guard !fullHeightConstraint.isActive else { return }
        variableHeightConstraint.constant = max(height, Constant.suggestionTrayInitialHeight)
    }

    func autocompleteDidReloadResults(_ controller: AutocompleteViewController) {
        if controller.suggestionFilter == .urlsOnly {
            view.isHidden = controller.isEmpty
            onURLFallbackVisibilityChanged?()
            return
        }
        if pendingDeferredAutocompleteReveal, controller === autocompleteController {
            pendingDeferredAutocompleteReveal = false
            controller.view.isHidden = false
        }
    }

}

extension SuggestionTrayViewController {
    
    // Only gets called if system theme changes while tray is open
    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        // only update the color if one has been set
        if backgroundView.backgroundColor != nil {
            backgroundView.backgroundColor = theme.tableCellBackgroundColor
        }
    }
    
}

private extension SuggestionTrayViewController {
    enum Constant {
        static let suggestionTrayInitialHeight = 380.0
        static let fillTopInset: CGFloat = 0
        static let floatingTopInset: CGFloat = 4
        static let popoverCornerRadius: CGFloat = 36
    }

    func applyTopConstraintForLayoutMode() {
        let baseInset = fullWidthConstraint.isActive ? Constant.fillTopInset : Constant.floatingTopInset
        topConstraint.constant = baseInset + additionalTopInset
    }
}
