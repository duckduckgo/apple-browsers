//
//  MainViewController+UnifiedToggleInput.swift
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

import AIChat
import Bookmarks
import Combine
import DesignResourcesKit
import os.log
import Subscription
import Suggestions
import UIKit

private let utiMainVCLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "UTI-Constraint")

// MARK: - Unified Toggle Input Setup

extension MainViewController {

    func setUpUnifiedToggleInputIfNeeded() {
        guard unifiedToggleInputFeature.isAvailable else { return }
        logUTI("setUpUnifiedToggleInputIfNeeded:start")

        let coordinator = UnifiedToggleInputCoordinator(isToggleEnabled: aiChatSettings.isAIChatSearchInputUserSettingsEnabled)
        coordinator.delegate = self
        coordinator.updateVoiceSearchAvailability(voiceSearchHelper.isVoiceSearchEnabled)
        self.unifiedToggleInputCoordinator = coordinator

        installUnifiedToggleInputViewController(coordinator.viewController)

        if let omniBarVC = viewCoordinator.omniBar as? DefaultOmniBarViewController {
            omniBarVC.inlineEditingActivating = self
        }

        setUpAIChatTabChatHeader()
        setUpUnifiedInputContentViewController()
        viewCoordinator.hideTopHeaderView()
        viewCoordinator.hideUnifiedInputSectionTitle()

        subscribeToIntentPublisher(coordinator)
        subscribeToModeChanges(coordinator)
        subscribeToSystemEvents()
        subscribeToToggleSettings()
        logUTI("setUpUnifiedToggleInputIfNeeded:end", coordinator: coordinator)
    }

