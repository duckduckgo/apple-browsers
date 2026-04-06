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

private let utiLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.duckduckgo", category: "UTI")

// MARK: - Unified Toggle Input Setup

extension MainViewController {

    func setUpUnifiedToggleInputIfNeeded() {
        utiLog.debug("MainVC.setUpUnifiedToggleInputIfNeeded")
        guard unifiedToggleInputFeature.isAvailable else {
            utiLog.debug("MainVC.setUpUnifiedToggleInputIfNeeded ↩️ guard: feature not available")
            return
        }

        let coordinator = UnifiedToggleInputCoordinator(isToggleEnabled: aiChatSettings.isAIChatSearchInputUserSettingsEnabled)
        coordinator.delegate = self
        coordinator.updateVoiceSearchAvailability(voiceSearchHelper.isVoiceSearchEnabled)
        coordinator.updateAIVoiceChatAvailability(voiceShortcutFeature.isAvailable)
        coordinator.onAnimatedDismissToOmnibar = { [weak self] in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator else {
                utiLog.debug("MainVC.onAnimatedDismissToOmnibar ↩️ guard: self or coordinator is nil")
                return
            }
            utiLog.debug("MainVC.onAnimatedDismissToOmnibar → calling dismissUnifiedToggleInputToOmnibar")
            self.dismissUnifiedToggleInputToOmnibar(coordinator: coordinator)
        }
        self.unifiedToggleInputCoordinator = coordinator

        utiLog.debug("MainVC.setUpUnifiedToggleInputIfNeeded → installUnifiedToggleInputViewController")
        installUnifiedToggleInputViewController(coordinator.viewController)

        if let omniBarVC = viewCoordinator.omniBar as? DefaultOmniBarViewController {
            utiLog.debug("MainVC.setUpUnifiedToggleInputIfNeeded → setting omnibar activating delegate")
            omniBarVC.unifiedToggleInputOmnibarActivating = self
        }

        utiLog.debug("MainVC.setUpUnifiedToggleInputIfNeeded → setUpAIChatTabChatHeader")
        setUpAIChatTabChatHeader()
        utiLog.debug("MainVC.setUpUnifiedToggleInputIfNeeded → installUnifiedInputContentViewController")
        installUnifiedInputContentViewController()
        utiLog.debug("MainVC.setUpUnifiedToggleInputIfNeeded → installFloatingSubmitViewController")
        installFloatingSubmitViewController()

        subscribeToIntentPublisher(coordinator)
        subscribeToModeChanges(coordinator)
        subscribeToSystemEvents()
        subscribeToToggleSettings()
    }

