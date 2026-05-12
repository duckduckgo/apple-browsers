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
import Onboarding
import RemoteMessaging
import Subscription

final class NewTabPageViewController: UIHostingController<NewTabPageView>, NewTabPage {

    var isShowingLogo: Bool {
        guard favoritesModel.isEmpty else { return false }
        if newTabPageViewModel.escapeHatch != nil {
            let isLandscape = view.bounds.width > view.bounds.height
            return !isLandscape
        }
        return true
    }

    private lazy var borderView = StyledTopBottomBorderView()

    private let newTabDialogFactory: any NewTabDaxDialogProviding
    private let daxDialogsManager: NewTabDialogSpecProvider & SubscriptionPromotionCoordinating

    private let newTabPageViewModel: NewTabPageViewModel
    private let messagesModel: NewTabPageMessagesModel
    private let favoritesModel: FavoritesViewModel
    private let associatedTab: Tab

    private var hostingController: UIHostingController<AnyView>?
    private var isShowingDuckAICompletionDialog = false
    private var isBorderSuppressedForChromeLayout = false

    private let appSettings: AppSettings
    private let appWidthObserver: AppWidthObserver

    private let internalUserCommands: URLBasedDebugCommands
    private let tutorialSettings: TutorialSettings

    var onViewDidAppear: (() -> Void)?

    init(isFocussedState: Bool,
         dismissKeyboardOnScroll: Bool,
         tab: Tab,
         interactionModel: FavoritesListInteracting,
         homePageMessagesConfiguration: HomePageMessagesConfiguration,
         subscriptionDataReporting: SubscriptionDataReporting? = nil,
         newTabDialogFactory: any NewTabDaxDialogProviding,
         daxDialogsManager: NewTabDialogSpecProvider & SubscriptionPromotionCoordinating,
         faviconLoader: FavoritesFaviconLoading,
         remoteMessagingActionHandler: RemoteMessagingActionHandling,
         remoteMessagingImageLoader: RemoteMessagingImageLoading,
         remoteMessagingPixelReporter: RemoteMessagingPixelReporting? = nil,
         fireModePromotionEligibility: FireModePromotionCoordinating? = nil,
         hasEscapeHatch: Bool = false,
         appSettings: AppSettings,
         faviconsCache: FavoritesFaviconCaching,
         subscriptionManager: any SubscriptionManager,
         internalUserCommands: URLBasedDebugCommands,
         narrowLayoutInLandscape: Bool = false,
         appWidthObserver: AppWidthObserver = .shared,
         tutorialSettings: TutorialSettings = DefaultTutorialSettings()) {

        self.associatedTab = tab
        self.newTabDialogFactory = newTabDialogFactory
        self.daxDialogsManager = daxDialogsManager
        self.appSettings = appSettings
        self.appWidthObserver = appWidthObserver
        self.internalUserCommands = internalUserCommands
        self.tutorialSettings = tutorialSettings

        newTabPageViewModel = NewTabPageViewModel(fireTab: tab.fireTab)
        favoritesModel = FavoritesViewModel(isFocussedState: isFocussedState,
                                            favoriteDataSource: FavoritesListInteractingAdapter(favoritesListInteracting: interactionModel),
                                            faviconLoader: faviconLoader,
                                            faviconsCache: faviconsCache)
        messagesModel = NewTabPageMessagesModel(homePageMessagesConfiguration: homePageMessagesConfiguration,
                                                subscriptionDataReporter: subscriptionDataReporting,
                                                messageActionHandler: remoteMessagingActionHandler,
                                                imageLoader: remoteMessagingImageLoader,
                                                pixelReporter: remoteMessagingPixelReporter,
                                                fireModePromotionEligibility: fireModePromotionEligibility,
                                                isOpenedAfterIdle: hasEscapeHatch)

        super.init(rootView: NewTabPageView(isFocussedState: isFocussedState,
                                            narrowLayoutInLandscape: narrowLayoutInLandscape,
                                            dismissKeyboardOnScroll: dismissKeyboardOnScroll,
                                            viewModel: self.newTabPageViewModel,
                                            messagesModel: self.messagesModel,
                                            favoritesViewModel: self.favoritesModel))

        assignFavoriteModelActions()
        messagesModel.onTryFireModeRequested = { [weak self] in
            guard let self else { return }
            self.delegate?.newTabPageDidRequestTryFireMode(self)
        }
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        newTabPageViewModel.escapeHatch = model
        if let model {
            let targetTab = model.targetTab
            newTabPageViewModel.onEscapeHatchTap = { [weak self] in
                guard let self else { return }
                self.delegate?.newTabPageDidRequestSwitchToTab(self, tab: targetTab)
            }
            newTabPageViewModel.onTabSwitcherTap = { [weak self] in
                guard let self else { return }
                self.delegate?.newTabPageDidRequestTabSwitcher(self)
            }
        } else {
            newTabPageViewModel.onEscapeHatchTap = nil
            newTabPageViewModel.onTabSwitcherTap = nil
        }
        updateBorderView()
    }