    private func installUnifiedToggleInputViewController(_ inputVC: UnifiedToggleInputViewController) {
        addChild(inputVC)
        inputVC.view.translatesAutoresizingMaskIntoConstraints = false
        viewCoordinator.unifiedToggleInputContainer.addSubview(inputVC.view)
        NSLayoutConstraint.activate([
            inputVC.view.topAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.topAnchor),
            inputVC.view.leadingAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.leadingAnchor),
            inputVC.view.trailingAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.trailingAnchor),
            inputVC.view.bottomAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.bottomAnchor),
        ])
        inputVC.didMove(toParent: self)
    }

    private var isKeyboardVisibleForUTI: Bool {
        let safeAreaFrame = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 0, dy: -additionalSafeAreaInsets.bottom)
        let keyboardFrame = view.keyboardLayoutGuide.layoutFrame
        return keyboardFrame.minY < safeAreaFrame.maxY - 1
    }

    private func logUTI(_ event: String, coordinator: UnifiedToggleInputCoordinator? = nil) {
        let coordinator = coordinator ?? unifiedToggleInputCoordinator
        let displayState = coordinator.map { String(describing: $0.displayState) } ?? "nil"
        let inputMode = coordinator.map { String(describing: $0.inputMode) } ?? "nil"
        let navTopActive = viewCoordinator.constraints.navigationBarContainerTop?.isActive ?? false
        let navBottomActive = viewCoordinator.constraints.navigationBarContainerBottom?.isActive ?? false
        let navBottomConstant = viewCoordinator.constraints.navigationBarContainerBottom?.constant ?? -9999
        let navHeightConstant = viewCoordinator.constraints.navigationBarContainerHeight?.constant ?? -9999
        let navMinY = viewCoordinator.navigationBarContainer.frame.minY
        let navMaxY = viewCoordinator.navigationBarContainer.frame.maxY
        let keyboardTop = view.keyboardLayoutGuide.layoutFrame.minY
        let keyboardVisibleByGuide = isKeyboardVisibleForUTI
        let tabIsAI = currentTab?.isAITab ?? false
        utiMainVCLog.debug(
            "UTILogging | \(event, privacy: .public) | tabIsAI=\(tabIsAI) keyboardShowing=\(self.keyboardShowing) keyboardVisibleByGuide=\(keyboardVisibleByGuide) displayState=\(displayState, privacy: .public) inputMode=\(inputMode, privacy: .public) addrPos=\(String(describing: self.viewCoordinator.addressBarPosition), privacy: .public) navTopActive=\(navTopActive) navBottomActive=\(navBottomActive) navBottomConstant=\(navBottomConstant) navHeightConstant=\(navHeightConstant) navMinY=\(navMinY) navMaxY=\(navMaxY) keyboardTop=\(keyboardTop) keyboardBased=\(self.viewCoordinator.isNavigationBarContainerBottomKeyboardBased)"
        )
    }

    private func subscribeToIntentPublisher(_ coordinator: UnifiedToggleInputCoordinator) {
        coordinator.intentPublisher
            .sink { [weak self] intent in
                self?.handleUnifiedToggleInputIntent(intent)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    private func subscribeToModeChanges(_ coordinator: UnifiedToggleInputCoordinator) {
        coordinator.modeChangePublisher
            .sink { [weak self] mode in
                self?.handleModeChange(mode)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    private func handleModeChange(_ mode: TextEntryMode) {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        logUTI("handleModeChange:start mode=\(mode.rawValue)", coordinator: coordinator)
        if coordinator.isInlineEditingActive {
            handleInlineEditingModeChange(mode, coordinator: coordinator)
        } else if case .aiTab(.expanded) = coordinator.displayState {
            handleAITabModeChange(mode, coordinator: coordinator)
        }
        logUTI("handleModeChange:end mode=\(mode.rawValue)", coordinator: coordinator)
    }

    private func handleInlineEditingModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        logUTI("handleInlineEditingModeChange:start mode=\(mode.rawValue)", coordinator: coordinator)
        let height = coordinator.inlineEditingHeight(for: mode)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.viewCoordinator.constraints.navigationBarContainerHeight.constant = height
            self.viewCoordinator.superview.layoutIfNeeded()
        }
        unifiedInputContentViewController?.setInputMode(mode)
        logUTI("handleInlineEditingModeChange:end mode=\(mode.rawValue)", coordinator: coordinator)
    }

    private func handleAITabModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        logUTI("handleAITabModeChange:start mode=\(mode.rawValue)", coordinator: coordinator)
        let height = coordinator.inlineEditingHeight(for: mode)
        viewCoordinator.constraints.navigationBarContainerHeight.constant = max(height, viewCoordinator.standardNavigationBarContainerHeight)
        updateUnifiedInputContentVisibility(for: coordinator)
        logUTI("handleAITabModeChange:end mode=\(mode.rawValue)", coordinator: coordinator)
    }

    func handleUnifiedToggleInputKeyboardFrameDidChange(keyboardVisible: Bool) {
        guard let coordinator = unifiedToggleInputCoordinator else {
            previousUnifiedToggleKeyboardVisible = keyboardVisible
            return
        }

        let wasKeyboardVisible = previousUnifiedToggleKeyboardVisible
        previousUnifiedToggleKeyboardVisible = keyboardVisible

        if keyboardVisible && !wasKeyboardVisible {
            coordinator.updateInlineEditingInputVisibility(true)
            logUTI("handleUnifiedToggleInputKeyboardFrameDidChange:transitionHiddenToVisible", coordinator: coordinator)
        } else if !keyboardVisible && wasKeyboardVisible {
            coordinator.updateInlineEditingInputVisibility(false)
            logUTI("handleUnifiedToggleInputKeyboardFrameDidChange:transitionVisibleToHidden", coordinator: coordinator)
        }

        coordinator.reconcileAITabExpansion(withInputVisibility: keyboardVisible)

        if case .aiTab(.expanded) = coordinator.displayState, keyboardVisible {
            if !viewCoordinator.isNavigationBarContainerBottomKeyboardBased {
                viewCoordinator.anchorUnifiedToggleInputToKeyboardPreservingHeight()
            }
            let height = coordinator.inlineEditingHeight(for: coordinator.inputMode)
            viewCoordinator.constraints.navigationBarContainerHeight.constant = max(height, viewCoordinator.standardNavigationBarContainerHeight)
            updateUnifiedInputContentVisibility(for: coordinator)
            if !coordinator.viewController.isInputFirstResponder {
                coordinator.activateInput()
            }
            logUTI("handleUnifiedToggleInputKeyboardFrameDidChange:aiTabExpandedVisible", coordinator: coordinator)
            return
        }
    }

    /// `keyboardLayoutGuide` can lag behind or under-report the visual keyboard top in some iOS keyboard states.
    /// Keep a small corrective offset so the UTI stays above the visible keyboard chrome.
    func syncUnifiedToggleInputKeyboardAnchor(keyboardFrameInView: CGRect, keyboardVisible: Bool) {
        guard let coordinator = unifiedToggleInputCoordinator else { return }

        guard case .aiTab(.expanded) = coordinator.displayState,
              keyboardVisible,
              viewCoordinator.isNavigationBarContainerBottomKeyboardBased else {
            if viewCoordinator.constraints.navigationBarContainerBottom.constant != 0 {
                viewCoordinator.constraints.navigationBarContainerBottom.constant = 0
                logUTI("syncUnifiedToggleInputKeyboardAnchor:reset", coordinator: coordinator)
            }
            return
        }

        let guideTop = view.keyboardLayoutGuide.layoutFrame.minY
        let frameTop = keyboardFrameInView.minY
        let effectiveTop = min(guideTop, frameTop)
        let offset = min(0, effectiveTop - guideTop)

        guard abs(viewCoordinator.constraints.navigationBarContainerBottom.constant - offset) > 0.5 else { return }
        viewCoordinator.constraints.navigationBarContainerBottom.constant = offset
        logUTI(
            "syncUnifiedToggleInputKeyboardAnchor:applied guideTop=\(guideTop) frameTop=\(frameTop) offset=\(offset)",
            coordinator: coordinator
        )
    }

    private func subscribeToSystemEvents() {
        NotificationCenter.default.publisher(for: .speechRecognizerDidChangeAvailability)
            .sink { [weak self] _ in
                guard let self else { return }
                self.unifiedToggleInputCoordinator?.updateVoiceSearchAvailability(self.voiceSearchHelper.isVoiceSearchEnabled)
            }
            .store(in: &unifiedToggleInputCancellables)

        NotificationCenter.default.publisher(for: .entitlementsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.currentTab?.isAITab == true else { return }
                self.refreshAIChatTabChatHeaderSubscriptionState()
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    private func subscribeToToggleSettings() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                let enabled = self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled
                coordinator.updateToggleEnabled(enabled)
                self.unifiedInputContentViewController?.isSwipeEnabled = enabled
                self.logUTI("subscribeToToggleSettings:enabled=\(enabled)", coordinator: coordinator)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else { return }
        logUTI("refreshUnifiedToggleInput:start tabIsAI=\(tab.isAITab)", coordinator: coordinator)

        if !tab.isAITab && coordinator.displayState == .hidden &&
            viewCoordinator.aiChatTabChatHeaderContainer.isHidden {
            tab.updateWebViewBottomAnchor(for: viewCoordinator.toolbar.alpha)
            logUTI("refreshUnifiedToggleInput:earlyReturn hidden+nonAI", coordinator: coordinator)
            return
        }

        if tab.isAITab {
            if let userScript = tab.userScripts?.aiChatUserScript {
                coordinator.bindToTab(userScript)
            }
            if viewCoordinator.navigationBarContainer.alpha < 0.99 ||
                viewCoordinator.toolbar.alpha < 0.99 ||
                viewCoordinator.tabBarContainer.alpha < 0.99 {
                showBars()
                logUTI("refreshUnifiedToggleInput:forcedShowBarsForAITab", coordinator: coordinator)
            }
            tab.webView.scrollView.contentInset = .zero
            coordinator.deactivateInlineEditingIfNeeded()
            if case .aiTab = coordinator.displayState {
                logUTI("refreshUnifiedToggleInput:preserveAIState", coordinator: coordinator)
            } else {
                logUTI("refreshUnifiedToggleInput:forceShowCollapsed from state=\(String(describing: coordinator.displayState))", coordinator: coordinator)
                coordinator.showCollapsed()
            }
            viewCoordinator.showAITabChrome()
            updateUnifiedInputContentVisibility(for: coordinator)
            refreshAIChatTabChatHeaderSubscriptionState()
            tab.borderView.isTopVisible = false
            tab.borderView.isBottomVisible = false
        } else {
            coordinator.deactivateInlineEditingIfNeeded()
            coordinator.hide()
            coordinator.unbind()
            viewCoordinator.hideAITabChrome()
            refreshStatusBarBackgroundAfterAIChrome()
            tab.borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
            tab.borderView.isBottomVisible = true
        }

        // Keep the webView bottom anchor in sync when URL transitions change tab type
        // (web -> AI or AI -> web) without switching tabs.
        // Otherwise a stale `-barsMaxHeight` offset can leave a visible gap above the UTI.
        tab.updateWebViewBottomAnchor(for: viewCoordinator.toolbar.alpha)
        logUTI("refreshUnifiedToggleInput:end tabIsAI=\(tab.isAITab)", coordinator: coordinator)
    }

    private func shouldShowUnifiedInputContent(for coordinator: UnifiedToggleInputCoordinator) -> Bool {
        let isAITab = currentTab?.isAITab == true

        switch coordinator.displayState {
        case .hidden, .aiTab(.collapsed):
            return false
        case .inline:
            return true
        case .aiTab(.expanded):
            return !(isAITab && coordinator.inputMode == .aiChat)
        }
    }

    private func shouldOverlayAIChatHeader(for coordinator: UnifiedToggleInputCoordinator) -> Bool {
        guard currentTab?.isAITab == true else { return false }
        guard case .aiTab(.expanded) = coordinator.displayState else { return false }
        return coordinator.inputMode == .search && shouldShowUnifiedInputContent(for: coordinator)
    }

    private func updateAITabHeaderVisibility(for coordinator: UnifiedToggleInputCoordinator) {
        guard currentTab?.isAITab == true else { return }
        if shouldOverlayAIChatHeader(for: coordinator) {
            viewCoordinator.hideAIChatTabChatHeader()
        } else {
            viewCoordinator.showAIChatTabChatHeader()
        }
    }

    private func updateStatusBarBackgroundForAITabOverlay(for coordinator: UnifiedToggleInputCoordinator) {
        guard currentTab?.isAITab == true else { return }

        if shouldOverlayAIChatHeader(for: coordinator) {
            viewCoordinator.statusBackground.backgroundColor = UIColor(designSystemColor: .panel)
        } else if viewCoordinator.isNavigationChromeHidden {
            viewCoordinator.statusBackground.backgroundColor = UIColor(singleUseColor: .duckAIContextualSheetBackground)
        }
    }

    private func updateUnifiedInputContentVisibility(for coordinator: UnifiedToggleInputCoordinator) {
        updateAITabHeaderVisibility(for: coordinator)
        updateStatusBarBackgroundForAITabOverlay(for: coordinator)

        if case .aiTab = coordinator.displayState {
            let shouldShowInlineHeader = shouldOverlayAIChatHeader(for: coordinator)
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(shouldShowInlineHeader ? .active : .hidden)
        }

        if shouldShowUnifiedInputContent(for: coordinator) {
            unifiedInputContentViewController?.setInputMode(coordinator.inputMode, animated: false)
            viewCoordinator.showUnifiedInputContent()
            logUTI("updateUnifiedInputContentVisibility:show", coordinator: coordinator)
        } else {
            viewCoordinator.hideUnifiedInputContent()
            logUTI("updateUnifiedInputContentVisibility:hide", coordinator: coordinator)
        }
    }

    private func setUpAIChatTabChatHeader() {
        let headerView = AIChatTabChatHeaderView()
        headerView.delegate = self
        headerView.translatesAutoresizingMaskIntoConstraints = false
        viewCoordinator.aiChatTabChatHeaderContainer.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.bottomAnchor),
        ])
        self.aiChatTabChatHeaderView = headerView
    }

    private func refreshAIChatTabChatHeaderSubscriptionState() {
        Task { @MainActor [weak self] in
            let isActive = (try? await AppDependencyProvider.shared.subscriptionManager.isFeatureEnabled(.paidAIChat)) ?? false
            self?.aiChatTabChatHeaderView?.configure(isSubscriptionActive: isActive)
        }
    }

    private func setUpUnifiedInputContentViewController() {
        guard let switchBarHandler = unifiedToggleInputCoordinator?.switchBarHandler else { return }

        let contentVC = UnifiedInputContentContainerViewController(switchBarHandler: switchBarHandler)
        contentVC.suggestionTrayDependencies = suggestionTrayDependencies
        contentVC.delegate = self
        contentVC.onDismissRequested = { [weak self] in
            self?.unifiedToggleInputCoordinator?.deactivateInlineEditing()
        }
        contentVC.isSwipeEnabled = unifiedToggleInputCoordinator?.isToggleEnabled ?? true
        unifiedInputContentViewController = contentVC

        guard let container = viewCoordinator.unifiedInputContentContainer else { return }
        addChild(contentVC)
        contentVC.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentVC.view)
        NSLayoutConstraint.activate([
            contentVC.view.topAnchor.constraint(equalTo: container.topAnchor),
            contentVC.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentVC.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentVC.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentVC.didMove(toParent: self)
    }

    private func handleUnifiedToggleInputIntent(_ intent: UnifiedToggleInputIntent) {
        logUTI("handleUnifiedToggleInputIntent:start intent=\(String(describing: intent))")
        switch intent {
        case .showCollapsed:
            viewCoordinator.showUnifiedToggleInput(aboveKeyboard: false)
            viewCoordinator.suggestionTrayContainer.isHidden = true
            viewCoordinator.hideUnifiedInputContent()
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(.hidden)
            viewCoordinator.superview.layoutIfNeeded()
        case .showExpanded:
            viewCoordinator.anchorUnifiedToggleInputToKeyboardPreservingHeight()
            if let coordinator = unifiedToggleInputCoordinator {
                let height = coordinator.inlineEditingHeight(for: coordinator.inputMode)
                viewCoordinator.constraints.navigationBarContainerHeight.constant = max(height, viewCoordinator.standardNavigationBarContainerHeight)
                updateUnifiedInputContentVisibility(for: coordinator)
            }
            viewCoordinator.superview.layoutIfNeeded()
        case .showInlineEditing(let height):
            viewCoordinator.showUnifiedToggleInputInline(expandedHeight: height)
            viewCoordinator.suggestionTrayContainer.isHidden = true
            if let coordinator = unifiedToggleInputCoordinator {
                updateUnifiedInputContentVisibility(for: coordinator)
            }
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(.active)
        case .showInlineInactive:
            viewCoordinator.restoreNavBarToToolbarForInlineInactive()
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(.inactive)
        case .showInlineActive:
            viewCoordinator.restoreNavBarToKeyboardForInlineActive()
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(.active)
        case .hideInlineEditing:
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(.hidden)
            viewCoordinator.hideUnifiedToggleInputInline()
            viewCoordinator.hideUnifiedInputContent()
            suggestionTrayController?.view.isHidden = false
            suggestionTrayController?.view.backgroundColor = nil
            hideSuggestionTray()
            viewCoordinator.suggestionTrayContainer.isHidden = false
        case .hide:
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(.hidden)
            viewCoordinator.hideUnifiedToggleInput()
            viewCoordinator.hideUnifiedInputContent()
        }
        logUTI("handleUnifiedToggleInputIntent:end intent=\(String(describing: intent))")
    }

    func recomputeInlineEditingHeightIfNeeded() {
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.isInlineEditingActive else { return }
        let height = coordinator.inlineEditingHeight(for: coordinator.inputMode)
        viewCoordinator.constraints.navigationBarContainerHeight.constant = height
    }
}