    private func installUnifiedToggleInputViewController(_ inputVC: UnifiedToggleInputViewController) {
        utiLog.debug("MainVC.installUnifiedToggleInputViewController")
        addChild(inputVC)
        inputVC.view.translatesAutoresizingMaskIntoConstraints = false
        viewCoordinator.unifiedToggleInputContainer.addSubview(inputVC.view)
        NSLayoutConstraint.activate([
            inputVC.view.topAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.topAnchor),
            inputVC.view.leadingAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.leadingAnchor),
            inputVC.view.trailingAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.trailingAnchor),
        ])
        inputVC.didMove(toParent: self)
    }

    private func subscribeToIntentPublisher(_ coordinator: UnifiedToggleInputCoordinator) {
        utiLog.debug("MainVC.subscribeToIntentPublisher")
        coordinator.intentPublisher
            .sink { [weak self] intent in
                self?.handleUnifiedToggleInputIntent(intent)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    private func subscribeToModeChanges(_ coordinator: UnifiedToggleInputCoordinator) {
        utiLog.debug("MainVC.subscribeToModeChanges")
        coordinator.modeChangePublisher
            .sink { [weak self] mode in
                self?.handleModeChange(mode)
            }
            .store(in: &unifiedToggleInputCancellables)

        coordinator.attachmentsChangePublisher
            .sink { [weak self] in
                guard let self, let coordinator = unifiedToggleInputCoordinator else {
                    utiLog.debug("MainVC.attachmentsChange ↩️ guard: self or coordinator is nil")
                    return
                }
                if coordinator.isAITabExpanded || coordinator.isOmnibarSession {
                    utiLog.debug("MainVC.attachmentsChange → adjustUI (isAITabExpanded: \(coordinator.isAITabExpanded, privacy: .public), isOmnibarSession: \(coordinator.isOmnibarSession, privacy: .public))")
                    adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0.2, animationCurve: .curveEaseInOut)
                } else {
                    utiLog.debug("MainVC.attachmentsChange 🔀 no adjustUI needed")
                }
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    private func handleModeChange(_ mode: TextEntryMode) {
        utiLog.debug("MainVC.handleModeChange - mode: \(String(describing: mode), privacy: .public)")
        guard let coordinator = unifiedToggleInputCoordinator else {
            utiLog.debug("MainVC.handleModeChange ↩️ guard: coordinator is nil")
            return
        }

        if coordinator.isOmnibarSession {
            utiLog.debug("MainVC.handleModeChange 🔀 isOmnibarSession → handleOmnibarModeChange")
            handleOmnibarModeChange(mode, coordinator: coordinator)
        } else if coordinator.isAITabExpanded {
            utiLog.debug("MainVC.handleModeChange 🔀 isAITabExpanded → handleAITabModeChange")
            handleAITabModeChange(mode, coordinator: coordinator)
        } else if coordinator.isAITabState && mode == .aiChat {
            utiLog.debug("MainVC.handleModeChange 🔀 isAITabState && .aiChat → showExpanded")
            coordinator.showExpanded(inputMode: .aiChat)
        } else {
            utiLog.debug("MainVC.handleModeChange 🔀 no matching branch (isOmnibarSession: \(coordinator.isOmnibarSession, privacy: .public), isAITabExpanded: \(coordinator.isAITabExpanded, privacy: .public), isAITabState: \(coordinator.isAITabState, privacy: .public))")
        }
    }

    private func handleOmnibarModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        utiLog.debug("MainVC.handleOmnibarModeChange - mode: \(String(describing: mode), privacy: .public)")
        utiLog.debug("MainVC.handleOmnibarModeChange 📐 BEFORE: navBarContainer.frame=\(self.viewCoordinator.navigationBarContainer.frame.debugDescription, privacy: .public), utiContainer.frame=\(self.viewCoordinator.unifiedToggleInputContainer.frame.debugDescription, privacy: .public)")
        utiLog.debug("MainVC.handleOmnibarModeChange → updateUnifiedInputContentVisibility")
        updateUnifiedInputContentVisibility(for: coordinator)
        utiLog.debug("MainVC.handleOmnibarModeChange 📐 AFTER contentVisibility: navBarContainer.frame=\(self.viewCoordinator.navigationBarContainer.frame.debugDescription, privacy: .public)")
        utiLog.debug("MainVC.handleOmnibarModeChange → adjustUI")
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0.2, animationCurve: .curveEaseInOut)
        utiLog.debug("MainVC.handleOmnibarModeChange 📐 AFTER adjustUI: navBarContainer.frame=\(self.viewCoordinator.navigationBarContainer.frame.debugDescription, privacy: .public)")
        utiLog.debug("MainVC.handleOmnibarModeChange → syncContentInputMode(\(String(describing: mode), privacy: .public))")
        unifiedToggleInputCoordinator?.syncContentInputMode(mode)
        utiLog.debug("MainVC.handleOmnibarModeChange → updateFloatingSubmitVisibility")
        updateFloatingSubmitVisibility()
    }

    private func handleAITabModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        utiLog.debug("MainVC.handleAITabModeChange - mode: \(String(describing: mode), privacy: .public), clearing backgrounds")
        UIView.performWithoutAnimation {
            utiLog.debug("MainVC.handleAITabModeChange → updateUnifiedInputContentVisibility (no animation)")
            updateUnifiedInputContentVisibility(for: coordinator)
            utiLog.debug("MainVC.handleAITabModeChange 📐 applyUnifiedInputBackground(.clear)")
            applyUnifiedInputBackground(.clear)
            utiLog.debug("MainVC.handleAITabModeChange 📐 unifiedToggleInputContainer.backgroundColor = .clear")
            viewCoordinator.unifiedToggleInputContainer.backgroundColor = .clear
            utiLog.debug("MainVC.handleAITabModeChange 📐 coordinator.viewController.view.backgroundColor = .clear")
            coordinator.viewController.view.backgroundColor = .clear
            viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()
        }
        utiLog.debug("MainVC.handleAITabModeChange → adjustUI (duration: 0)")
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0, animationCurve: .curveEaseInOut)

        if keyboardShowing,
           !coordinator.viewController.isInputFirstResponder,
           currentTab?.aiChatContextualSheetCoordinator.isSheetPresented != true {
            utiLog.debug("MainVC.handleAITabModeChange 🔀 keyboard showing + input not first responder → scheduling activateInput")
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, coordinator.isAITabExpanded else {
                    utiLog.debug("MainVC.handleAITabModeChange.activateInput ↩️ guard: coordinator nil or not expanded")
                    return
                }
                utiLog.debug("MainVC.handleAITabModeChange → activateInput()")
                coordinator.activateInput()
            }
        } else {
            utiLog.debug("MainVC.handleAITabModeChange 🔀 skipping activateInput (keyboardShowing: \(self.keyboardShowing, privacy: .public), isInputFirstResponder: \(coordinator.viewController.isInputFirstResponder, privacy: .public))")
        }
    }

    func updateUnifiedToggleInputKeyboardVisibility(_ keyboardVisible: Bool) {
        utiLog.debug("MainVC.updateUnifiedToggleInputKeyboardVisibility - keyboardVisible: \(keyboardVisible, privacy: .public)")
        unifiedToggleInputCoordinator?.updateOmnibarInputVisibility(keyboardVisible)
    }

    private func subscribeToSystemEvents() {
        utiLog.debug("MainVC.subscribeToSystemEvents")
        NotificationCenter.default.publisher(for: .speechRecognizerDidChangeAvailability)
            .sink { [weak self] _ in
                guard let self else {
                    utiLog.debug("MainVC.speechRecognizerDidChange ↩️ guard: self is nil")
                    return
                }
                utiLog.debug("MainVC.speechRecognizerDidChange → updateVoiceSearchAvailability(\(self.voiceSearchHelper.isVoiceSearchEnabled, privacy: .public))")
                self.unifiedToggleInputCoordinator?.updateVoiceSearchAvailability(self.voiceSearchHelper.isVoiceSearchEnabled)
            }
            .store(in: &unifiedToggleInputCancellables)

        NotificationCenter.default.publisher(for: .entitlementsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    utiLog.debug("MainVC.entitlementsDidChange ↩️ guard: self is nil")
                    return
                }
                utiLog.debug("MainVC.entitlementsDidChange → fetchModels()")
                self.unifiedToggleInputCoordinator?.fetchModels()
                if self.currentTab?.isAITab == true {
                    utiLog.debug("MainVC.entitlementsDidChange 🔀 on AI tab → refreshAIChatTabChatHeaderSubscriptionState")
                    self.refreshAIChatTabChatHeaderSubscriptionState()
                }
            }
            .store(in: &unifiedToggleInputCancellables)

    }

    private func subscribeToToggleSettings() {
        utiLog.debug("MainVC.subscribeToToggleSettings")
        NotificationCenter.default.publisher(for: .aiChatSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else {
                    utiLog.debug("MainVC.aiChatSettingsChanged ↩️ guard: self or coordinator is nil")
                    return
                }
                let enabled = self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled
                utiLog.debug("MainVC.aiChatSettingsChanged → updateToggleEnabled(\(enabled, privacy: .public))")
                coordinator.updateToggleEnabled(enabled)
                coordinator.contentViewController.isSwipeEnabled = enabled
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        utiLog.debug("MainVC.refreshUnifiedToggleInput - isAITab: \(tab.isAITab, privacy: .public)")
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else {
            utiLog.debug("MainVC.refreshUnifiedToggleInput ↩️ guard: featureAvailable=\(self.unifiedToggleInputFeature.isAvailable, privacy: .public), coordinatorNil=\(self.unifiedToggleInputCoordinator == nil, privacy: .public)")
            return
        }

        if !tab.isAITab && !coordinator.isActive &&
            viewCoordinator.aiChatTabChatHeaderContainer.isHidden {
            utiLog.debug("MainVC.refreshUnifiedToggleInput 🔀 non-AI tab, inactive coordinator, header hidden → early unbind path")
            utiLog.debug("MainVC.refreshUnifiedToggleInput → coordinator.unbind()")
            coordinator.unbind()
            utiLog.debug("MainVC.refreshUnifiedToggleInput → moveAddressBarToPosition(\(String(describing: self.appSettings.currentAddressBarPosition), privacy: .public))")
            viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
            refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
            tab.updateWebViewBottomAnchor(for: viewCoordinator.toolbar.alpha)
            return
        }

        if tab.isAITab {
            utiLog.debug("MainVC.refreshUnifiedToggleInput 🔀 AI tab branch")
            utiLog.debug("MainVC.refreshUnifiedToggleInput 📐 statusBackground.backgroundColor = duckAIContextualSheetBackground")
            viewCoordinator.statusBackground.backgroundColor = UIColor(singleUseColor: .duckAIContextualSheetBackground)
            let hadSubmittedPrompt = coordinator.hasSubmittedPrompt
            utiLog.debug("MainVC.refreshUnifiedToggleInput - hadSubmittedPrompt: \(hadSubmittedPrompt, privacy: .public)")
            if let userScript = tab.userScripts?.aiChatUserScript {
                let hasExistingChat = tab.url?.duckAIChatID != nil
                utiLog.debug("MainVC.refreshUnifiedToggleInput → bindToTab(hasExistingChat: \(hasExistingChat, privacy: .public))")
                coordinator.bindToTab(userScript, hasExistingChat: hasExistingChat)
            } else {
                utiLog.debug("MainVC.refreshUnifiedToggleInput 🔀 no aiChatUserScript available, skipping bind")
            }
            if coordinator.isAITabState && viewCoordinator.isNavigationChromeHidden {
                utiLog.debug("MainVC.refreshUnifiedToggleInput ↩️ isAITabState && chrome hidden → early return")
                return
            }
            if viewCoordinator.navigationBarContainer.alpha < 0.99 ||
                viewCoordinator.toolbar.alpha < 0.99 ||
                viewCoordinator.tabBarContainer.alpha < 0.99 {
                utiLog.debug("MainVC.refreshUnifiedToggleInput → showBars() (navBar.alpha: \(self.viewCoordinator.navigationBarContainer.alpha, privacy: .public), toolbar.alpha: \(self.viewCoordinator.toolbar.alpha, privacy: .public), tabBar.alpha: \(self.viewCoordinator.tabBarContainer.alpha, privacy: .public))")
                showBars()
            }
            utiLog.debug("MainVC.refreshUnifiedToggleInput 📐 webView.scrollView.contentInset = .zero")
            tab.webView.scrollView.contentInset = .zero
            utiLog.debug("MainVC.refreshUnifiedToggleInput → deactivateToOmnibar()")
            coordinator.deactivateToOmnibar()
            utiLog.debug("MainVC.refreshUnifiedToggleInput → showAITabChrome()")
            viewCoordinator.showAITabChrome()
            if !coordinator.isAITabState {
                let hasExistingChat = tab.url?.duckAIChatID != nil
                utiLog.debug("MainVC.refreshUnifiedToggleInput 🔀 not isAITabState → showCollapsed (hasExistingChat: \(hasExistingChat, privacy: .public), hadSubmittedPrompt: \(hadSubmittedPrompt, privacy: .public))")
                coordinator.showCollapsed()
                if !hasExistingChat && !hadSubmittedPrompt {
                    utiLog.debug("MainVC.refreshUnifiedToggleInput → scheduling showExpanded(.aiChat)")
                    DispatchQueue.main.async { [weak coordinator] in
                        guard let coordinator, coordinator.isAITabState else {
                            utiLog.debug("MainVC.refreshUnifiedToggleInput.showExpanded ↩️ guard: coordinator nil or not AITabState")
                            return
                        }
                        utiLog.debug("MainVC.refreshUnifiedToggleInput → showExpanded(.aiChat)")
                        coordinator.showExpanded(inputMode: .aiChat)
                    }
                }
            } else {
                utiLog.debug("MainVC.refreshUnifiedToggleInput 🔀 already isAITabState, skipping showCollapsed")
            }
            utiLog.debug("MainVC.refreshUnifiedToggleInput → updateUnifiedInputContentVisibility")
            updateUnifiedInputContentVisibility(for: coordinator)
            utiLog.debug("MainVC.refreshUnifiedToggleInput → refreshAIChatTabChatHeaderSubscriptionState")
            refreshAIChatTabChatHeaderSubscriptionState()
            utiLog.debug("MainVC.refreshUnifiedToggleInput 📐 borderView.isTopVisible = false, isBottomVisible = false")
            tab.borderView.isTopVisible = false
            tab.borderView.isBottomVisible = false
        } else {
            utiLog.debug("MainVC.refreshUnifiedToggleInput 🔀 non-AI tab branch")
            utiLog.debug("MainVC.refreshUnifiedToggleInput → deactivateToOmnibar(), hide(), unbind()")
            coordinator.deactivateToOmnibar()
            coordinator.hide()
            coordinator.unbind()
            utiLog.debug("MainVC.refreshUnifiedToggleInput → hideAITabChrome()")
            viewCoordinator.hideAITabChrome()
            utiLog.debug("MainVC.refreshUnifiedToggleInput → moveAddressBarToPosition(\(String(describing: self.appSettings.currentAddressBarPosition), privacy: .public))")
            viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
            refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
            utiLog.debug("MainVC.refreshUnifiedToggleInput → refreshStatusBarBackgroundAfterAIChrome()")
            refreshStatusBarBackgroundAfterAIChrome()
            tab.borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
            utiLog.debug("MainVC.refreshUnifiedToggleInput 📐 borderView.isBottomVisible = true")
            tab.borderView.isBottomVisible = true
        }

        tab.updateWebViewBottomAnchor(for: viewCoordinator.toolbar.alpha)
    }

    private func setUpAIChatTabChatHeader() {
        utiLog.debug("MainVC.setUpAIChatTabChatHeader")
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
        utiLog.debug("MainVC.refreshAIChatTabChatHeaderSubscriptionState")
        Task { @MainActor [weak self] in
            let isActive = (try? await AppDependencyProvider.shared.subscriptionManager.isFeatureEnabled(.paidAIChat)) ?? false
            self?.aiChatTabChatHeaderView?.configure(isSubscriptionActive: isActive)
        }
    }

    private func updateUnifiedInputContentVisibility(for coordinator: UnifiedToggleInputCoordinator) {
        utiLog.debug("MainVC.updateUnifiedInputContentVisibility - isAITabState: \(coordinator.isAITabState, privacy: .public)")
        let isOnAITab = currentTab?.isAITab == true
        let renderState = coordinator.computeRenderState()
        utiLog.debug("MainVC.updateUnifiedInputContentVisibility - isOnAITab: \(isOnAITab, privacy: .public), renderState.isContentVisible: \(renderState.isContentVisible, privacy: .public)")
        if coordinator.isAITabState {
            utiLog.debug("MainVC.updateUnifiedInputContentVisibility 📐 forceBottomBarLayout = true")
            coordinator.contentViewController.forceBottomBarLayout = true
        } else {
            utiLog.debug("MainVC.updateUnifiedInputContentVisibility 📐 forceBottomBarLayout = false")
            coordinator.contentViewController.forceBottomBarLayout = false
        }

        utiLog.debug("MainVC.updateUnifiedInputContentVisibility → applyTopChromeState")
        applyTopChromeState(renderState: renderState, isOnAITab: isOnAITab, coordinator: coordinator)
    }

    private func applyTopChromeState(renderState: UTIRenderState, isOnAITab: Bool, coordinator: UnifiedToggleInputCoordinator) {
        utiLog.debug("MainVC.applyTopChromeState - isOnAITab: \(isOnAITab, privacy: .public), isContentVisible: \(renderState.isContentVisible, privacy: .public)")
        let targetStatusBackgroundColor: UIColor? = {
            guard isOnAITab, viewCoordinator.isNavigationChromeHidden else {
                utiLog.debug("MainVC.applyTopChromeState 🔀 statusBg: nil (not AI tab or chrome visible)")
                return nil
            }
            if renderState.isContentVisible {
                utiLog.debug("MainVC.applyTopChromeState 🔀 statusBg: panel (content visible)")
                return UIColor(designSystemColor: .panel)
            }
            utiLog.debug("MainVC.applyTopChromeState 🔀 statusBg: duckAIContextualSheetBackground")
            return UIColor(singleUseColor: .duckAIContextualSheetBackground)
        }()

        if let targetStatusBackgroundColor {
            utiLog.debug("MainVC.applyTopChromeState 📐 statusBackground.backgroundColor = \(targetStatusBackgroundColor.debugDescription, privacy: .public)")
            viewCoordinator.statusBackground.backgroundColor = targetStatusBackgroundColor
        }

        if coordinator.isAITabState {
            utiLog.debug("MainVC.applyTopChromeState → applyDismissButtonVisibility()")
            coordinator.applyDismissButtonVisibility()
        }

        utiLog.debug("MainVC.applyTopChromeState → updateUnifiedToggleInputColors")
        viewCoordinator.updateUnifiedToggleInputColors(
            inputView: coordinator.viewController.view
        )

        if renderState.isContentVisible {
            utiLog.debug("MainVC.applyTopChromeState 🔀 content visible → syncContentInputMode, pushContentInsets, showUnifiedInputContent")
            coordinator.syncContentInputMode(renderState.contentInputMode, animated: false)
            coordinator.pushContentInsets()
            viewCoordinator.showUnifiedInputContent()
        } else {
            utiLog.debug("MainVC.applyTopChromeState 🔀 content not visible → hideUnifiedInputContent")
            viewCoordinator.hideUnifiedInputContent()
        }

        if isOnAITab {
            if renderState.isContentVisible {
                utiLog.debug("MainVC.applyTopChromeState 📐 hideAIChatTabChatHeader (content visible)")
                viewCoordinator.hideAIChatTabChatHeader()
            } else {
                utiLog.debug("MainVC.applyTopChromeState 📐 showAIChatTabChatHeader (content not visible)")
                viewCoordinator.showAIChatTabChatHeader()
            }
            if viewIfLoaded?.window != nil {
                utiLog.debug("MainVC.applyTopChromeState → layoutIfNeeded()")
                view.layoutIfNeeded()
            }
        }
    }

    private func installUnifiedInputContentViewController() {
        utiLog.debug("MainVC.installUnifiedInputContentViewController")
        guard let coordinator = unifiedToggleInputCoordinator,
              let container = viewCoordinator.unifiedInputContentContainer else {
            utiLog.debug("MainVC.installUnifiedInputContentViewController ↩️ guard: coordinator or container is nil")
            return
        }

        let contentVC = coordinator.contentViewController
        contentVC.suggestionTrayDependencies = suggestionTrayDependencies
        contentVC.delegate = self
        contentVC.onDismissRequested = { [weak self] in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator else {
                utiLog.debug("MainVC.onDismissRequested ↩️ guard: self or coordinator is nil")
                return
            }
            if coordinator.isOmnibarSession {
                utiLog.debug("MainVC.onDismissRequested 🔀 isOmnibarSession → dismissUnifiedToggleInputToOmnibar")
                self.dismissUnifiedToggleInputToOmnibar(coordinator: coordinator)
                // Restore the tab's committed mode — the user toggled but didn't submit.
                if let tabMode = self.tabManager.currentTabsModel.currentTab?.preferredTextEntryMode {
                    utiLog.debug("MainVC.onDismissRequested → updateInputMode(\(String(describing: tabMode), privacy: .public))")
                    coordinator.updateInputMode(tabMode, animated: false)
                }
            } else if coordinator.isAITabExpanded {
                utiLog.debug("MainVC.onDismissRequested 🔀 isAITabExpanded → showCollapsed")
                coordinator.showCollapsed()
            } else {
                utiLog.debug("MainVC.onDismissRequested 🔀 no action (isOmnibarSession: \(coordinator.isOmnibarSession, privacy: .public), isAITabExpanded: \(coordinator.isAITabExpanded, privacy: .public))")
            }
        }
        contentVC.onSwipeDownRequested = { [weak self] in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator else {
                utiLog.debug("MainVC.onSwipeDownRequested ↩️ guard: self or coordinator is nil")
                return
            }
            utiLog.debug("MainVC.onSwipeDownRequested → dismissOmnibarKeyboard()")
            coordinator.dismissOmnibarKeyboard()
        }
        contentVC.isSwipeEnabled = coordinator.isToggleEnabled

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

    private func installFloatingSubmitViewController() {
        utiLog.debug("MainVC.installFloatingSubmitViewController")
        guard let coordinator = unifiedToggleInputCoordinator else {
            utiLog.debug("MainVC.installFloatingSubmitViewController ↩️ guard: coordinator is nil")
            return
        }

        let floatingVC = coordinator.floatingSubmitViewController
        floatingVC.delegate = self

        addChild(floatingVC)
        floatingVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingVC.view)
        NSLayoutConstraint.activate([
            floatingVC.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            floatingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        floatingVC.didMove(toParent: self)
        floatingVC.subscribe(to: coordinator.textChangePublisher)
        floatingVC.view.isHidden = true
    }

    private func updateFloatingSubmitVisibility() {
        utiLog.debug("MainVC.updateFloatingSubmitVisibility")
        guard let coordinator = unifiedToggleInputCoordinator else {
            utiLog.debug("MainVC.updateFloatingSubmitVisibility ↩️ guard: coordinator is nil")
            return
        }
        let renderState = coordinator.computeRenderState()
        utiLog.debug("MainVC.updateFloatingSubmitVisibility 📐 floatingSubmit.isHidden = \(!renderState.isFloatingSubmitVisible, privacy: .public)")
        coordinator.floatingSubmitViewController.view.isHidden = !renderState.isFloatingSubmitVisible
    }

    private func handleUnifiedToggleInputIntent(_ intent: UnifiedToggleInputIntent) {
        utiLog.debug("MainVC.handleUnifiedToggleInputIntent - intent: \(String(describing: intent), privacy: .public)")
        switch intent {
        case .showCollapsed:
            utiLog.debug("MainVC.handleIntent 🔀 case .showCollapsed")
            utiLog.debug("MainVC.handleIntent 📐 applyUnifiedInputBackground(nil, forAITabOnly: true)")
            applyUnifiedInputBackground(nil, forAITabOnly: true)
            if unifiedToggleInputCoordinator?.isAITabState == true {
                utiLog.debug("MainVC.handleIntent 📐 stopContentContainerBehindInput (isAITabState)")
                viewCoordinator.stopContentContainerBehindInput()
            }
            utiLog.debug("MainVC.handleIntent 📐 showUnifiedToggleInput()")
            viewCoordinator.showUnifiedToggleInput()
            utiLog.debug("MainVC.handleIntent 📐 suggestionTrayContainer.isHidden = true")
            viewCoordinator.suggestionTrayContainer.isHidden = true
            if let coordinator = unifiedToggleInputCoordinator {
                utiLog.debug("MainVC.handleIntent → updateUnifiedInputContentVisibility")
                updateUnifiedInputContentVisibility(for: coordinator)
            } else {
                utiLog.debug("MainVC.handleIntent 🔀 no coordinator → hideUnifiedInputContent")
                viewCoordinator.hideUnifiedInputContent()
            }
        case .showExpanded:
            utiLog.debug("MainVC.handleIntent 🔀 case .showExpanded")
            utiLog.debug("MainVC.handleIntent 📐 showUnifiedToggleInput()")
            viewCoordinator.showUnifiedToggleInput()
            if let coordinator = unifiedToggleInputCoordinator {
                if coordinator.isAITabState {
                    utiLog.debug("MainVC.handleIntent 🔀 isAITabState → clearing backgrounds, extending content behind input")
                    utiLog.debug("MainVC.handleIntent 📐 applyUnifiedInputBackground(.clear)")
                    applyUnifiedInputBackground(.clear)
                    utiLog.debug("MainVC.handleIntent 📐 unifiedToggleInputContainer.backgroundColor = .clear")
                    viewCoordinator.unifiedToggleInputContainer.backgroundColor = .clear
                    utiLog.debug("MainVC.handleIntent 📐 coordinator.viewController.view.backgroundColor = .clear")
                    coordinator.viewController.view.backgroundColor = .clear
                    utiLog.debug("MainVC.handleIntent 📐 extendContentContainerBehindInput()")
                    viewCoordinator.extendContentContainerBehindInput()
                }
                utiLog.debug("MainVC.handleIntent → updateUnifiedInputContentVisibility")
                updateUnifiedInputContentVisibility(for: coordinator)
            }
            utiLog.debug("MainVC.handleIntent → adjustUI (duration: 0)")
            adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0, animationCurve: .curveEaseInOut)
        case .showOmnibarEditing(let height, let pendingHeight):
            utiLog.debug("MainVC.handleIntent 🔀 case .showOmnibarEditing(height: \(height, privacy: .public), pendingHeight: \(String(describing: pendingHeight), privacy: .public))")
            utiLog.debug("MainVC.handleIntent 📐 showUnifiedToggleInputOmnibar(expandedHeight: \(height, privacy: .public))")
            viewCoordinator.showUnifiedToggleInputOmnibar(expandedHeight: height)
            utiLog.debug("MainVC.handleIntent 📐 suggestionTrayContainer.isHidden = true")
            viewCoordinator.suggestionTrayContainer.isHidden = true
            let isTopPosition = unifiedToggleInputCoordinator?.cardPosition == .top
            utiLog.debug("MainVC.handleIntent - isTopPosition: \(isTopPosition == true, privacy: .public)")
            if let coordinator = unifiedToggleInputCoordinator {
                utiLog.debug("MainVC.handleIntent → updateUnifiedInputContentVisibility")
                updateUnifiedInputContentVisibility(for: coordinator)
                if isTopPosition && coordinator.isToggleEnabled {
                    utiLog.debug("MainVC.handleIntent 🔀 topPosition + toggleEnabled → animateOmnibarExpansion")
                    let targetHeight = pendingHeight
                    utiLog.debug("MainVC.handleIntent 📐 unifiedInputContentContainer.alpha = 0")
                    self.viewCoordinator.unifiedInputContentContainer.alpha = 0
                    coordinator.animateOmnibarExpansion { [weak self] in
                        guard let self else {
                            utiLog.debug("MainVC.handleIntent.animateOmnibarExpansion ↩️ guard: self is nil")
                            return
                        }
                        if let targetHeight {
                            utiLog.debug("MainVC.handleIntent 📐 navigationBarContainerHeight = \(targetHeight, privacy: .public)")
                            self.viewCoordinator.constraints.navigationBarContainerHeight.constant = targetHeight
                            self.viewCoordinator.superview.layoutIfNeeded()
                        }
                        utiLog.debug("MainVC.handleIntent → pushContentInsets()")
                        self.unifiedToggleInputCoordinator?.pushContentInsets()
                        utiLog.debug("MainVC.handleIntent 📐 unifiedInputContentContainer.alpha = 1")
                        self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                    }
                } else if isTopPosition {
                    utiLog.debug("MainVC.handleIntent 🔀 topPosition + toggle disabled → fade in content")
                    utiLog.debug("MainVC.handleIntent 📐 unifiedInputContentContainer.alpha = 0")
                    self.viewCoordinator.unifiedInputContentContainer.alpha = 0
                    UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) { [weak self] in
                        utiLog.debug("MainVC.handleIntent 📐 unifiedInputContentContainer.alpha = 1 (animated)")
                        self?.viewCoordinator.unifiedInputContentContainer.alpha = 1
                    }
                } else {
                    utiLog.debug("MainVC.handleIntent 🔀 bottom position → no expansion animation")
                }
            }
        case .showOmnibarInactive:
            utiLog.debug("MainVC.handleIntent 🔀 case .showOmnibarInactive")
            utiLog.debug("MainVC.handleIntent → restoreNavBarToToolbarForOmnibarInactive()")
            viewCoordinator.restoreNavBarToToolbarForOmnibarInactive()
            utiLog.debug("MainVC.handleIntent → recomputeOmnibarEditingHeightIfNeeded()")
            recomputeOmnibarEditingHeightIfNeeded()
        case .showOmnibarActive:
            utiLog.debug("MainVC.handleIntent 🔀 case .showOmnibarActive")
            utiLog.debug("MainVC.handleIntent → restoreNavBarToToolbarForOmnibarInactive()")
            viewCoordinator.restoreNavBarToToolbarForOmnibarInactive()
            utiLog.debug("MainVC.handleIntent → recomputeOmnibarEditingHeightIfNeeded()")
            recomputeOmnibarEditingHeightIfNeeded()
        case .hideOmnibarEditing:
            utiLog.debug("MainVC.handleIntent 🔀 case .hideOmnibarEditing")
            utiLog.debug("MainVC.handleIntent 📐 hideUnifiedToggleInputOmnibar()")
            viewCoordinator.hideUnifiedToggleInputOmnibar()
            utiLog.debug("MainVC.handleIntent 📐 hideUnifiedInputContent()")
            viewCoordinator.hideUnifiedInputContent()
            utiLog.debug("MainVC.handleIntent → setContentInset(top: 0, bottom: 0)")
            unifiedToggleInputCoordinator?.contentViewController.setContentInset(top: 0, bottom: 0)
            utiLog.debug("MainVC.handleIntent → hideSuggestionTray()")
            hideSuggestionTray()
            utiLog.debug("MainVC.handleIntent 📐 suggestionTrayContainer.backgroundColor = .clear, isHidden = false")
            viewCoordinator.suggestionTrayContainer.backgroundColor = .clear
            viewCoordinator.suggestionTrayContainer.isHidden = false
        case .hide:
            utiLog.debug("MainVC.handleIntent 🔀 case .hide")
            viewCoordinator.exitOmniBarUnifiedInputState()
            utiLog.debug("MainVC.handleIntent 📐 coordinator.viewController.view.backgroundColor = .clear")
            unifiedToggleInputCoordinator?.viewController.view.backgroundColor = .clear
            utiLog.debug("MainVC.handleIntent 📐 hideUnifiedToggleInput()")
            viewCoordinator.hideUnifiedToggleInput()
            utiLog.debug("MainVC.handleIntent 📐 hideUnifiedInputContent()")
            viewCoordinator.hideUnifiedInputContent()
            utiLog.debug("MainVC.handleIntent → setContentInset(top: 0, bottom: 0)")
            unifiedToggleInputCoordinator?.contentViewController.setContentInset(top: 0, bottom: 0)
            utiLog.debug("MainVC.handleIntent → hideSuggestionTray()")
            hideSuggestionTray()
            utiLog.debug("MainVC.handleIntent 📐 suggestionTrayContainer.isHidden = false")
            viewCoordinator.suggestionTrayContainer.isHidden = false
        }
        utiLog.debug("MainVC.handleIntent → updateFloatingSubmitVisibility()")
        updateFloatingSubmitVisibility()
    }

    private func applyUnifiedInputBackground(_ color: UIColor?, forAITabOnly: Bool = false) {
        utiLog.debug("MainVC.applyUnifiedInputBackground - color: \(String(describing: color), privacy: .public), forAITabOnly: \(forAITabOnly, privacy: .public)")
        utiLog.debug("MainVC.applyUnifiedInputBackground 📐 navigationBarContainer.backgroundColor = \(String(describing: color), privacy: .public)")
        viewCoordinator.navigationBarContainer.backgroundColor = color
        utiLog.debug("MainVC.applyUnifiedInputBackground 📐 unifiedInputContentContainer.backgroundColor = \(String(describing: color ?? .clear), privacy: .public)")
        viewCoordinator.unifiedInputContentContainer?.backgroundColor = color ?? .clear
        if !forAITabOnly || unifiedToggleInputCoordinator?.isAITabState == true {
            if let webView = currentTab?.webView {
                utiLog.debug("MainVC.applyUnifiedInputBackground 📐 webView backgrounds = \(String(describing: color), privacy: .public)")
                webView.backgroundColor = color
                webView.scrollView.backgroundColor = color
                webView.underPageBackgroundColor = color
            } else {
                utiLog.debug("MainVC.applyUnifiedInputBackground 🔀 no webView to apply background to")
            }
        } else {
            utiLog.debug("MainVC.applyUnifiedInputBackground 🔀 skipping webView backgrounds (forAITabOnly: \(forAITabOnly, privacy: .public), isAITabState: \(self.unifiedToggleInputCoordinator?.isAITabState == true, privacy: .public))")
        }
    }

    func recomputeOmnibarEditingHeightIfNeeded() {
        utiLog.debug("MainVC.recomputeOmnibarEditingHeightIfNeeded")
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.isOmnibarSession else {
            utiLog.debug("MainVC.recomputeOmnibarEditingHeightIfNeeded ↩️ guard: coordinator nil or not omnibar session")
            return
        }
        let height = coordinator.omnibarEditingHeight()
        utiLog.debug("MainVC.recomputeOmnibarEditingHeightIfNeeded 📐 navBarContainer.frame BEFORE=\(self.viewCoordinator.navigationBarContainer.frame.debugDescription, privacy: .public), newHeight=\(height, privacy: .public)")
        viewCoordinator.constraints.navigationBarContainerHeight.constant = height
        utiLog.debug("MainVC.recomputeOmnibarEditingHeightIfNeeded 📐 navBarContainer.frame AFTER=\(self.viewCoordinator.navigationBarContainer.frame.debugDescription, privacy: .public)")
        utiLog.debug("MainVC.recomputeOmnibarEditingHeightIfNeeded → pushContentInsets()")
        coordinator.pushContentInsets()
    }

    private func dismissUnifiedToggleInputToOmnibar(coordinator: UnifiedToggleInputCoordinator) {
        utiLog.debug("MainVC.dismissUnifiedToggleInputToOmnibar")
        utiLog.debug("MainVC.dismissUnifiedToggleInputToOmnibar 📐 navigationBarContainer.backgroundColor = nil")
        viewCoordinator.navigationBarContainer.backgroundColor = nil
        utiLog.debug("MainVC.dismissUnifiedToggleInputToOmnibar 📐 unifiedInputContentContainer.backgroundColor = .clear")
        viewCoordinator.unifiedInputContentContainer?.backgroundColor = .clear
        if coordinator.isAITabState, let webView = currentTab?.webView {
            utiLog.debug("MainVC.dismissUnifiedToggleInputToOmnibar 📐 clearing webView backgrounds (isAITabState)")
            webView.backgroundColor = nil
            webView.scrollView.backgroundColor = nil
            webView.underPageBackgroundColor = nil
        }
        let isTopPosition = coordinator.cardPosition == .top
        utiLog.debug("MainVC.dismissUnifiedToggleInputToOmnibar - isTopPosition: \(isTopPosition, privacy: .public), isToggleEnabled: \(coordinator.isToggleEnabled, privacy: .public)")
        if isTopPosition && coordinator.isToggleEnabled {
            utiLog.debug("MainVC.dismissUnifiedToggleInputToOmnibar 🔀 topPosition + toggleEnabled → animateToggleHide")
            coordinator.viewController.animateToggleHide(additionalAnimations: { [weak self] in
                guard let self else {
                    utiLog.debug("MainVC.dismissToOmnibar.animateToggleHide ↩️ guard: self is nil")
                    return
                }
                utiLog.debug("MainVC.dismissToOmnibar 📐 navigationBarContainerHeight = standardHeight, alpha = 0")
                self.viewCoordinator.constraints.navigationBarContainerHeight.constant = self.viewCoordinator.standardNavigationBarContainerHeight
                self.viewCoordinator.superview.layoutIfNeeded()
                self.viewCoordinator.unifiedInputContentContainer.alpha = 0
            }, completion: { [weak self] in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else {
                    utiLog.debug("MainVC.dismissToOmnibar.animateToggleHide.completion ↩️ guard: self or coordinator is nil")
                    return
                }
                utiLog.debug("MainVC.dismissToOmnibar 📐 unifiedInputContentContainer.isHidden = true, alpha = 1")
                self.viewCoordinator.unifiedInputContentContainer.isHidden = true
                self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                utiLog.debug("MainVC.dismissToOmnibar → deactivateToOmnibar(resetView: false)")
                coordinator.deactivateToOmnibar(resetView: false)
            })
        } else if isTopPosition {
            utiLog.debug("MainVC.dismissUnifiedToggleInputToOmnibar 🔀 topPosition + toggle disabled → fade out content")
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: { [weak self] in
                utiLog.debug("MainVC.dismissToOmnibar 📐 unifiedInputContentContainer.alpha = 0 (animated)")
                self?.viewCoordinator.unifiedInputContentContainer.alpha = 0
            }, completion: { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else {
                    utiLog.debug("MainVC.dismissToOmnibar.fadeOut.completion ↩️ guard: self or coordinator is nil")
                    return
                }
                utiLog.debug("MainVC.dismissToOmnibar 📐 unifiedInputContentContainer.isHidden = true, alpha = 1")
                self.viewCoordinator.unifiedInputContentContainer.isHidden = true
                self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                utiLog.debug("MainVC.dismissToOmnibar → deactivateToOmnibar(resetView: false)")
                coordinator.deactivateToOmnibar(resetView: false)
            })
        } else {
            utiLog.debug("MainVC.dismissUnifiedToggleInputToOmnibar 🔀 bottom position → deactivateToOmnibar()")
            coordinator.deactivateToOmnibar()
        }
    }

}

