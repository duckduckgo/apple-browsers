//
//  NewTabPageViewController.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import SwiftUI
import DDGSync
import Bookmarks
import BrowserServicesKit
import Core
import DesignResourcesKit
import Onboarding
import RemoteMessaging
import Subscription

final class NewTabPageViewController: UIHostingController<NewTabPageView>, NewTabPage, RemoteMessagePresenting {

    var isShowingLogo: Bool {
        guard !newTabPageViewModel.isLogoHidden else { return false }
        return restingContentIsLogo
    }

    var isShowingFavorites: Bool {
        restingContentIsFavorites && !newTabPageViewModel.isFavoritesHidden
    }

    /// What the NTP shows at rest (logo vs favorites), independent of the transient
    /// `isLogoHidden`/`isFavoritesHidden` flags the focus/dismiss handoff toggles. The dismiss path
    /// uses these to pick the right handoff while those flags are still mid-transition.
    var restingContentIsLogo: Bool {
        guard favoritesModel.isEmpty else { return false }
        if newTabPageViewModel.escapeHatch != nil {
            return view.bounds.width <= view.bounds.height
        }
        return true
    }

    var restingContentIsFavorites: Bool {
        !favoritesModel.isEmpty
    }

    func setLogoHidden(_ hidden: Bool) {
        newTabPageViewModel.isLogoHidden = hidden
    }

    func setFavoritesHidden(_ hidden: Bool) {
        newTabPageViewModel.isFavoritesHidden = hidden
    }

    private lazy var borderView = StyledTopBottomBorderView()

    private let onboardingCoordinator: NewTabPageOnboardingCoordinator

    private let newTabPageViewModel: NewTabPageViewModel
    let messagesModel: NewTabPageMessagesModel
    let favoritesModel: FavoritesViewModel
    private let associatedTab: Tab

    var isShowingDuckAICompletionDialog: Bool { onboardingCoordinator.isShowingDuckAICompletionDialog }
    private var isBorderSuppressedForChromeLayout = false
    private let appSettings: AppSettings
    private let appWidthObserver: AppWidthObserver
    private let floatingUIManager: FloatingUIManaging
    private let notificationCenter: NotificationCenter

    private let internalUserCommands: URLBasedDebugCommands

    private(set) var isRemoteMessageSurfacePresented = false

    var onViewDidAppear: (() -> Void)?

    init(isFocussedState: Bool,
         openedAfterIdle: Bool = false,
         dismissKeyboardOnScroll: Bool,
         tab: Tab,
         interactionModel: FavoritesListInteracting,
         homePageMessagesConfiguration: HomePageMessagesConfiguration,
         subscriptionDataReporting: SubscriptionDataReporting? = nil,
         newTabDialogFactory: any NewTabDaxDialogProviding,
         daxDialogsManager: DaxDialogsManaging,
         onboardingFlowProvider: OnboardingFlowProviding,
         faviconLoader: FavoritesFaviconLoading,
         remoteMessagingActionHandler: RemoteMessagingActionHandling,
         remoteMessagingImageLoader: RemoteMessagingImageLoading,
         remoteMessagingPixelReporter: RemoteMessagingPixelReporting? = nil,
         appSettings: AppSettings,
         faviconsCache: FavoritesFaviconCaching,
         subscriptionManager: any SubscriptionManager,
         internalUserCommands: URLBasedDebugCommands,
         narrowLayoutInLandscape: Bool = false,
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature(),
         floatingUIManager: FloatingUIManaging = FloatingUIManager(
            isFloatingUIFeatureEnabled: false
         ),
         appWidthObserver: AppWidthObserver = .shared,
         notificationCenter: NotificationCenter = .default,
         tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
         contextualContentProvider: ContextualOnboardingContentProviding = ContextualOnboardingContentProvider()) {

        onboardingCoordinator = NewTabPageOnboardingCoordinator(newTabDialogFactory: newTabDialogFactory,
                                                               daxDialogsManager: daxDialogsManager,
                                                               onboardingFlowProvider: onboardingFlowProvider,
                                                               floatingUIManager: floatingUIManager,
                                                               tutorialSettings: tutorialSettings,
                                                               contextualContentProvider: contextualContentProvider)
        self.associatedTab = tab
        self.appSettings = appSettings
        self.appWidthObserver = appWidthObserver
        self.floatingUIManager = floatingUIManager
        self.notificationCenter = notificationCenter
        self.internalUserCommands = internalUserCommands

        newTabPageViewModel = NewTabPageViewModel(fireTab: tab.fireTab)
        newTabPageViewModel.openedAfterIdle = openedAfterIdle
        favoritesModel = FavoritesViewModel(isFocussedState: isFocussedState,
                                            favoriteDataSource: FavoritesListInteractingAdapter(favoritesListInteracting: interactionModel),
                                            faviconLoader: faviconLoader,
                                            faviconsCache: faviconsCache)
        let viewModel = newTabPageViewModel
        messagesModel = NewTabPageMessagesModel(homePageMessagesConfiguration: homePageMessagesConfiguration,
                                                subscriptionDataReporter: subscriptionDataReporting,
                                                messageActionHandler: remoteMessagingActionHandler,
                                                imageLoader: remoteMessagingImageLoader,
                                                pixelReporter: remoteMessagingPixelReporter,
                                                isOpenedAfterIdle: { [weak viewModel] in viewModel?.openedAfterIdle ?? false })

        super.init(rootView: NewTabPageView(isFocussedState: isFocussedState,
                                            narrowLayoutInLandscape: narrowLayoutInLandscape,
                                            dismissKeyboardOnScroll: dismissKeyboardOnScroll,
                                            layoutConfiguration: unifiedToggleInputFeature.isAvailable ? .unifiedToggleInput : .standard,
                                            viewModel: self.newTabPageViewModel,
                                            messagesModel: self.messagesModel,
                                            favoritesViewModel: self.favoritesModel))

        onboardingCoordinator.page = self
        assignFavoriteModelActions()
        assignSessionInstrumentationActions()
        messagesModel.onMessageVisibilityChanged = { [weak self] in
            self?.notifyRemoteMessageSurfaceChanged()
        }
    }

