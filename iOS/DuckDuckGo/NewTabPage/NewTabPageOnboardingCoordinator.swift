//
//  NewTabPageOnboardingCoordinator.swift
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

import SwiftUI
import Core
import DesignResourcesKit
import Onboarding

enum NewTabPageOnboardingDialogKind: Equatable {
    case contextual
    case duckAICompletion
}

@MainActor
protocol NewTabPageOnboardingHosting: NewTabPage {
    func setOnboardingContentHidden(_ hidden: Bool, for dialog: NewTabPageOnboardingDialogKind)
}

/// Shares the contextual onboarding sequence between the legacy and redesigned pages.
@MainActor
final class NewTabPageOnboardingCoordinator {
    weak var page: (any NewTabPageOnboardingHosting)?

    private let newTabDialogFactory: any NewTabDaxDialogProviding
    private let daxDialogsManager: DaxDialogsManaging
    private let onboardingFlowProvider: OnboardingFlowProviding
    private let floatingUIManager: FloatingUIManaging
    private let tutorialSettings: TutorialSettings
    private let contextualContentProvider: ContextualOnboardingContentProviding
    private let unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding
    private var presentationGeneration = 0
    private var hostingController: UIHostingController<AnyView>?
    private var daxDialogTopConstraint: NSLayoutConstraint?
    private var isShowingDuckAICompletionDialog = false
    private var didHideBarsForChatPathVisitSiteDialog = false
    private var hiddenContentDialog: NewTabPageOnboardingDialogKind?
    private var didHideLogo = false
    private var presentedSpec: DaxDialogs.HomeScreenSpec?
    private var isCompletionPending = false

    var isPresentingDialog: Bool { hiddenContentDialog != nil }

    var isAwaitingChatPathCompletion: Bool {
        daxDialogsManager.chatPathPhase == .trackerToEOJ && daxDialogsManager.isAIChatEnabled && hostingController == nil
    }

    private var chromeDelegate: BrowserChromeDelegate? { page?.chromeDelegate }
    private var parent: UIViewController? { page?.parent }

    init(newTabDialogFactory: any NewTabDaxDialogProviding,
         daxDialogsManager: DaxDialogsManaging,
         onboardingFlowProvider: OnboardingFlowProviding,
         floatingUIManager: FloatingUIManaging,
         tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
         contextualContentProvider: ContextualOnboardingContentProviding = ContextualOnboardingContentProvider(),
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature()) {
        self.newTabDialogFactory = newTabDialogFactory
        self.daxDialogsManager = daxDialogsManager
        self.onboardingFlowProvider = onboardingFlowProvider
        self.floatingUIManager = floatingUIManager
        self.tutorialSettings = tutorialSettings
        self.contextualContentProvider = contextualContentProvider
        self.unifiedToggleInputFeature = unifiedToggleInputFeature
    }

    func pageDidAppear() {
        guard !isShowingDuckAICompletionDialog, !isCompletionPending else { return }
        showNextDaxDialog()
    }

    func pageWillDisappear() {
        dismissDuckAICompletionDialogIfNeededOnEditingEnd()
        // Ordinary dialogs stay attached when a modal temporarily covers the page.
    }

    func detach() {
        dismissDuckAICompletionDialogIfNeededOnEditingEnd()
        dismissHostingController(didFinishNTPOnboarding: true, animateBars: false)
    }

    private func setLogoHidden(_ hidden: Bool) {
        // Only restore a logo this coordinator hid; repeated hide requests must reach the shared view.
        guard hidden || didHideLogo else { return }
        didHideLogo = hidden
        page?.setLogoHidden(hidden)
    }

    private func hideOnboardingContent(for dialog: NewTabPageOnboardingDialogKind) {
        hiddenContentDialog = dialog
        page?.setOnboardingContentHidden(true, for: dialog)
    }