// MARK: - UnifiedToggleInputOmnibarActivating

extension MainViewController: UnifiedToggleInputOmnibarActivating {

    func activateFromOmnibarIfNeeded(currentText: String?) -> UnifiedToggleInputActivationDecision {
        utiLog.debug("MainVC.activateFromOmnibarIfNeeded - currentText: \(String(describing: currentText), privacy: .public)")
        guard let coordinator = unifiedToggleInputCoordinator,
              currentTab?.isAITab != true else {
            utiLog.debug("MainVC.activateFromOmnibarIfNeeded ↩️ guard: coordinator nil or on AI tab → .allowDefault")
            return .allowDefault
        }
        let position: UnifiedToggleInputCardPosition = appSettings.currentAddressBarPosition == .bottom ? .bottom : .top
        let inputMode = tabManager.currentTabsModel.currentTab?.preferredTextEntryMode ?? .search
        utiLog.debug("MainVC.activateFromOmnibarIfNeeded → activateFromOmnibar(position: \(String(describing: position), privacy: .public), inputMode: \(String(describing: inputMode), privacy: .public))")
        coordinator.activateFromOmnibar(prefilledText: currentText, inputMode: inputMode, cardPosition: position)
        viewCoordinator.enterOmniBarUnifiedInputState()
        utiLog.debug("MainVC.activateFromOmnibarIfNeeded → returning .intercept")
        return .intercept
    }
}

