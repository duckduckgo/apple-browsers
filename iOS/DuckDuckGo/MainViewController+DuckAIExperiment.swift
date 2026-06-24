//
//  MainViewController+DuckAIExperiment.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AIChat
import Combine
import Core
import DesignResourcesKit
import UIKit

// MARK: - Duck.ai Query Experiment — onboarding fire flow types

/// Tracks the one-time Duck.ai Fire onboarding sequence:
/// idle → awaitingFirstResponse → active → completed.
enum ExperimentDuckAIFireOnboardingState: Equatable {
    /// The experiment flow is not armed for the current tab/session.
    case idle
    /// The Duck.ai onboarding UI is active and we are waiting for the first AI response
    /// before showing the Fire onboarding dialog.
    case awaitingFirstResponse
    /// The Fire onboarding dialog has been triggered and related UI state is locked.
    case active
    /// The Fire onboarding sequence finished and should not be shown again this session.
    case completed
}

/// Stores transient state needed to coordinate the Fire onboarding across
/// async AI responses, delayed retries, and post-fire cleanup.
struct ExperimentDuckAIFireOnboardingFlowContext {
    /// Current position in the Fire onboarding state machine.
    var state: ExperimentDuckAIFireOnboardingState = .idle
    /// Restores the address bar picker after the Fire dialog if the experiment moved it.
    var shouldForcePostFireAddressBarPickerRestore = false
    /// Prevents user interaction with experiment-owned controls while the dialog is active.
    var controlsLocked = false
    /// Pending retry or failsafe trigger used when the dialog cannot be shown immediately.
    var triggerWorkItem: DispatchWorkItem?
    /// Completion copy captured before the final dialog can safely be presented.
    var pendingCompletionDialogMessage: String?

    /// True while the flow is in progress and owns the current UI state.
    var isRunning: Bool {
        switch state {
        case .awaitingFirstResponse, .active:
            return true
        case .idle, .completed:
            return false
        }
    }
}

private enum ExperimentDuckAIFireOnboardingMetrics {
    static let failsafeTriggerDelay: TimeInterval = 2
}

// MARK: - Duck.ai Query Experiment — MainViewController methods

extension MainViewController {

    // MARK: Session setup

    func enforceSingleTabAfterOnboardingIfNeeded() {
        guard experimentDuckAIFireOnboardingFlow.isRunning || experimentDuckAIFireOnboardingFlow.state == .completed,
              let tabToKeep = tabManager.current(createIfNeeded: false) else {
            return
        }

        let tabsToRemove = tabManager.currentTabsModel.tabs.filter { $0 !== tabToKeep.tabModel }
        for tab in tabsToRemove {
            tabManager.remove(tab: tab, clearTabHistory: false)
        }
        tabManager.select(tabToKeep.tabModel, dismissCurrent: false)
        tabsBarController?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
    }

    // MARK: Fire dialog triggering

    func showExperimentFireDialogAfterAIChatResponseIfReady() {
        guard experimentDuckAIFireOnboardingFlow.state == .awaitingFirstResponse,
              currentTab?.isAITab == true else {
            return
        }

        experimentDuckAIFireOnboardingFlow.triggerWorkItem?.cancel()
        experimentDuckAIFireOnboardingFlow.triggerWorkItem = nil
        experimentDuckAIFireOnboardingFlow.state = .active
        // The Duck.ai flow persists the interlude step `.interludeDuckAI` when the interlude started;
        // The reason is that for that specific flow the Duck.ai chat happens in between the linear onboarding and the linear flow needs to resume when the interlude (Duck.ai chat) finishes
        // Overwriting it the resume step with `.duckAIAnswerStep` would lose the signal that linear onboarding needs to resume on relaunch.
        if linearOnboardingContext?.activeInterlude != .duckAI {
            onboardingResumeStepStore.resumeStep = .duckAIAnswerStep
        }
        applyExperimentDuckAIFireChromeState()
        setExperimentFireControlsLocked(true)
        if presentedViewController == nil {
            showFireButtonPulse()
        }
        currentTab?.presentExperimentContextualDaxFireDialog()
    }

