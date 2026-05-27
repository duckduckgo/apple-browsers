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

final class NewTabPageViewController: UIHostingController<NewTabPageView>, NewTabPage {

    var isShowingLogo: Bool {
        guard !newTabPageViewModel.isLogoHidden else { return false }
        guard favoritesModel.isEmpty else { return false }
        if newTabPageViewModel.escapeHatch != nil {
            let isLandscape = view.bounds.width > view.bounds.height
            return !isLandscape
        }
        return true
    }

    func setLogoHidden(_ hidden: Bool) {
        newTabPageViewModel.isLogoHidden = hidden
    }

    private lazy var borderView = StyledTopBottomBorderView()

    private let newTabDialogFactory: any NewTabDaxDialogProviding
    private let daxDialogsManager: NewTabDialogSpecProvider & SubscriptionPromotionCoordinating
    private let onboardingFlowProvider: OnboardingFlowProviding

    private let newTabPageViewModel: NewTabPageViewModel
    private let messagesModel: NewTabPageMessagesModel
    private let favoritesModel: FavoritesViewModel
    private let associatedTab: Tab

    private var hostingController: UIHostingController<AnyView>?
    private var isShowingDuckAICompletionDialog = false
    private var isBorderSuppressedForChromeLayout = false
    private var didHideBarsForChatPathVisitSiteDialog = false

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
         onboardingFlowProvider: OnboardingFlowProviding,
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
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature(),
         appWidthObserver: AppWidthObserver = .shared,
         tutorialSettings: TutorialSettings = DefaultTutorialSettings()) {

        self.associatedTab = tab
        self.newTabDialogFactory = newTabDialogFactory
        self.daxDialogsManager = daxDialogsManager
        self.onboardingFlowProvider = onboardingFlowProvider
        self.appSettings = appSettings
        self.appWidthObserver = appWidthObserver
        self.internalUserCommands = internalUserCommands
        self.tutorialSettings = tutorialSettings

        newTabPageViewModel = NewTabPageViewModel(fireTab: tab.fireTab)
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
                                                fireModePromotionEligibility: fireModePromotionEligibility,
                                                isOpenedAfterIdle: { [weak viewModel] in viewModel?.escapeHatch != nil })

        super.init(rootView: NewTabPageView(isFocussedState: isFocussedState,
                                            narrowLayoutInLandscape: narrowLayoutInLandscape,
                                            dismissKeyboardOnScroll: dismissKeyboardOnScroll,
                                            layoutConfiguration: unifiedToggleInputFeature.isAvailable ? .unifiedToggleInput : .standard,
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
        messagesModel.refresh()
        updateBorderView()
    }

    func setChromeLayoutContext(isBorderSuppressed: Bool) {
        isBorderSuppressedForChromeLayout = isBorderSuppressed
        updateBorderView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        registerForNotifications()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // In UTI mode the visit-site dialog's hostingController is parented to MainViewController
        // (not to self) so it lives in unifiedInputContentContainer.  When navigation replaces
        // this NTP with a web view or a fresh NTP, the container can reappear later and show the
        // stale dialog.  Clean it up here before this NTP leaves the screen.
        if let hc = hostingController, hc.parent !== self {
            dismissHostingController(didFinishNTPOnboarding: false)
        }
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

        presentNextDaxDialog(event: .nextDialogRequested)

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
        if let mainVC = parent as? MainViewController,
           let coordinator = mainVC.unifiedToggleInputCoordinator,
           coordinator.isOmnibarSession {
            // UTI mode: expand the UTI pill so the address bar is ready for a new search.
            coordinator.activateInput()
        } else {
            // Duck.ai tailored flow surfaces the omnibar in AI-chat mode by default so users land in the
            // experience the onboarding emphasised. Other flows pass `nil` to let the omnibar fall back
            // to its default mode (search).
            let textEntryMode: TextEntryMode? = onboardingFlowProvider.currentOnboardingFlow == .duckAI ? .aiChat : nil
            chromeDelegate?.omniBar.beginEditing(animated: true, forTextEntryMode: textEntryMode)
        }
    }

    func dismiss() {
        notifyDuckAICompletionDismissedIfNeeded()
        chromeDelegate?.setUnifiedInputContentOverlaySuppressed(false)
        if didHideBarsForChatPathVisitSiteDialog {
            didHideBarsForChatPathVisitSiteDialog = false
            chromeDelegate?.setBarsHidden(false, animated: false, customAnimationDuration: nil)
        }
        delegate = nil
        chromeDelegate = nil
        removeFromParent()
        view.removeFromSuperview()
    }

    func showNextDaxDialog() {
        presentNextDaxDialog(event: .nextDialogRequested)
    }

    func onboardingCompleted() {
        presentNextDaxDialog(event: .linearOnboardingCompleted)
    }

    func showDuckAIOnboardingCompletionWithActiveAddressBar(message: String, textEntryMode: TextEntryMode? = nil) {
        // Note: the editing-state Dax suppression and NTP `view.alpha = 0` are pre-armed
        // synchronously in `MainViewController.tabDidRequestNewTab` /
        // `presentChatPathOnboardingCompletionIfNeeded` BEFORE this async hop runs, so
        // we don't repeat them here — re-setting the pending flag at this point would
        // leak past the EOJ flow and incorrectly suppress the Dax in the next-created
        // editing state (e.g. after the subscription promo's "No, Thanks").
        setLogoHidden(true)
        chromeDelegate?.omniBar.beginEditing(animated: true, forTextEntryMode: textEntryMode)

        DispatchQueue.main.async { [weak self] in
            self?.showDuckAIOnboardingCompletionDialog(message: message)
        }
    }

    // MARK: - Onboarding

    private func presentNextDaxDialog(event: NewTabPageOnboardingDialogEvent) {
        // If linear onboarding is not completed do not attempt to present any Dax dialog.
        guard tutorialSettings.hasSeenOnboarding else { return }

        switch onboardingFlowProvider.currentOnboardingFlow {
        case .default:
            presentDefaultFlowDialog(for: event)
        case .duckAI:
            presentDuckAITailoredDialog(for: event)
        }
    }

    private func presentDefaultFlowDialog(for event: NewTabPageOnboardingDialogEvent) {
        switch event {
        case .nextDialogRequested:
            showNextDaxDialogNew(dialogProvider: daxDialogsManager, factory: newTabDialogFactory)
        case .linearOnboardingCompleted:
            showNextDaxDialogNew(dialogProvider: daxDialogsManager, factory: newTabDialogFactory)
            // Show keyboard when surfacing the first Dax tip after linear onboarding.
            chromeDelegate?.omniBar.beginEditing(animated: true)
        }
    }

    private func presentDuckAITailoredDialog(for event: NewTabPageOnboardingDialogEvent) {
        switch event {
        case .nextDialogRequested:
            // Tailored flow never enters the regular Dax sequence. Only the subscription promo can
            // surface here — chained from the completion dialog's onDismiss via `showNextDaxDialog()`
            // after `setFinalOnboardingDialogSeen()` flips `subscriptionPromotionPending` true.
            presentSubscriptionPromotionIfPending()
        case .linearOnboardingCompleted:
            // Skip branch does not show Dax dialogs. Land the user in a new tab page with the AI-chat-mode address bar prompted.
            if tutorialSettings.hasSkippedOnboarding {
                chromeDelegate?.omniBar.beginEditing(animated: true, forTextEntryMode: .aiChat)
            } else {
                showDuckAIOnboardingCompletionWithActiveAddressBar(message: UserText.Onboarding.DuckAICPP.Contextual.onboardingEndOfJourneyMessage, textEntryMode: .aiChat)
            }
        }
    }

    private func presentSubscriptionPromotionIfPending() {
        guard daxDialogsManager.subscriptionPromotionPending else { return }
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

        // UTI mode: no OmniBarEditingStateViewController is presented; embed the dialog in the
        // UTI's content area (below the bar) and wire up subscription-promo check on dismiss.
        if let mainVC = parent as? MainViewController,
           let coordinator = mainVC.unifiedToggleInputCoordinator,
           coordinator.isOmnibarSession {
            showDuckAIOnboardingCompletionDialogInUTI(mainVC: mainVC, coordinator: coordinator, message: message)
            return
        }

        let presentedHostViewController = parent?.presentedViewController ?? parent
        guard let editingController = presentedHostViewController as? OmniBarEditingStateViewController else {
            isShowingDuckAICompletionDialog = false
            setLogoHidden(false)
            view.alpha = 1
            return
        }

        isShowingDuckAICompletionDialog = true
        editingController.setLogoHidden(true)

        let onDismiss = { [weak self, weak editingController] in
            guard let self else { return }
            let finishDismissal = {
                // Mark EOJ as seen before peeking the next spec so that
                // peekNextHomeScreenMessageExperiment() enters the finalDaxDialogSeen
                // branch and can return .subscriptionPromotion. Without this the
                // chat-path branch returns nil and dismiss() is called immediately,
                // making isEnabled = false and blocking the promo forever (r3257196584).
                self.daxDialogsManager.setFinalOnboardingDialogSeen()
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

    // Mirrors showDuckAIOnboardingCompletionDialog for UTI mode where no editing-state VC exists.
    // The completion dialog is embedded directly in unifiedInputContentContainer below the UTI bar,
    // and the onDismiss closure mirrors the legacy path's subscription-promo check.
    private func showDuckAIOnboardingCompletionDialogInUTI(
        mainVC: MainViewController,
        coordinator: UnifiedToggleInputCoordinator,
        message: String
    ) {
        isShowingDuckAICompletionDialog = true
        // The NTP view is about to become visible (view.alpha = 1 below) but
        // finishOnboarding() has already set isOnboarding = false, so SwiftUI
        // would render the Dax logo on the next frame.  Hide both the NTP logo
        // and the UTI/omnibar logo (shown by the beginEditing transition) so
        // neither flashes through the transparent completion dialog hosting view.
        // Both are restored once the dialog is dismissed.
        setLogoHidden(true)
        coordinator.contentViewController.setLogoHidden(true)
        view.alpha = 1

        let onDismiss = { [weak self, weak mainVC, weak coordinator] in
            guard let self else { return }
            // Collapse the UTI bar explicitly rather than going through omniBar.endEditing()
            // (which only resigns the legacy text field and does not drive the UTI state machine).
            // Takes an optional completion so the subscription promo can be deferred until after
            // the animation finishes (ensuring coordinator.deactivateToOmnibar() has run).
            let collapseUTI = { (completion: (() -> Void)?) in
                if let mainVC, let coordinator = coordinator ?? mainVC.unifiedToggleInputCoordinator {
                    mainVC.dismissUnifiedToggleInputToOmnibar(coordinator: coordinator, completion: completion)
                } else {
                    completion?()
                }
            }
            let finishDismissal = {
                // Mirror the OmniBar path: mark EOJ seen before peeking so that
                // peekNextHomeScreenMessageExperiment() enters the finalDaxDialogSeen
                // branch and can return .subscriptionPromotion (r3257196584).
                self.daxDialogsManager.setFinalOnboardingDialogSeen()
                let nextSpec = self.daxDialogsManager.nextHomeScreenMessageNew()
                if nextSpec == .subscriptionPromotion {
                    // Zero the UTI content container alpha so the UTI Dax can't flash
                    // during the collapse animation.  Restored to 1 by
                    // dismissUnifiedToggleInputToOmnibar's animation completion block.
                    if let mainVC = self.parent as? MainViewController {
                        mainVC.viewCoordinator.unifiedInputContentContainer.alpha = 0
                    }
                    self.dismissHostingController(didFinishNTPOnboarding: true)
                    // Defer showNextDaxDialog to the collapse completion so that
                    // coordinator.deactivateToOmnibar() has already run before the
                    // promo appears.  Without this, tapping "No thanks" quickly
                    // while the collapse animation is still running causes
                    // launchNewSearch() to find isOmnibarSession = true and call
                    // activateInput() instead of omniBar.beginEditing(); the collapse
                    // completion then cancels that session, leaving an empty NTP.
                    collapseUTI { [weak self] in
                        self?.showNextDaxDialog()
                    }
                } else {
                    self.daxDialogsManager.dismiss()
                    self.dismissHostingController(didFinishNTPOnboarding: true)
                    self.setLogoHidden(false)
                    coordinator?.contentViewController.setLogoHidden(false)
                    collapseUTI(nil)
                    ViewHighlighter.hideAll()
                }
            }
            guard let hostingView = self.hostingController?.view else {
                finishDismissal()
                return
            }
            hostingView.isUserInteractionEnabled = false
            // Mark EOJ as seen now (idempotent — finishDismissal also calls it) so we
            // can check subscriptionPromotionPending before deciding whether to animate.
            self.daxDialogsManager.setFinalOnboardingDialogSeen()
            if self.daxDialogsManager.subscriptionPromotionPending {
                // Skip the 0.2s fade: the UTI Dax would appear through the fading dialog
                // before the subscription promo covers it.  An instant dismiss avoids the
                // blink and matches the desired UX ("should disappear right away").
                hostingView.alpha = 0
                finishDismissal()
            } else {
                UIView.animate(withDuration: 0.2, animations: { hostingView.alpha = 0 },
                               completion: { _ in finishDismissal() })
            }
        }

        let root = newTabDialogFactory.createExperimentCompletionDialog(message: message, onDismiss: onDismiss)
        let hostingController = UIHostingController(rootView: root)
        hostingController.view.backgroundColor = UIColor.clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        guard let container = mainVC.viewCoordinator.unifiedInputContentContainer else {
            assertionFailure("unifiedInputContentContainer is nil in UTI completion dialog path")
            isShowingDuckAICompletionDialog = false
            setLogoHidden(false)
            coordinator.contentViewController.setLogoHidden(false)
            return
        }
        self.hostingController = hostingController
        mainVC.addChild(hostingController)
        container.addSubview(hostingController.view)
        // In top-bar mode the UTI bar is above the content area: pin the dialog below the bar.
        // In bottom-bar mode the UTI bar is at the bottom: pin the dialog above the bar so it
        // fills the visible content area instead of collapsing to zero height.
        let isBottomBar = coordinator.cardPosition.isBottom
        NSLayoutConstraint.activate([
            isBottomBar
                ? hostingController.view.topAnchor.constraint(equalTo: container.topAnchor)
                : hostingController.view.topAnchor.constraint(equalTo: coordinator.viewController.view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            isBottomBar
                ? hostingController.view.bottomAnchor.constraint(equalTo: coordinator.viewController.view.topAnchor)
                : hostingController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        hostingController.didMove(toParent: mainVC)
    }

    func showNextDaxDialogNew(dialogProvider: NewTabDialogSpecProvider, factory: any NewTabDaxDialogProviding) {
        dismissHostingController(didFinishNTPOnboarding: false, updateUnifiedInputContentOverlaySuppression: false)

        guard let spec = dialogProvider.nextHomeScreenMessageNew() else {
            // When the chat-path completion dialog (presentChatPathOnboardingCompletionIfNeeded)
            // is about to fire, it drives its own overlay state.  Un-suppressing here while the
            // UTI is active from the premature beginEditing would cause a visual flash of the
            // NTP Dax logo before the completion dialog appears.
            let contextualLogic = daxDialogsManager as? ContextualOnboardingLogic
            let chatPathCompletionPending = contextualLogic?.chatPathPhase == .trackerToEOJ
                && contextualLogic?.isAIChatEnabled == true
            if !chatPathCompletionPending {
                chromeDelegate?.setUnifiedInputContentOverlaySuppressed(false)
            }
            return
        }
        chromeDelegate?.setUnifiedInputContentOverlaySuppressed(true)

        let onDismiss: (_ activateSearch: Bool) -> Void = { [weak self] activateSearch in
            guard let self else { return }

            let nextSpec = dialogProvider.nextHomeScreenMessageNew()
            guard nextSpec != .subscriptionPromotion else {
                // Hide the NTP logo before the promo fades in so it doesn't blink through
                // the FadeInView's alpha-0→1 animation.  It will be restored once the UTI
                // deactivates after the user acts on the promo ("No thanks" / proceed).
                self.setLogoHidden(true)
                chromeDelegate?.omniBar.endEditing()
                showNextDaxDialog()
                // UIHostingController starts with a clear UIKit background; SwiftUI renders
                // the promo's opaque ContextualBackgroundStyle backdrop asynchronously.
                // Matching the backing view's colour immediately prevents the one-frame gap
                // where whatever is behind the promo (NTP background, logo) shows through.
                self.hostingController?.view.backgroundColor = UIColor(singleUseColor: .rebranding(.backdrop))
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
                    // Hide the NTP logo before the promo fades in — mirrors the onDismiss path.
                    self?.setLogoHidden(true)
                    self?.chromeDelegate?.omniBar.endEditing()
                    self?.showNextDaxDialog()
                    // Set the background color to the rebranding backdrop color to prevent the NTP logo from flashing through the completion dialog.
                    self?.hostingController?.view.backgroundColor = UIColor(singleUseColor: .rebranding(.backdrop))
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

        // For the chat-path "try visiting a site" dialog, hide both the address bar and toolbar
        // so the user can only choose from the preset suggestions. Showing the bars lets users
        // bypass the onboarding step (by typing a search or switching tabs), causing edge-cases.
        // Defer to the next run loop so any pending beginEditing() finishes before setBarsHidden
        // (which calls hideKeyboard internally).
        if spec == .subsequent,
           (daxDialogsManager as? ContextualOnboardingLogic)?.chatPathPhase == .visitSite {
            didHideBarsForChatPathVisitSiteDialog = true
            DispatchQueue.main.async { [weak self] in
                self?.chromeDelegate?.setBarsHidden(true, animated: false, customAnimationDuration: nil)
            }
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

    private func dismissHostingController(didFinishNTPOnboarding: Bool, updateUnifiedInputContentOverlaySuppression: Bool = true) {
        let didDismissDuckAICompletionDialog = isShowingDuckAICompletionDialog
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        if updateUnifiedInputContentOverlaySuppression {
            chromeDelegate?.setUnifiedInputContentOverlaySuppressed(false)
        }
        isShowingDuckAICompletionDialog = false
        if didHideBarsForChatPathVisitSiteDialog {
            didHideBarsForChatPathVisitSiteDialog = false
            chromeDelegate?.setBarsHidden(false, animated: true, customAnimationDuration: nil)
        }
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

/// Onboarding-dialog triggers handled by `presentNextDaxDialog(event:)`.
private enum NewTabPageOnboardingDialogEvent {
    /// The linear-onboarding modal has just dismissed. Carries side effects that differ per flow:
    /// - `default` → render next Dax tip + begin editing the omnibar
    /// - `duckAi` → present the completion dialog (or begin editing in `.aiChat` mode when the user skipped onboarding).
    case linearOnboardingCompleted

    /// "Compute and surface the next dialog, if any." Fired by:
    ///  - `viewDidAppear`
    ///  - `forgetAllWithAnimation`'s post-fire callback
    ///  - `showNextDaxDialog()` recursively inside the completion-dialog dismiss chain.
    case nextDialogRequested
}