// MARK: - UnifiedToggleInputDelegate

extension MainViewController: UnifiedToggleInputDelegate {

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, images: [AIChatNativePrompt.NativePromptImage]?) {
        utiLog.debug("MainVC.unifiedToggleInputDidSubmitPrompt - modelId: \(String(describing: modelId), privacy: .public)")
        utiLog.debug("MainVC.unifiedToggleInputDidSubmitPrompt → commitUnifiedToggleStateToCurrentTab()")
        commitUnifiedToggleStateToCurrentTab()
        utiLog.debug("MainVC.unifiedToggleInputDidSubmitPrompt → openAIChat(autoSend: true)")
        openAIChat(prompt, autoSend: true, modelId: modelId, images: images)
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {
        utiLog.debug("MainVC.unifiedToggleInputDidSubmitQuery")
        utiLog.debug("MainVC.unifiedToggleInputDidSubmitQuery → commitUnifiedToggleStateToCurrentTab()")
        commitUnifiedToggleStateToCurrentTab()
        utiLog.debug("MainVC.unifiedToggleInputDidSubmitQuery → handleUnifiedToggleInputSearchSubmission()")
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedToggleInputDidRequestVoiceSearch() {
        utiLog.debug("MainVC.unifiedToggleInputDidRequestVoiceSearch")
        let mode = unifiedToggleInputCoordinator?.inputMode ?? .search
        if mode == .aiChat && voiceShortcutFeature.isAvailable {
            utiLog.debug("MainVC.unifiedToggleInputDidRequestVoiceSearch 🔀 aiChat + voiceShortcut → onDuckAIVoiceModeRequested()")
            onDuckAIVoiceModeRequested()
        } else {
            utiLog.debug("MainVC.unifiedToggleInputDidRequestVoiceSearch 🔀 mode: \(String(describing: mode), privacy: .public) → handleVoiceSearchOpenRequest")
            handleVoiceSearchOpenRequest(preferredTarget: mode == .aiChat ? .AIChat : .SERP)
        }
    }

    func unifiedToggleInputDidChangeHeight() {
        utiLog.debug("MainVC.unifiedToggleInputDidChangeHeight - isOmnibarSession: \(self.unifiedToggleInputCoordinator?.isOmnibarSession == true, privacy: .public), navBarContainer.frame=\(self.viewCoordinator.navigationBarContainer.frame.debugDescription, privacy: .public)")
        if unifiedToggleInputCoordinator?.isOmnibarSession == true {
            utiLog.debug("MainVC.unifiedToggleInputDidChangeHeight 🔀 isOmnibarSession → recomputeOmnibarEditingHeightIfNeeded()")
            recomputeOmnibarEditingHeightIfNeeded()
        } else {
            utiLog.debug("MainVC.unifiedToggleInputDidChangeHeight 🔀 not omnibar → pushContentInsets()")
            unifiedToggleInputCoordinator?.pushContentInsets()
        }
    }
}

// MARK: - UnifiedInputContentContainerViewControllerDelegate

extension MainViewController: UnifiedInputContentContainerViewControllerDelegate {

    func unifiedInputEditingStateDidSubmitQuery(_ query: String) {
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitQuery")
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitQuery → commitUnifiedToggleStateToCurrentTab()")
        commitUnifiedToggleStateToCurrentTab()
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitQuery → clearText()")
        unifiedToggleInputCoordinator?.clearText()
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitQuery → handleExternalSubmission(.query)")
        unifiedToggleInputCoordinator?.handleExternalSubmission(.query)
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitQuery → handleUnifiedToggleInputSearchSubmission()")
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?) {
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitPrompt")
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitPrompt → commitUnifiedToggleStateToCurrentTab()")
        commitUnifiedToggleStateToCurrentTab()
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitPrompt → clearText()")
        unifiedToggleInputCoordinator?.clearText()
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitPrompt → handleExternalSubmission(.prompt)")
        unifiedToggleInputCoordinator?.handleExternalSubmission(.prompt)
        utiLog.debug("MainVC.unifiedInputEditingStateDidSubmitPrompt → openAIChat(autoSend: true)")
        openAIChat(query, autoSend: true, tools: tools)
    }

    func unifiedInputEditingStateDidSelectFavorite(_ favorite: BookmarkEntity) {
        utiLog.debug("MainVC.unifiedInputEditingStateDidSelectFavorite")
        utiLog.debug("MainVC.unifiedInputEditingStateDidSelectFavorite → handleFavoriteSelected()")
        handleFavoriteSelected(favorite)
    }

    func unifiedInputEditingStateDidEditFavorite(_ favorite: BookmarkEntity) {
        utiLog.debug("MainVC.unifiedInputEditingStateDidEditFavorite")
        utiLog.debug("MainVC.unifiedInputEditingStateDidEditFavorite → segueToEditBookmark()")
        segueToEditBookmark(favorite)
    }

    func unifiedInputEditingStateDidSelectSuggestion(_ suggestion: Suggestion) {
        utiLog.debug("MainVC.unifiedInputEditingStateDidSelectSuggestion")
        utiLog.debug("MainVC.unifiedInputEditingStateDidSelectSuggestion → handleSuggestionSelected()")
        handleSuggestionSelected(suggestion)
    }

    func unifiedInputEditingStateDidSelectChatHistory(url: URL) {
        utiLog.debug("MainVC.unifiedInputEditingStateDidSelectChatHistory - url: \(url.absoluteString, privacy: .public)")
        utiLog.debug("MainVC.unifiedInputEditingStateDidSelectChatHistory → onChatHistorySelected()")
        onChatHistorySelected(url: url)
    }

    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: Tab) {
        utiLog.debug("MainVC.unifiedInputEditingStateDidRequestSwitchTab")
        utiLog.debug("MainVC.unifiedInputEditingStateDidRequestSwitchTab → onSwitchToTab()")
        onSwitchToTab(tab)
    }

    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode) {
        utiLog.debug("MainVC.unifiedInputEditingStateDidChangeMode - mode: \(String(describing: mode), privacy: .public)")
        utiLog.debug("MainVC.unifiedInputEditingStateDidChangeMode → syncInputModeFromExternalSource(\(String(describing: mode), privacy: .public))")
        unifiedToggleInputCoordinator?.syncInputModeFromExternalSource(mode)
    }
}