    func scheduleExperimentDuckAIFireOnboardingAfterLoadIfNeeded(for tab: TabViewController) {
        guard experimentDuckAIFireOnboardingFlow.state == .awaitingFirstResponse,
              currentTab == tab,
              tab.isAITab else {
            return
        }

        experimentDuckAIFireOnboardingFlow.triggerWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.showExperimentFireDialogAfterAIChatResponseIfReady()
        }
        experimentDuckAIFireOnboardingFlow.triggerWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + ExperimentDuckAIFireOnboardingMetrics.failsafeTriggerDelay,
                                      execute: workItem)
    }

    // MARK: Chrome / UI state

    func applyExperimentDuckAIFireChromeState() {
        setBarsVisibility(1, animated: false, animationDuration: nil)
    }

    func setExperimentFireControlsLocked(_ locked: Bool) {
        guard experimentDuckAIFireOnboardingFlow.controlsLocked != locked else { return }
        experimentDuckAIFireOnboardingFlow.controlsLocked = locked

        let canGoBack = currentTab?.canGoBack ?? false
        let canGoForward = currentTab?.canGoForward ?? false
        viewCoordinator.toolbarBackButton.isEnabled = locked ? false : canGoBack
        viewCoordinator.toolbarForwardButton.isEnabled = locked ? false : canGoForward
        viewCoordinator.omniBar.isBackButtonEnabled = locked ? false : canGoBack
        viewCoordinator.omniBar.isForwardButtonEnabled = locked ? false : canGoForward
        viewCoordinator.toolbarTabSwitcherButton.isEnabled = !locked
        viewCoordinator.menuToolbarButton.isEnabled = !locked
        viewCoordinator.toolbarPasswordsButton.isEnabled = !locked
        viewCoordinator.toolbarBookmarksButton.isEnabled = !locked
        if let tabSwitcherView = viewCoordinator.toolbarTabSwitcherButton.customView {
            tabSwitcherView.alpha = locked ? 0.5 : 1
            tabSwitcherView.isUserInteractionEnabled = !locked
        }
        swipeTabsCoordinator?.isEnabled = !locked
        viewCoordinator.omniBar.barView.isUserInteractionEnabled = !locked
        viewCoordinator.omniBar.barView.menuButton.isUserInteractionEnabled = !locked
        viewCoordinator.omniBar.barView.alpha = locked ? 0.5 : 1

        // Lock Duck.ai unified input controls during the fire onboarding step.
        aiChatTabChatHeaderView?.setOnboardingLocked(locked)
        unifiedToggleInputCoordinator?.setOnboardingControlsLocked(locked)
    }

    // MARK: Completion

    func completeExperimentDuckAIFireOnboarding() {
        experimentDuckAIFireOnboardingFlow.state = .completed
        experimentDuckAIFireOnboardingFlow.triggerWorkItem?.cancel()
        experimentDuckAIFireOnboardingFlow.triggerWorkItem = nil
        // The experiment path skips fireButtonPulseStarted() so no timer auto-hides the highlight.
        // Dismiss it explicitly now that the fire step is complete.
        ViewHighlighter.hideAll()
        // The tracker-blocking demo post-fire sequence (visit-site -> tracker-blocked -> EOJ) is
        // feature-flagged. When enabled, mark this as a chat-first path so DaxDialogs drives that
        // sequence. When disabled, fall back to the standard contextual dialog flow.
        if featureFlagger.isFeatureOn(.onboardingDuckAIQueryTrackersDemoExperiment) {
            daxDialogsManager.setAsChatFirstPath()
        }
        daxDialogsManager.setFireEducationMessageSeen()
        setExperimentFireControlsLocked(false)
        if !aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
            aiChatSettings.enableAIChatSearchInputUserSettings(enable: true)
        }
        if let tabToClose = currentTab?.tabModel {
            closeTab(tabToClose, behavior: .createEmptyTabAtSamePosition, clearTabHistory: false)
        } else {
            updateCurrentTab()
        }
        refreshOmniBar()
        restorePostFireAddressBarPickerIfNeeded()
    }

    func markSearchContextualOnboardingAsSeenForExperiment() {
        daxDialogsManager.setTryAnonymousSearchMessageSeen()
        daxDialogsManager.setSearchMessageSeen()
        experimentDuckAIFireOnboardingFlow.pendingCompletionDialogMessage = nil
        OnboardingResumeCheckpointStore.clearAll(in: onboardingResumeStepStore)
        ensureDuckAiCompletionDialogPresentationPrerequisites()
    }

    func ensureDuckAiCompletionDialogPresentationPrerequisites() {
        // Defer disabling dialogs when a subscription promo is still pending: the NTP's
        // showNextDaxDialogNew will call dialogProvider.dismiss() (equivalent) after the
        // promo is dismissed, so contextual dialogs are disabled at the right time.
        if !daxDialogsManager.subscriptionPromotionPending {
            daxDialogsManager.disableContextualDaxDialogs()
        }
        if !aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
            aiChatSettings.enableAIChatSearchInputUserSettings(enable: true)
        }
    }

    // MARK: Address bar picker restore

    func restorePostFireAddressBarPickerIfNeeded() {
        guard experimentDuckAIFireOnboardingFlow.shouldForcePostFireAddressBarPickerRestore,
              aiChatAddressBarExperience.shouldShowModeToggle else {
            return
        }

        experimentDuckAIFireOnboardingFlow.shouldForcePostFireAddressBarPickerRestore = false

        // Unified toggle can be disabled for this configuration. Force the picker via omnibar mode-toggle path.
        viewCoordinator.setNavigationChromeHidden(false)
        viewCoordinator.navigationBarContainer.alpha = 1
        if let omniBarVC = viewCoordinator.omniBar as? OmniBarViewController {
            let targetMode: TextEntryMode = currentTab?.isAITab == true ? .aiChat : .search
            omniBarVC.setSelectedTextEntryMode(targetMode)
        }
        viewCoordinator.omniBar.endEditing()
        viewCoordinator.omniBar.barView.isUserInteractionEnabled = true
        viewCoordinator.omniBar.barView.menuButton.isUserInteractionEnabled = true
        refreshOmniBar()
        refreshBackForwardButtons()
    }

    // MARK: App resume

    func restorePendingDuckAIAnswerStepIfNeeded() {
        // `.duckAIAnswerStep` (experiment flow) and `.interludeDuckAI` (tailored flow) describe the same
        // physical state — the Fire onboarding is mid-flight and needs its AI tab + Fire dialog restored.
        guard
            [.duckAIAnswerStep, .interludeDuckAI].contains(onboardingResumeStepStore.resumeStep),
            currentTab?.isAITab == true
        else {
            return
        }

        experimentDuckAIFireOnboardingFlow.triggerWorkItem?.cancel()
        experimentDuckAIFireOnboardingFlow.triggerWorkItem = nil
        experimentDuckAIFireOnboardingFlow.state = .awaitingFirstResponse
        setExperimentFireControlsLocked(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await clearDuckAIWebsiteDataForResumeIfNeeded()
            recreateAIChatTabForResumeIfNeeded()
            if let currentTab {
                scheduleExperimentDuckAIFireOnboardingAfterLoadIfNeeded(for: currentTab)
            }
        }
    }

    func recreateAIChatTabForResumeIfNeeded() {
        let query = onboardingResumeStepStore.resumeExperimentPrompt
        if query == nil || query?.isEmpty == true {
            Logger.general.error("DuckAI onboarding resume missing stored prompt; opening AI Chat without a prompt")
        }
        if let tabToClose = currentTab?.tabModel {
            closeTab(tabToClose, behavior: .createEmptyTabAtSamePosition, clearTabHistory: false)
        }
        openAIChat(query, autoSend: query.map { !$0.isEmpty } ?? false, flowType: .mobileAppOnboarding)
    }

    func clearDuckAIWebsiteDataForResumeIfNeeded() async {
        let dataStore = DDGWebsiteDataStoreProvider.current(fireMode: tabManager.currentBrowsingMode == .fire)
        _ = await websiteDataManager.clear(dataStore: dataStore)
    }

    // MARK: Fire confirmation (used from onFirePressed)

    /// Presents the experiment-specific "Delete This Chat" fire confirmation sheet.
    func presentExperimentDuckAIFireConfirmation() {
        let presenter = FireConfirmationPresenter()
        let source: UIView = findFireButton() ?? viewCoordinator.toolbar
        presenter.presentFireConfirmation(
            on: self,
            attachPopoverTo: source,
            tabViewModel: tabManager.viewModelForCurrentTab(),
            pixelSource: FireRequest.Source.browsing,
            fireContext: .duckAIOnboarding,
            browsingMode: tabManager.currentBrowsingMode,
            onConfirm: { [weak self] fireRequest in
                self?.contextualOnboardingPixelReporter.measureFireButtonOnboardingDeleteConfirmed()
                self?.forgetAllWithAnimation(request: fireRequest) {
                    self?.experimentDuckAIFireOnboardingFlow.shouldForcePostFireAddressBarPickerRestore = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self?.refreshOmniBar()
                    }
                    // If Duck.ai flow resume linear onboarding first and then complete duck.ai query 
                    if self?.linearOnboardingContext?.activeInterlude == .duckAI {
                        self?.finishOnboardingInterlude {
                            self?.completeExperimentDuckAIFireOnboarding()
                        }
                    } else {
                        self?.completeExperimentDuckAIFireOnboarding()
                    }
                }
            },
            onCancel: { [weak self] in
                self?.setExperimentFireControlsLocked(true)
                self?.showFireButtonPulse()
            }
        )
    }

}