// MARK: - InlineEditingActivating

extension MainViewController: InlineEditingActivating {

    func activateInlineEditingIfNeeded(currentText: String?) -> InlineEditingActivationDecision {
        guard let coordinator = unifiedToggleInputCoordinator,
              currentTab?.isAITab != true else {
            logUTI("activateInlineEditingIfNeeded:allowDefault aiTabOrMissingCoordinator")
            return .allowDefault
        }
        let position: UnifiedToggleInputCardPosition = appSettings.currentAddressBarPosition == .bottom ? .bottom : .top
        coordinator.activateInlineEditing(prefilledText: currentText, inputMode: .search, cardPosition: position)
        logUTI("activateInlineEditingIfNeeded:intercept position=\(String(describing: position))", coordinator: coordinator)
        return .intercept
    }
}

// MARK: - UnifiedToggleInputDelegate

extension MainViewController: UnifiedToggleInputDelegate {

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String) {
        openAIChat(prompt, autoSend: true)
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedToggleInputDidRequestVoiceSearch() {
        let mode = unifiedToggleInputCoordinator?.inputMode ?? .search
        handleVoiceSearchOpenRequest(preferredTarget: mode == .aiChat ? .AIChat : .SERP)
    }
}

// MARK: - UnifiedInputContentContainerViewControllerDelegate