private extension MainViewController {
    func handleUnifiedToggleInputSearchSubmission(_ query: String) {
        utiLog.debug("MainVC.handleUnifiedToggleInputSearchSubmission - isAITab: \(self.currentTab?.isAITab == true, privacy: .public)")
        if currentTab?.isAITab == true {
            utiLog.debug("MainVC.handleUnifiedToggleInputSearchSubmission 🔀 on AI tab → hideAITabChrome, refreshStatusBar")
            viewCoordinator.hideAITabChrome()
            refreshStatusBarBackgroundAfterAIChrome()
        }
        utiLog.debug("MainVC.handleUnifiedToggleInputSearchSubmission → loadQuery()")
        loadQuery(query)
    }

    func commitUnifiedToggleStateToCurrentTab() {
        utiLog.debug("MainVC.commitUnifiedToggleStateToCurrentTab - mode: \(String(describing: self.unifiedToggleInputCoordinator?.inputMode), privacy: .public)")
        guard let mode = unifiedToggleInputCoordinator?.inputMode else {
            utiLog.debug("MainVC.commitUnifiedToggleStateToCurrentTab ↩️ guard: inputMode is nil")
            return
        }
        utiLog.debug("MainVC.commitUnifiedToggleStateToCurrentTab → commitToggleMode(\(String(describing: mode), privacy: .public))")
        commitToggleMode(mode)
    }
}