// MARK: - Onboarding delegate experiment integration

extension MainViewController {

    func onboardingCompletedWithExperimentTransition(controller: UIViewController) {
        enforceSingleTabAfterOnboardingIfNeeded()
        let snapshot = showOnboardingTransitionSnapshot(from: controller)

        // In UTI mode the coordinator is active immediately after openAIChatFromOnboarding fires.
        // Calling setBarsVisibility(0) would kill the UTI session via dismissOmniBar(), so we take
        // a simpler snapshot-only path: dismiss the intro modal, let UTI manage chrome, fade snapshot.
        let isUTIActive = unifiedToggleInputCoordinator != nil

        if isUTIActive {
            prepareUTIChromeForSlideIn()
        }

        controller.dismiss(animated: false) { [weak self] in
            guard let self else { return }
            if isUTIActive {
                self.runUTIOnboardingTransition(snapshot: snapshot)
            } else {
                self.runLegacyOnboardingTransition(snapshot: snapshot)
            }
            self.newTabPageViewController?.onboardingCompleted()
        }
    }

    // Slide UTI chrome off-screen so it enters the same way the legacy bars do.
    // transform-based so Auto Layout is unaffected and the content area doesn't shift.
    private func prepareUTIChromeForSlideIn() {
        let safeTop = view.safeAreaInsets.top
        let headerH = viewCoordinator.aiChatTabChatHeaderContainer.bounds.height
        viewCoordinator.aiChatTabChatHeaderContainer.transform =
            CGAffineTransform(translationX: 0, y: -(headerH + safeTop))

        let safeBottom = view.safeAreaInsets.bottom
        let inputBarH = viewCoordinator.navigationBarContainer.bounds.height
        viewCoordinator.navigationBarContainer.transform =
            CGAffineTransform(translationX: 0, y: inputBarH + safeBottom)
    }