extension MainViewController: UnifiedInputContentContainerViewControllerDelegate {

    func unifiedInputEditingStateDidUpdateQuery(_ query: String) {
    }

    func unifiedInputEditingStateDidSubmitQuery(_ query: String) {
        unifiedToggleInputCoordinator?.clearText()
        unifiedToggleInputCoordinator?.handleExternalQuerySubmission()
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?) {
        unifiedToggleInputCoordinator?.handleExternalPromptSubmission()
        openAIChat(query, autoSend: true)
    }

    func unifiedInputEditingStateDidSelectFavorite(_ favorite: BookmarkEntity) {
        dismissOmniBar()
        guard let urlString = favorite.url, let url = URL(string: urlString) else { return }
        loadUrl(url)
    }

    func unifiedInputEditingStateDidEditFavorite(_ favorite: BookmarkEntity) {
    }

    func unifiedInputEditingStateDidSelectSuggestion(_ suggestion: Suggestion) {
        dismissOmniBar()
        if let url = suggestion.url {
            loadUrl(url)
        } else if case .phrase(let phrase) = suggestion {
            loadQuery(phrase)
        } else if case .askAIChat(let value) = suggestion {
            openAIChat(value, autoSend: true)
        }
    }

    func unifiedInputEditingStateDidRequestVoiceSearch(from mode: TextEntryMode) {
        handleVoiceSearchOpenRequest(preferredTarget: mode == .aiChat ? .AIChat : .SERP)
    }