// MARK: - AIChatTabChatHeaderViewDelegate

extension MainViewController: AIChatTabChatHeaderViewDelegate {

    func aiChatTabChatHeaderDidTapSettings() {
        utiLog.debug("MainVC.aiChatTabChatHeaderDidTapSettings")
        utiLog.debug("MainVC.aiChatTabChatHeaderDidTapSettings → showCollapsed()")
        unifiedToggleInputCoordinator?.showCollapsed()
        utiLog.debug("MainVC.aiChatTabChatHeaderDidTapSettings → submitToggleSidebarAction()")
        currentTab?.submitToggleSidebarAction()
    }

    func aiChatTabChatHeaderDidTapNewChat() {
        utiLog.debug("MainVC.aiChatTabChatHeaderDidTapNewChat")
        utiLog.debug("MainVC.aiChatTabChatHeaderDidTapNewChat → startNewChat()")
        unifiedToggleInputCoordinator?.startNewChat()
        utiLog.debug("MainVC.aiChatTabChatHeaderDidTapNewChat → showExpanded(.aiChat)")
        unifiedToggleInputCoordinator?.showExpanded(inputMode: .aiChat)
        utiLog.debug("MainVC.aiChatTabChatHeaderDidTapNewChat → submitStartChatAction()")
        currentTab?.submitStartChatAction()
    }

