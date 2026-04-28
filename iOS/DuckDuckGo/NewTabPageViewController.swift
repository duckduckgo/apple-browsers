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

    private let appSettings: AppSettings
    private let appWidthObserver: AppWidthObserver

    private let internalUserCommands: URLBasedDebugCommands

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
         appSettings: AppSettings,
         faviconsCache: FavoritesFaviconCaching,
         subscriptionManager: any SubscriptionManager,
         internalUserCommands: URLBasedDebugCommands,
         narrowLayoutInLandscape: Bool = false,
         appWidthObserver: AppWidthObserver = .shared) {

        self.associatedTab = tab
        self.newTabDialogFactory = newTabDialogFactory
        self.daxDialogsManager = daxDialogsManager
        self.appSettings = appSettings
        self.appWidthObserver = appWidthObserver
        self.internalUserCommands = internalUserCommands

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
                                                fireModePromotionEligibility: fireModePromotionEligibility)

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
        } else {
            newTabPageViewModel.onEscapeHatchTap = nil
        }
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
        let hasEscapeHatch = newTabPageViewModel.escapeHatch != nil
        borderView.isTopVisible = !hasEscapeHatch && appSettings.currentAddressBarPosition == .top
        borderView.isBottomVisible = !appWidthObserver.isLargeWidth
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
        // Note: the editing-state Dax suppression and NTP `view.alpha = 0` are pre-armed
        // synchronously in `MainViewController.tabDidRequestNewTab` /
        // `presentChatPathOnboardingCompletionIfNeeded` BEFORE this async hop runs, so
        // we don't repeat them here — re-setting the pending flag at this point would
        // leak past the EOJ flow and incorrectly suppress the Dax in the next-created
        // editing state (e.g. after the subscription promo's "No, Thanks").
        chromeDelegate?.omniBar.beginEditing(animated: true)
        DispatchQueue.main.async { [weak self] in
            self?.showDuckAIOnboardingCompletionDialog(message: message)
        }
    }

    // MARK: - Onboarding

    private func presentNextDaxDialog() {
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
            view.alpha = 1
            return
        }

        isShowingDuckAICompletionDialog = true
        editingController.setLogoHidden(true)

        let onDismiss = { [weak self, weak editingController] in
            guard let self else { return }
            let finishDismissal = {
                // Check for subscription promo before ending onboarding, mirroring
                // the same check in showNextDaxDialogNew's onDismiss.
                let nextSpec = self.daxDialogsManager.nextHomeScreenMessageNew()
                if nextSpec == .subscriptionPromotion {
                    // Editing state is about to be dismissed for the subscription promo —
                    // keep the suppressed Dax non-installed so the dismiss animation can't
                    // slide it in along with the editing state's logo Y-offset animation.
                    self.dismissHostingController(didFinishNTPOnboarding: true)
                    self.chromeDelegate?.omniBar.endEditing()
                    self.showNextDaxDialog()
                } else {
                    // Staying in the editing state — lazily install/restore the Dax so
                    // it's visible normally for subsequent visibility updates.
                    editingController?.setLogoHidden(false)
                    self.daxDialogsManager.dismiss()
                    self.dismissHostingController(didFinishNTPOnboarding: true)
                    ViewHighlighter.hideAll()
                }
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
        dismissHostingController(didFinishNTPOnboarding: false)

        guard let spec = dialogProvider.nextHomeScreenMessageNew() else { return }

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

        // For the chat-path "try visiting a site" dialog the keyboard must be visible. We activate
        // the editing state first, then embed the dialog inside it on the next run loop (once
        // `presentedViewController` is set) — mirroring how the completion dialog is embedded.
        if spec == .subsequent, (daxDialogsManager as? ContextualOnboardingLogic)?.chatPathPhase == .visitSite {
            chromeDelegate?.omniBar.beginEditing(animated: true)
            DispatchQueue.main.async { [weak self, weak hostingController] in
                guard let self, let hostingController else { return }
                self.embedDialogInEditingState(hostingController)
            }
            return
        }

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

    private func embedDialogInEditingState(_ hostingController: UIHostingController<AnyView>) {
        guard let editingController = parent?.presentedViewController as? OmniBarEditingStateViewController else {
            // Fallback: embed directly on the NTP if the editing state didn't materialise.
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
            return
        }

        editingController.addChild(hostingController)
        let container = editingController.contentStackContainerView
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            editingController.isUsingTopBarPositionForLayout
                ? hostingController.view.topAnchor.constraint(equalTo: editingController.contentStackTopAnchor,
                                                              constant: editingController.addressBarToToggleSpacing)
                : hostingController.view.topAnchor.constraint(equalTo: container.topAnchor),
            editingController.isUsingTopBarPositionForLayout
                ? hostingController.view.heightAnchor.constraint(equalTo: container.heightAnchor)
                : hostingController.view.bottomAnchor.constraint(equalTo: editingController.contentStackBottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        hostingController.didMove(toParent: editingController)
        container.bringSubviewToFront(editingController.switchBarVC.view)
        newTabPageViewModel.startOnboarding()

        // When the keyboard is dismissed (editing state dismissed by user), rescue the dialog
        // back to the NTP so it remains visible rather than disappearing with the editing state.
        editingController.onViewWillDisappear = { [weak self, weak editingController, weak hostingController] in
            guard let self, let hostingController, hostingController.parent === editingController else { return }
            hostingController.willMove(toParent: nil)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()

            self.addChild(hostingController)
            self.view.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
            ])
            hostingController.didMove(toParent: self)
        }
    }

    private func dismissHostingController(didFinishNTPOnboarding: Bool) {
        let didDismissDuckAICompletionDialog = isShowingDuckAICompletionDialog
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        isShowingDuckAICompletionDialog = false
        if didDismissDuckAICompletionDialog {
            // Restore NTP visibility that was muted during the chat-path handoff so the
            // empty-state Dax doesn't flash through the editing-state transition.
            view.alpha = 1
            delegate?.newTabPageDidDismissDuckAIExperimentCompletion(self)
        }
        if didFinishNTPOnboarding {
            self.newTabPageViewModel.finishOnboarding()
        }
    }

    func dismissDuckAICompletionDialogIfNeededOnEditingEnd() {
        guard isShowingDuckAICompletionDialog else { return }
        let promoPending = daxDialogsManager.subscriptionPromotionPending
        dismissHostingController(didFinishNTPOnboarding: true)
        if !promoPending {
            daxDialogsManager.dismiss()
        }
        // When promoPending, the state machine is left intact: the subscription promo
        // will surface naturally on the next NTP open via viewDidAppear → presentNextDaxDialog().
        ViewHighlighter.hideAll()
    }

    private func notifyDuckAICompletionDismissedIfNeeded() {
        guard isShowingDuckAICompletionDialog else { return }
        isShowingDuckAICompletionDialog = false
        view.alpha = 1
        delegate?.newTabPageDidDismissDuckAIExperimentCompletion(self)
    }
}