    private func runUTIOnboardingTransition(snapshot: UIView?) {
        viewCoordinator.aiChatTabChatHeaderContainer.alpha = 0
        viewCoordinator.navigationBarContainer.alpha = 0
        viewCoordinator.statusBackground.alpha = 0

        let chromeRevealDelay: TimeInterval = 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + chromeRevealDelay) {
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                snapshot?.alpha = 0
                self.viewCoordinator.aiChatTabChatHeaderContainer.transform = .identity
                self.viewCoordinator.navigationBarContainer.transform = .identity
            } completion: { _ in
                self.hideOnboardingTransitionSnapshot(snapshot)
            }
        }

        // Hide content so no partially-loaded web view bleeds through the fading snapshot.
        viewCoordinator.contentContainer.alpha = 0

        // Full-screen surface fill placed behind the content container. This prevents the
        // root view's surfaceCanvas background from bleeding through the transparent
        // contentContainer during both the snapshot fade and the subsequent content fade-in.
        // It must be removed only after contentContainer is fully opaque.
        let transitionFill = UIView()
        transitionFill.backgroundColor = UIColor(singleUseColor: .duckAIWebViewBackground)
        var fillFrame = view.bounds
        fillFrame.size.height -= view.safeAreaInsets.bottom
        transitionFill.frame = fillFrame
        transitionFill.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        transitionFill.isUserInteractionEnabled = false
        view.insertSubview(transitionFill, belowSubview: viewCoordinator.contentContainer)

        UIView.animate(withDuration: 0.3) {
            snapshot?.alpha = 0
            self.viewCoordinator.aiChatTabChatHeaderContainer.alpha = 1
            self.viewCoordinator.navigationBarContainer.alpha = 1
            self.viewCoordinator.statusBackground.alpha = 1
        } completion: { _ in
            self.hideOnboardingTransitionSnapshot(snapshot)

            let revealContent = {
                UIView.animate(withDuration: 0.25) {
                    self.viewCoordinator.contentContainer.alpha = 1
                } completion: { _ in
                    transitionFill.removeFromSuperview()
                }
            }

            // Trigger the fade-in only once the web view has finished loading so the
            // content is rendered before it becomes visible, not while it's still blank.
            guard let webView = self.currentTab?.webView, webView.isLoading else {
                revealContent()
                return
            }

            var cancellable: AnyCancellable?
            cancellable = webView.publisher(for: \.isLoading)
                .filter { !$0 }
                .first()
                // delay before the web view content starts rendering before revealing it
                .delay(for: .seconds(0.5), scheduler: DispatchQueue.main)
                .sink { _ in
                    cancellable = nil
                    revealContent()
                }
            _=cancellable // suppress warning
        }
    }

    private func runLegacyOnboardingTransition(snapshot: UIView?) {
        let chromeRevealDelay: TimeInterval = 0.05
        let chromeRevealDuration: CGFloat = 0.25
        let onboardingTransitionBottomFillView = showOnboardingTransitionBottomFill()

        setBarsVisibility(0, animated: false, animationDuration: nil)
        viewCoordinator.toolbar.alpha = 1 // keep toolbar at its off-screen start position
        setOnboardingChromeOffscreenStartPosition()
        viewCoordinator.statusBackground.alpha = 0
        viewCoordinator.topSlideContainer.alpha = 0
        onboardingTransitionBottomFillView?.alpha = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + chromeRevealDelay) {
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                UIView.animate(withDuration: 0.25) {
                    snapshot?.alpha = 0
                } completion: { _ in
                    self.hideOnboardingTransitionSnapshot(snapshot)
                    self.hideOnboardingTransitionBottomFill(onboardingTransitionBottomFillView)
                }
            }
            self.setBarsVisibility(1, animated: true, animationDuration: chromeRevealDuration)
            UIView.animate(withDuration: chromeRevealDuration) {
                self.viewCoordinator.statusBackground.alpha = 1
                self.viewCoordinator.topSlideContainer.alpha = 1
                onboardingTransitionBottomFillView?.alpha = 1
            }
            CATransaction.commit()
        }
    }

    func openAIChatFromOnboarding(_ query: String?, autoSend: Bool, flowType: AIChatOnboardingFlowType) {
        let shouldArmExperimentFireOnboarding = autoSend && experimentDuckAIFireOnboardingFlow.state != .completed
        experimentDuckAIFireOnboardingFlow.triggerWorkItem?.cancel()
        experimentDuckAIFireOnboardingFlow.triggerWorkItem = nil

        if shouldArmExperimentFireOnboarding {
            experimentDuckAIFireOnboardingFlow.state = .awaitingFirstResponse
            // Don't overwrite the tailored flow's interlude checkpoint with .duckAIAnswerStep as it's the signal that
            // linear onboarding needs to resume after the Fire flow.
            if linearOnboardingContext?.activeInterlude != .duckAI {
                onboardingResumeStepStore.resumeStep = .duckAIAnswerStep
            }
            onboardingResumeStepStore.resumeExperimentPrompt = query
            enforceSingleTabAfterOnboardingIfNeeded()
        } else if experimentDuckAIFireOnboardingFlow.state != .completed {
            experimentDuckAIFireOnboardingFlow.state = .idle
        }

        setExperimentFireControlsLocked(shouldArmExperimentFireOnboarding)
        openAIChat(query, autoSend: autoSend, flowType: flowType)
    }

    func clearDuckAIOnboardingResumeStepIfNeeded() {
        if experimentDuckAIFireOnboardingFlow.state != .awaitingFirstResponse,
           experimentDuckAIFireOnboardingFlow.state != .active {
            OnboardingResumeCheckpointStore.clearAll(in: onboardingResumeStepStore)
        }
    }

    private func showOnboardingTransitionSnapshot(from controller: UIViewController) -> UIView? {
        guard let snapshot = controller.view.snapshotView(afterScreenUpdates: false) else { return nil }

        snapshot.alpha = 1
        snapshot.frame = view.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.isUserInteractionEnabled = false
        // Keep snapshot above page content but below browser chrome.
        view.insertSubview(snapshot, aboveSubview: viewCoordinator.contentContainer)
        return snapshot
    }

    private func hideOnboardingTransitionSnapshot(_ snapshot: UIView?) {
        guard let snapshot else { return }
        snapshot.removeFromSuperview()
    }

    private func showOnboardingTransitionBottomFill() -> UIView? {
        let fill = UIView()
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.isUserInteractionEnabled = false
        fill.backgroundColor = ThemeManager.shared.currentTheme.barBackgroundColor
        view.insertSubview(fill, belowSubview: viewCoordinator.toolbar)
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fill.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // Extend through the toolbar area to avoid transparent toolbar bleed-through during handoff.
            fill.topAnchor.constraint(equalTo: viewCoordinator.toolbar.topAnchor)
        ])
        return fill
    }

    private func hideOnboardingTransitionBottomFill(_ fill: UIView?) {
        guard let fill else { return }
        fill.removeFromSuperview()
    }

    private func setOnboardingChromeOffscreenStartPosition() {
        let browserTabsOffset = viewCoordinator.tabBarContainer.isHidden ? 0 : viewCoordinator.tabBarContainer.frame.size.height
        let navBarHeight = viewCoordinator.navigationBarContainer.frame.size.height
        let safeAreaTop = view.safeAreaInsets.top

        // Move tab strip fully above the visible region (including safe-area inset).
        viewCoordinator.constraints.tabBarContainerTop.constant = -(browserTabsOffset + safeAreaTop)
        // Move navigation bar container fully above the visible region as well.
        viewCoordinator.constraints.navigationBarContainerTop.constant = -(navBarHeight + browserTabsOffset + safeAreaTop)
        view.layoutIfNeeded()
    }
}