    func aiChatTabChatHeaderDidTapUpgrade() {
        utiLog.debug("MainVC.aiChatTabChatHeaderDidTapUpgrade")
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow()
        )
    }
}

// MARK: - UnifiedToggleInputFloatingSubmitDelegate

extension MainViewController: UnifiedToggleInputFloatingSubmitDelegate {

    func floatingSubmitDidTapSubmit() {
        utiLog.debug("MainVC.floatingSubmitDidTapSubmit")
        guard let coordinator = unifiedToggleInputCoordinator else {
            utiLog.debug("MainVC.floatingSubmitDidTapSubmit ↩️ guard: coordinator is nil")
            return
        }
        let text = coordinator.currentText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            utiLog.debug("MainVC.floatingSubmitDidTapSubmit ↩️ guard: text is empty")
            return
        }
        utiLog.debug("MainVC.floatingSubmitDidTapSubmit → switchBarHandler.submitText()")
        coordinator.switchBarHandler.submitText(text)
    }

    func floatingSubmitDidTapVoice() {
        utiLog.debug("MainVC.floatingSubmitDidTapVoice")
        utiLog.debug("MainVC.floatingSubmitDidTapVoice → onDuckAIVoiceModeRequested()")
        onDuckAIVoiceModeRequested()
    }
}