    func unifiedInputEditingStateDidSelectChatHistory(url: URL) {
        onChatHistorySelected(url: url)
    }

    func unifiedInputEditingStateDidRequestDismiss() {
        unifiedToggleInputCoordinator?.deactivateInlineEditing()
    }

    func unifiedInputEditingStateDidRequestSwitchTab(toIndex index: Int) {
        select(tabAt: index)
    }

    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode) {
        logUTI("unifiedInputEditingStateDidChangeMode mode=\(mode.rawValue)")
        unifiedToggleInputCoordinator?.syncInputModeFromExternalSource(mode)
    }
}

private extension MainViewController {
    func handleUnifiedToggleInputSearchSubmission(_ query: String) {
        viewCoordinator.hideAITabChrome()
        refreshStatusBarBackgroundAfterAIChrome()
        loadQuery(query)
    }
}

// MARK: - AIChatTabChatHeaderViewDelegate

extension MainViewController: AIChatTabChatHeaderViewDelegate {

    func aiChatTabChatHeaderDidTapSettings() {
        unifiedToggleInputCoordinator?.showCollapsed()
        currentTab?.submitToggleSidebarAction()
    }

    func aiChatTabChatHeaderDidTapNewChat() {
        currentTab?.submitStartChatAction()
    }

    func aiChatTabChatHeaderDidTapUpgrade() {
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow()
        )
    }
}