    private func assignSessionInstrumentationActions() {
        newTabPageViewModel.onDidScroll = { [weak self] in
            guard let self else { return }
            delegate?.newTabPageDidScroll(self)
        }

        messagesModel.onMessageInteraction = { [weak self] interaction in
            guard let self else { return }
            delegate?.newTabPage(self, didInteractWithMessage: interaction)
        }
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        newTabPageViewModel.escapeHatch = model
        newTabPageViewModel.openedAfterIdle = (model != nil)
        messagesModel.refresh()
        updateBorderView()
    }

    func setOpenedAfterIdle(_ openedAfterIdle: Bool) {
        newTabPageViewModel.openedAfterIdle = openedAfterIdle
        messagesModel.refresh()
    }

    func setChromeLayoutContext(isBorderSuppressed: Bool) {
        isBorderSuppressedForChromeLayout = isBorderSuppressed
        updateBorderView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        registerForNotifications()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onboardingCoordinator.refreshContextualOnboardingDialogLayout()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onboardingCoordinator.pageWillDisappear()
        isRemoteMessageSurfacePresented = false
        notifyRemoteMessageSurfaceChanged()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        view.backgroundColor = UIColor(designSystemColor: .background)

        // If there's no tab switcher then this will be true, if there is a tabswitcher then only allow the
        // stuff below to happen if it's being dismissed
        guard presentedViewController?.isBeingDismissed ?? true else {
            return
        }

        onViewDidAppear?()
        onViewDidAppear = nil

        associatedTab.viewed = true
        isRemoteMessageSurfacePresented = true
        notifyRemoteMessageSurfaceChanged()

        onboardingCoordinator.pageDidAppear()

        if !favoritesModel.isEmpty {
            borderView.insertSelf(into: view)
            updateBorderView()
        }
    }

    func setSectionTitle(_ title: String?) {
        newTabPageViewModel.sectionTitle = title
    }

    func setFavoritesEditable(_ editable: Bool) {
        newTabPageViewModel.canEditFavorites = editable
        favoritesModel.canEditFavorites = editable
    }

    func hideBorderView() {
        borderView.isHidden = true
    }

    func widthChanged() {
        updateBorderView()
    }

    func updateBorderView() {
        // Floating UI overlays a glass omnibar over the page surface, so the framing border would
        // expose a strip artifact. Suppress it entirely while floating UI is enabled.
        if floatingUIManager.isFloatingUIEnabled {
            borderView.isHidden = true
            borderView.isTopVisible = false
            borderView.isBottomVisible = false
            return
        }

        if !favoritesModel.isEmpty, isViewLoaded {
            borderView.insertSelf(into: view)
        }

        let shouldShowBorder = !favoritesModel.isEmpty && !isBorderSuppressedForChromeLayout
        let hasEscapeHatch = newTabPageViewModel.escapeHatch != nil
        borderView.isTopVisible = shouldShowBorder && !hasEscapeHatch && appSettings.currentAddressBarPosition == .top
        borderView.isBottomVisible = shouldShowBorder && !appWidthObserver.isLargeWidth
    }