    private func restoreOnboardingContentIfNeeded() {
        guard let dialog = hiddenContentDialog else { return }
        hiddenContentDialog = nil
        page?.setOnboardingContentHidden(false, for: dialog)
    }

    private func setUnifiedInputContentOverlaySuppressed(_ suppressed: Bool) {
        chromeDelegate?.setUnifiedInputContentOverlaySuppressed(suppressed)
    }

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

    func showNextDaxDialog() {
        presentNextDaxDialog(event: .nextDialogRequested)
    }

    func onboardingCompleted() {
        presentNextDaxDialog(event: .linearOnboardingCompleted)
    }

    func showDuckAIOnboardingCompletionWithActiveAddressBar(message: String, textEntryMode: TextEntryMode? = nil) {
        dismissHostingController(didFinishNTPOnboarding: false)
        isCompletionPending = true
        hideOnboardingContent(for: .duckAICompletion)
        setLogoHidden(true)
        setUnifiedInputContentOverlaySuppressed(true)
        chromeDelegate?.omniBar.beginEditing(animated: true, forTextEntryMode: textEntryMode)

        let generation = presentationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.presentationGeneration == generation, self.page?.parent != nil else {
                // A newer dialog owns visibility if it has already replaced this request.
                if self.hostingController == nil && self.presentationGeneration == generation {
                    self.isCompletionPending = false
                    self.setUnifiedInputContentOverlaySuppressed(false)
                    self.restoreOnboardingContentIfNeeded()
                    self.setLogoHidden(false)
                    self.page?.view.alpha = 1
                }
                return
            }
            self.isCompletionPending = false
            self.showDuckAIOnboardingCompletionDialog(message: message)
        }
    }

    // MARK: - Onboarding

    private func presentNextDaxDialog(event: NewTabPageOnboardingDialogEvent) {
        // If linear onboarding is not completed do not attempt to present any Dax dialog.
        guard page != nil, tutorialSettings.hasSeenOnboarding else { return }

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
                // Prevent contextual dialogs to show if user does not manually dismiss the end of journey dialog
                daxDialogsManager.setDialogsPriorFinalSeen()
                // Show final dialog
                showDuckAIOnboardingCompletionWithActiveAddressBar(message: UserText.Onboarding.DuckAICPP.Contextual.onboardingEndOfJourneyMessage, textEntryMode: .aiChat)
            }
        }
    }

    private func presentSubscriptionPromotionIfPending() {
        guard daxDialogsManager.subscriptionPromotionPending else {
            dismissHostingController(didFinishNTPOnboarding: true)
            return
        }
        showNextDaxDialogNew(dialogProvider: daxDialogsManager, factory: newTabDialogFactory)
    }

    private func showDuckAIOnboardingCompletionDialog(message: String) {
        guard let mainVC = parent as? MainViewController,
              let coordinator = mainVC.unifiedToggleInputCoordinator,
              coordinator.isOmnibarSession else {
            dismissHostingController(didFinishNTPOnboarding: true)
            setLogoHidden(false)
            page?.view.alpha = 1
            return
        }
        showDuckAIOnboardingCompletionDialogInUTI(mainVC: mainVC, coordinator: coordinator, message: message)
    }

    // Mirrors showDuckAIOnboardingCompletionDialog for UTI mode where no editing-state VC exists.
    // Uses the same overlay-suppression mechanism as showNextDaxDialogNew:
    //   • setUnifiedInputContentOverlaySuppressed(true) hides unifiedInputContentContainer so
    //     the NTP (contentContainer) shows through, keeping the dialog visible while the address
    //     bar is active.  dismissHostingController re-enables the overlay on teardown.
    //   • A single copy in the page's superview (contentContainer's plain UIView) avoids the
    //     nested-UIHostingController warning from adding _UIHostingView into another hosting controller's view.
    // pageWillDisappear clears the completion dialog; detach also removes ordinary dialogs.
    // The onDismiss closure mirrors the legacy path's subscription-promo check.
    private func showDuckAIOnboardingCompletionDialogInUTI(
        mainVC: MainViewController,
        coordinator: UnifiedToggleInputCoordinator,
        message: String
    ) {
        guard let page else { return }
        isShowingDuckAICompletionDialog = true
        // Hide the logo before restoring the page alpha. The completion background is
        // transparent on the legacy page; redesigned modules were hidden before input activation.
        setLogoHidden(true)
        page.view.alpha = 1
        // Mirror showNextDaxDialogNew: suppress the UTI content overlay so the NTP
        // (contentContainer) remains visible while the address bar is active.
        // dismissHostingController re-enables the overlay when the dialog is torn down.
        setUnifiedInputContentOverlaySuppressed(true)

        let generation = presentationGeneration
        let onDismiss = { [weak self, weak mainVC, weak coordinator] in
            guard let self, self.presentationGeneration == generation else { return }
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
                guard self.presentationGeneration == generation else { return }
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
                    collapseUTI { [weak self] in
                        guard self?.presentationGeneration == generation else { return }
                        self?.dismissHostingController(didFinishNTPOnboarding: false,
                                                       updateUnifiedInputContentOverlaySuppression: false)
                        self?.showNextDaxDialog()
                        self?.hostingController?.view.backgroundColor = UIColor(singleUseColor: .rebranding(.backdrop))
                    }
                } else {
                    self.daxDialogsManager.dismiss()
                    self.dismissHostingController(didFinishNTPOnboarding: true)
                    self.setLogoHidden(false)
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
                finishDismissal()
            } else {
                UIView.animate(withDuration: 0.2, animations: { hostingView.alpha = 0 },
                               completion: { _ in finishDismissal() })
            }
        }

        // Overlays the NTP view, visible after the omnibar closes.
        // Parented to mainVC because the legacy page is a UIHostingController<NewTabPageView>:
        // adding one _UIHostingView as a subview of another UIHostingController.view is
        // unsupported and triggers a UIKit warning. the page's superview is the content
        // container's plain UIView, so it is safe to host into.
        let ntpRoot = newTabDialogFactory.createDuckAIFireOnboardingCompletionDialog(message: message, onDismiss: onDismiss)
        let ntpHC = UIHostingController(rootView: ntpRoot)
        ntpHC.view.backgroundColor = .clear
        ntpHC.view.translatesAutoresizingMaskIntoConstraints = false
        self.hostingController = ntpHC
        // The redesigned page hides its modules; the legacy page keeps its background content.
        hideOnboardingContent(for: .duckAICompletion)
        let ntpContainer: UIView = page.view.superview ?? mainVC.view
        mainVC.addChild(ntpHC)
        ntpContainer.addSubview(ntpHC.view)
        // Also shown with the input card focused, so it needs the same offset.
        let ntpTopConstraint = ntpHC.view.topAnchor.constraint(equalTo: page.view.topAnchor,
                                                              constant: floatingDaxDialogTopInset)
        daxDialogTopConstraint = ntpTopConstraint
        NSLayoutConstraint.activate([
            ntpTopConstraint,
            ntpHC.view.leadingAnchor.constraint(equalTo: page.view.leadingAnchor),
            ntpHC.view.trailingAnchor.constraint(equalTo: page.view.trailingAnchor),
            ntpHC.view.bottomAnchor.constraint(equalTo: page.view.bottomAnchor),
        ])
        ntpHC.didMove(toParent: mainVC)
    }

    private func showNextDaxDialogNew(dialogProvider: NewTabDialogSpecProvider, factory: any NewTabDaxDialogProviding) {
        guard let page else { return }
        let nextSpec = dialogProvider.nextHomeScreenMessageNew()
        if let nextSpec, nextSpec == presentedSpec, hostingController != nil {
            setUnifiedInputContentOverlaySuppressed(true)
            return
        }
        dismissHostingController(didFinishNTPOnboarding: false, updateUnifiedInputContentOverlaySuppression: false)

        guard let spec = nextSpec else {
            restoreContentAfterDialogSequenceIfNeeded()
            return
        }
        presentedSpec = spec
        hideOnboardingContent(for: .contextual)
        setUnifiedInputContentOverlaySuppressed(true)

        // The EoJ ("High five!") dialog surfaces with an active address bar in UTI mode so the user
        // can immediately try a search — but only on the duck.ai suggestion path. On the search
        // suggestion path the address bar is activated later via launchNewSearch() in the onDismiss
        // closure, so a premature beginEditing here would cause a visual double-activation glitch.
        //
        // `tryAnonymousSearchMessageSeen` is the persisted discriminator: true on the search path,
        // false on the duck.ai suggestion path (openAIChatFromOnboarding never sets it).
        if spec == .final, unifiedToggleInputFeature.isAvailable,
           !daxDialogsManager.tryAnonymousSearchMessageSeen {
            chromeDelegate?.omniBar.beginEditing(animated: false, forTextEntryMode: .aiChat)
        }

        let generation = presentationGeneration
        let onDismiss: (_ activateSearch: Bool) -> Void = { [weak self] activateSearch in
            guard let self, self.presentationGeneration == generation else { return }

            let nextSpec = dialogProvider.nextHomeScreenMessageNew()
            guard nextSpec != .subscriptionPromotion else {
                self.presentSubscriptionPromotionAfterAddressBarDismissal()
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
            guard self?.presentationGeneration == generation else { return }
            self?.dismissHostingController(didFinishNTPOnboarding: true)

            if spec == .final {
                let nextSpec = dialogProvider.nextHomeScreenMessageNew()
                if nextSpec == .subscriptionPromotion {
                    self?.presentSubscriptionPromotionAfterAddressBarDismissal()
                    return
                }
                dialogProvider.dismiss()
            }

            // Show keyboard when manually dismiss the Dax tips.
            self?.chromeDelegate?.omniBar.beginEditing(animated: true)
        }

        let daxDialogView = makeDialog(for: spec, factory: factory, generation: generation,
                                       onDismiss: onDismiss, onManualDismiss: onManualDismiss)
        let hostingController = UIHostingController(rootView: daxDialogView)
        self.hostingController = hostingController
        hostingController.view.backgroundColor = .clear

        hideBarsIfNeeded(for: spec)

        page.addChild(hostingController)
        page.view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        // Floating UI spans the page behind the focused input card, so start the dialog below it.
        let topConstraint = hostingController.view.topAnchor.constraint(equalTo: page.view.topAnchor,
                                                                       constant: floatingDaxDialogTopInset)
        daxDialogTopConstraint = topConstraint
        NSLayoutConstraint.activate([
            topConstraint,
            hostingController.view.leadingAnchor.constraint(equalTo: page.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: page.view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: page.view.bottomAnchor)
        ])

        hostingController.didMove(toParent: page)
    }

    private func restoreContentAfterDialogSequenceIfNeeded() {
        // The chat-path completion owns visibility during the queued input handoff.
        guard !isAwaitingChatPathCompletion else { return }
        restoreOnboardingContentIfNeeded()
        setLogoHidden(false)
        setUnifiedInputContentOverlaySuppressed(false)
    }

    private func makeDialog(for spec: DaxDialogs.HomeScreenSpec,
                            factory: any NewTabDaxDialogProviding,
                            generation: Int,
                            onDismiss: @escaping (Bool) -> Void,
                            onManualDismiss: @escaping () -> Void) -> AnyView {
        if spec == .final {
            // Every end-of-journey variant (standard / Try-AI) renders through the single
            // content-driven entry point — the content provider decides which variant.
            // Other specs still go through `createDaxDialog` below but we will refactor one by one (strangler pattern).
            return factory.createEndOfJourneyDialog(content: contextualContentProvider.endOfJourneyContent) { [weak self] action in
                guard self?.presentationGeneration == generation else { return }
                switch action {
                case .completeAndActivateSearch: onDismiss(true)
                case .manualDismiss: onManualDismiss()
                case .tryDuckAI: self?.dismissEndOfJourneyTryAIDialog(shouldOpenDuckAI: true)
                case .skip: self?.dismissEndOfJourneyTryAIDialog(shouldOpenDuckAI: false)
                }
            }
        } else {
            return AnyView(factory.createDaxDialog(for: spec, onCompletion: onDismiss, onManualDismiss: onManualDismiss))
        }
    }

    private func hideBarsIfNeeded(for spec: DaxDialogs.HomeScreenSpec) {
        // For the chat-path "try visiting a site" dialog, hide both the address bar and toolbar
        // so the user can only choose from the preset suggestions. Showing the bars lets users
        // bypass the onboarding step (by typing a search or switching tabs), causing edge-cases.
        // Defer to the next run loop so any pending beginEditing() finishes before setBarsHidden
        // (which calls hideKeyboard internally).
        if spec == .subsequent,
            daxDialogsManager.chatPathPhase == .visitSite {
            didHideBarsForChatPathVisitSiteDialog = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.didHideBarsForChatPathVisitSiteDialog, self.page?.parent != nil else { return }
                self.chromeDelegate?.setBarsHidden(true, animated: false, customAnimationDuration: nil)
            }
        }
    }

    /// Hides the logo, collapses the address bar, then presents the subscription promo.
    private func presentSubscriptionPromotionAfterAddressBarDismissal() {
        // Hide the NTP logo before the promo fades in so it doesn't blink through
        // the FadeInView's alpha-0→1 animation.  It will be restored once the UTI
        // deactivates after the user acts on the promo ("No thanks" / proceed).
        setLogoHidden(true)
        dismissAddressBarEditingForSubscriptionPromo(completion: { [weak self] in
            self?.showNextDaxDialog()
            // UIHostingController starts with a clear UIKit background; SwiftUI renders
            // the promo's opaque ContextualBackgroundStyle backdrop asynchronously.
            // Matching the backing view's colour immediately prevents the one-frame gap
            // where whatever is behind the promo (NTP background, logo) shows through.
            self?.hostingController?.view.backgroundColor = UIColor(singleUseColor: .rebranding(.backdrop))
        })
    }

    /// Collapses the address bar (or UTI panel) before showing the subscription promo, then
    /// calls `completion` once the dismissal has finished. Uses UTI-aware collapse when UTI is
    /// active because `omniBar.endEditing()` only resigns the legacy text field and does not
    /// drive the UTI state machine.
    private func dismissAddressBarEditingForSubscriptionPromo(completion: @escaping () -> Void) {
        let generation = presentationGeneration
        let completeIfCurrent = { [weak self] in
            guard self?.presentationGeneration == generation else { return }
            completion()
        }
        if let mainVC = parent as? MainViewController,
           let coordinator = mainVC.unifiedToggleInputCoordinator,
           coordinator.isOmnibarSession {
            mainVC.dismissUnifiedToggleInputToOmnibar(coordinator: coordinator, completion: completeIfCurrent)
        } else {
            chromeDelegate?.omniBar.endEditing()
            completeIfCurrent()
        }
    }

    private func dismissEndOfJourneyTryAIDialog(shouldOpenDuckAI: Bool) {
        // Complete onboarding. On next NTP show subscription
        dismissHostingController(didFinishNTPOnboarding: true)

        // - `shouldOpenDuckAI`: dismiss the dialog and activate Omnibar with .aiChat textEntry mode. ands the user in the Duck.ai-mode address bar. The subscription promo will surface on the next new tab.
        // - `!shouldOpenDuckAI`: dismiss the dialog and shows the subscription promo.
        if shouldOpenDuckAI {
            // Opens Duck.ai via the omnibar path, mirroring showDuckAIOnboardingCompletionWithActiveAddressBar.
            chromeDelegate?.omniBar.beginEditing(animated: true, forTextEntryMode: .aiChat)
        } else {
            // Skip: mirror the standard final dialog's subscription hand-off.
            let nextSpec = daxDialogsManager.nextHomeScreenMessageNew()
            if nextSpec == .subscriptionPromotion {
                presentSubscriptionPromotionAfterAddressBarDismissal()
            } else {
                daxDialogsManager.dismiss()
            }
        }
    }

    /// Offset the contextual onboarding dialog needs to clear the focused unified toggle input card.
    /// Zero outside floating UI, which is the only layout that floats the card over the page.
    private var floatingDaxDialogTopInset: CGFloat {
        guard floatingUIManager.isFloatingUIEnabled else { return 0 }
        return chromeDelegate?.floatingNewTabPageTopObscuredHeight ?? 0
    }

    /// Re-applies the dialog offset after the input card resized — typing, or a Search ↔ Duck.ai
    /// toggle. Neither dirties this page's layout, so the push has to be explicit.
    func refreshContextualOnboardingDialogLayout() {
        updateDaxDialogTopInsetIfNeeded()
    }

    /// Runs on every layout pass (covers rotation and attach) and on the push above. The offset comes
    /// from the card, not from anything downstream of this constraint, so it settles in one pass.
    private func updateDaxDialogTopInsetIfNeeded() {
        guard let daxDialogTopConstraint else { return }
        let inset = floatingDaxDialogTopInset
        guard daxDialogTopConstraint.constant != inset else { return }
        daxDialogTopConstraint.constant = inset
    }

    private func dismissHostingController(didFinishNTPOnboarding: Bool,
                                          updateUnifiedInputContentOverlaySuppression: Bool = true,
                                          animateBars: Bool = true) {
        let didDismissDuckAICompletionDialog = isShowingDuckAICompletionDialog
        if isCompletionPending {
            page?.view.alpha = 1
        }
        if hostingController != nil || isCompletionPending {
            // Cancel callbacks only when a hosted or queued presentation is actually removed.
            presentationGeneration += 1
        }
        isCompletionPending = false
        presentedSpec = nil
        if let hostingController {
            hostingController.willMove(toParent: nil)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
            self.hostingController = nil
            daxDialogTopConstraint = nil
        }
        if updateUnifiedInputContentOverlaySuppression {
            setUnifiedInputContentOverlaySuppressed(false)
        }
        isShowingDuckAICompletionDialog = false
        if didHideBarsForChatPathVisitSiteDialog {
            didHideBarsForChatPathVisitSiteDialog = false
            chromeDelegate?.setBarsHidden(false, animated: animateBars, customAnimationDuration: nil)
        }
        if didDismissDuckAICompletionDialog, let page {
            // Restore NTP visibility that was muted during the chat-path handoff so the
            // empty-state Dax doesn't flash through the editing-state transition.
            page.view.alpha = 1
            page.delegate?.newTabPageDidDismissDuckAIFireOnboardingCompletion(page)
        }
        if didFinishNTPOnboarding {
            restoreOnboardingContentIfNeeded()
            setLogoHidden(false)
        }
    }

    func dismissDuckAICompletionDialogIfNeededOnEditingEnd() {
        guard isShowingDuckAICompletionDialog else { return }
        // Mark EOJ seen before peeking subscriptionPromotionPending — the promo requires
        // finalDaxDialogSeen == true, so checking before this call always returns false.
        daxDialogsManager.setFinalOnboardingDialogSeen()
        let promoPending = daxDialogsManager.subscriptionPromotionPending
        dismissHostingController(didFinishNTPOnboarding: true)
        if !promoPending {
            daxDialogsManager.dismiss()
        }
        // When promoPending, the state machine is left intact: the subscription promo
        // will surface naturally on the next NTP open via viewDidAppear → presentNextDaxDialog().
        ViewHighlighter.hideAll()
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