    func setOpenTabCount(_ count: Int) {
        newTabPageViewModel.openTabCount = count
    }

    func setChromeLayoutContext(isBorderSuppressed: Bool) {
        isBorderSuppressedForChromeLayout = isBorderSuppressed
        updateBorderView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        registerForNotifications()
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

        presentNextDaxDialog()

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

    weak var chromeDelegate: BrowserChromeDelegate?
    weak var delegate: NewTabPageControllerDelegate?

    private func launchNewSearch() {
        // If we are displaying a Subscription promotion on a new tab, do not activate search
        guard !daxDialogsManager.isShowingSubscriptionPromotion else { return }
        chromeDelegate?.omniBar.beginEditing(animated: true)
    }

    func dismiss() {
        notifyDuckAICompletionDismissedIfNeeded()
        chromeDelegate?.setUnifiedInputContentOverlaySuppressed(false)
        delegate = nil
        chromeDelegate = nil
        removeFromParent()
        view.removeFromSuperview()
    }

    func showNextDaxDialog() {
        presentNextDaxDialog()
    }

    func onboardingCompleted() {
        presentNextDaxDialog()
        // Show Keyboard when showing the first Dax tip
        chromeDelegate?.omniBar.beginEditing(animated: true)
    }

    func showDuckAIOnboardingCompletionWithActiveAddressBar(message: String) {
        chromeDelegate?.omniBar.beginEditing(animated: true)
        DispatchQueue.main.async { [weak self] in
            self?.showDuckAIOnboardingCompletionDialog(message: message)
        }
    }

    // MARK: - Onboarding

    private func presentNextDaxDialog() {
        // If linear onboarding is not completed do not attempt to present any Dax dialog.
        guard tutorialSettings.hasSeenOnboarding else { return }
        // Present Dax dialog if needed.
        showNextDaxDialogNew(dialogProvider: daxDialogsManager, factory: newTabDialogFactory)
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

extension NewTabPageViewController {

    func showDuckAIOnboardingCompletionDialog(message: String) {
        dismissHostingController(didFinishNTPOnboarding: false)
        // Completion dialog should not hide NTP background state.
        newTabPageViewModel.finishOnboarding()

        let presentedHostViewController = parent?.presentedViewController ?? parent
        guard let editingController = presentedHostViewController as? OmniBarEditingStateViewController else {
            isShowingDuckAICompletionDialog = false
            return
        }

        isShowingDuckAICompletionDialog = true
        editingController.setLogoHidden(true)

        let onDismiss = { [weak self, weak editingController] in
            guard let self else { return }
            let finishDismissal = {
                editingController?.setLogoHidden(false)
                self.daxDialogsManager.dismiss()
                self.dismissHostingController(didFinishNTPOnboarding: true)
                ViewHighlighter.hideAll()
            }

            guard let hostingView = self.hostingController?.view else {
                finishDismissal()
                return
            }
            hostingView.isUserInteractionEnabled = false
            UIView.animate(withDuration: 0.2, animations: {
                hostingView.alpha = 0
            }, completion: { _ in
                finishDismissal()
            })
        }

        let root = newTabDialogFactory.createExperimentCompletionDialog(message: message, onDismiss: onDismiss)
        let hostingController = UIHostingController(rootView: root)
        self.hostingController = hostingController
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        editingController.addChild(hostingController)
        let container = editingController.contentStackContainerView
        container.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            // Keep the completion content pinned to the top; in bottom-bar mode it gets cropped from the bottom
            // as the bar moves up with the keyboard.
            editingController.isUsingTopBarPositionForLayout ?
                hostingController.view.topAnchor.constraint(equalTo: editingController.contentStackTopAnchor,
                                                            constant: editingController.addressBarToToggleSpacing) :
                hostingController.view.topAnchor.constraint(equalTo: container.topAnchor),
            editingController.isUsingTopBarPositionForLayout ?
                hostingController.view.heightAnchor.constraint(equalTo: container.heightAnchor) :
                hostingController.view.bottomAnchor.constraint(equalTo: editingController.contentStackBottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        hostingController.didMove(toParent: editingController)
        container.bringSubviewToFront(editingController.switchBarVC.view)
    }

    func showNextDaxDialogNew(dialogProvider: NewTabDialogSpecProvider, factory: any NewTabDaxDialogProviding) {
        dismissHostingController(didFinishNTPOnboarding: false, updateUnifiedInputContentOverlaySuppression: false)

        guard let spec = dialogProvider.nextHomeScreenMessageNew() else {
            chromeDelegate?.setUnifiedInputContentOverlaySuppressed(false)
            return
        }
        chromeDelegate?.setUnifiedInputContentOverlaySuppressed(true)

        let onDismiss: (_ activateSearch: Bool) -> Void = { [weak self] activateSearch in
            guard let self else { return }

            let nextSpec = dialogProvider.nextHomeScreenMessageNew()
            guard nextSpec != .subscriptionPromotion else {
                chromeDelegate?.omniBar.endEditing()
                showNextDaxDialog()
                return
            }

            dialogProvider.dismiss()
            self.dismissHostingController(didFinishNTPOnboarding: true)
            if activateSearch {
                // Make the address bar first responder after closing the new tab page final dialog.
                self.launchNewSearch()
            }
        }

        let onManualDismiss: () -> Void = { [weak self] in
            self?.dismissHostingController(didFinishNTPOnboarding: true)

            if spec == .final {
                let nextSpec = dialogProvider.nextHomeScreenMessageNew()
                if nextSpec == .subscriptionPromotion {
                    self?.chromeDelegate?.omniBar.endEditing()
                    self?.showNextDaxDialog()
                    return
                }
                dialogProvider.dismiss()
            }

            // Show keyboard when manually dismiss the Dax tips.
            self?.chromeDelegate?.omniBar.beginEditing(animated: true)
        }

        let daxDialogView = AnyView(factory.createDaxDialog(for: spec, onCompletion: onDismiss, onManualDismiss: onManualDismiss))
        let hostingController = UIHostingController(rootView: daxDialogView)
        self.hostingController = hostingController

        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)

        newTabPageViewModel.startOnboarding()
    }

    private func dismissHostingController(didFinishNTPOnboarding: Bool, updateUnifiedInputContentOverlaySuppression: Bool = true) {
        let didDismissDuckAICompletionDialog = isShowingDuckAICompletionDialog
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        if updateUnifiedInputContentOverlaySuppression {
            chromeDelegate?.setUnifiedInputContentOverlaySuppressed(false)
        }
        isShowingDuckAICompletionDialog = false
        if didDismissDuckAICompletionDialog {
            delegate?.newTabPageDidDismissDuckAIExperimentCompletion(self)
        }
        if didFinishNTPOnboarding {
            self.newTabPageViewModel.finishOnboarding()
        }
    }

    func dismissDuckAICompletionDialogIfNeededOnEditingEnd() {
        guard isShowingDuckAICompletionDialog else { return }
        daxDialogsManager.dismiss()
        dismissHostingController(didFinishNTPOnboarding: true)
    }

    private func notifyDuckAICompletionDismissedIfNeeded() {
        guard isShowingDuckAICompletionDialog else { return }
        isShowingDuckAICompletionDialog = false
        delegate?.newTabPageDidDismissDuckAIExperimentCompletion(self)
    }
}