    func registerForNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onSettingsDidDisappear),
                                               name: .settingsDidDisappear,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAddressBarPositionChanged),
                                               name: AppUserDefaults.Notifications.addressBarPositionChanged,
                                               object: nil)
    }

    @objc func onAddressBarPositionChanged() {
        updateBorderView()
    }

    @objc func onSettingsDidDisappear() {
        if self.favoritesModel.hasMissingIcons {
            self.delegate?.newTabPageDidRequestFaviconsFetcherOnboarding(self)
        }
    }

    // MARK: - Private

    private func assignFavoriteModelActions() {
        favoritesModel.onFaviconMissing = { [weak self] in
            guard let self else { return }

            delegate?.newTabPageDidRequestFaviconsFetcherOnboarding(self)
        }

        favoritesModel.onFavoriteURLSelected = { [weak self] favorite in
            guard let self else { return }

            // Handle shortcuts for internal testing
            if let favUrl = favorite.url, let url = URL(string: favUrl), internalUserCommands.handle(url: url) {
                return
            }

            delegate?.newTabPageDidSelectFavorite(self, favorite: favorite)
        }

        favoritesModel.onFavoriteEdit = { [weak self] favorite in
            guard let self else { return }

            delegate?.newTabPageDidEditFavorite(self, favorite: favorite)
        }

        favoritesModel.onFavoriteDeleted = { [weak self] _ in
            guard let self else { return }

            updateBorderView()
        }
    }

    // MARK: - NewTabPage

    var isDragging: Bool { newTabPageViewModel.isDragging }

    var hasInlineSearchInput: Bool { false }

    weak var chromeDelegate: BrowserChromeDelegate?
    weak var delegate: NewTabPageControllerDelegate?

    func dismiss() {
        onboardingCoordinator.detach()
        delegate = nil
        chromeDelegate = nil
        removeFromParent()
        view.removeFromSuperview()
    }

    // MARK: - RMF

    func hasVisibleRemoteMessage(withID messageID: String) -> Bool {
        isRemoteMessageSurfacePresented && hasAppearedRemoteMessage(withID: messageID)
    }

    func hasAppearedRemoteMessage(withID messageID: String) -> Bool {
        messagesModel.hasAppearedRemoteMessage(withID: messageID)
    }

    private func notifyRemoteMessageSurfaceChanged() {
        notificationCenter.post(name: RemoteMessageImpressionReporter.remoteMessageSurfaceDidChange, object: self)
    }

    // MARK: -

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension NewTabPageViewController: HomeScreenTransitionSource {
    var snapshotView: UIView {
        view
    }

    var rootContainerView: UIView {
        view
    }
}

extension NewTabPageViewController: NewTabPageOnboardingHosting {

    func setOnboardingContentHidden(_ hidden: Bool) {
        if hidden {
            newTabPageViewModel.startOnboarding()
        } else {
            newTabPageViewModel.finishOnboarding()
        }
    }

    func showNextDaxDialog() {
        onboardingCoordinator.showNextDaxDialog()
    }

    func onboardingCompleted() {
        onboardingCoordinator.onboardingCompleted()
    }

    func showDuckAIOnboardingCompletionWithActiveAddressBar(message: String, textEntryMode: TextEntryMode? = nil) {
        onboardingCoordinator.showDuckAIOnboardingCompletionWithActiveAddressBar(message: message, textEntryMode: textEntryMode)
    }

    func showDuckAIOnboardingCompletionDialog(message: String) {
        onboardingCoordinator.showDuckAIOnboardingCompletionDialog(message: message)
    }

    func showNextDaxDialogNew(dialogProvider: NewTabDialogSpecProvider, factory: any NewTabDaxDialogProviding) {
        onboardingCoordinator.showNextDaxDialogNew(dialogProvider: dialogProvider, factory: factory)
    }

    func refreshContextualOnboardingDialogLayout() {
        onboardingCoordinator.refreshContextualOnboardingDialogLayout()
    }

    func dismissDuckAICompletionDialogIfNeededOnEditingEnd() {
        onboardingCoordinator.dismissDuckAICompletionDialogIfNeededOnEditingEnd()
    }
}
