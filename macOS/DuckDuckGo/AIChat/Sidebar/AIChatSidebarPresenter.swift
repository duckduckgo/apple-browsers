//
//  AIChatSidebarPresenter.swift
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
import AppKit
import PrivacyConfig
import Combine
import PixelKit

/// Represents an event of hiding or showing an AI Chat tab sidebar.
///
/// - Note: This only refers to the logic of tab having sidebar shown or hidden,
///         not to sidebars getting on and off the screen due to switching browser tabs.
struct AIChatSidebarPresenceChange: Equatable {
    let tabID: TabIdentifier
    let isShown: Bool
}

/// Manages the presentation of an AI Chat sidebar in the browser.
///
/// Handles visibility, state management, and feature flag coordination for the AI Chat sidebar.
@MainActor
protocol AIChatSidebarPresenting {

    /// Toggles the AI Chat sidebar visibility on a current tab, using appropriate animation.
    func toggleSidebar()

    /// Collapses the AI Chat sidebar on the current tab with or without animation.
    func collapseSidebar(withAnimation: Bool)

    /// Returns whether the AI Chat sidebar is open on a tab specified by `tabID`.
    func isSidebarOpen(for tabID: TabIdentifier) -> Bool

    /// Returns whether the AI Chat sidebar is currently open for the active tab.
    func isSidebarOpenForCurrentTab() -> Bool

    /// Returns the date when the AI Chat sidebar was last hidden for a tab specified by `tabID`.
    func sidebarHiddenAt(for tabID: TabIdentifier) -> Date?

    /// Returns the date when the AI Chat sidebar was last hidden for the active tab.
    func sidebarHiddenAtForCurrentTab() -> Date?

    /// Emits events whenever sidebar is shown or hidden for a tab.
    var sidebarPresenceWillChangePublisher: AnyPublisher<AIChatSidebarPresenceChange, Never> { get }

    /// Consumes `prompt` and presents it in the sidebar. Appends to existing conversation if that was present.
    func presentSidebar(for prompt: AIChatNativePrompt)
}

final class AIChatSidebarPresenter: AIChatSidebarPresenting {

    let sidebarPresenceWillChangePublisher: AnyPublisher<AIChatSidebarPresenceChange, Never>

    private let sidebarHost: AIChatSidebarHosting
    private let sidebarProvider: AIChatSidebarProviding
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatTabOpener: AIChatTabOpening
    private let windowControllersManager: WindowControllersManagerProtocol
    private let pixelFiring: PixelFiring?
    private let sidebarPresenceWillChangeSubject = PassthroughSubject<AIChatSidebarPresenceChange, Never>()

    private var isAnimatingSidebarTransition: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init(
        sidebarHost: AIChatSidebarHosting,
        sidebarProvider: AIChatSidebarProviding,
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
        aiChatTabOpener: AIChatTabOpening,
        windowControllersManager: WindowControllersManagerProtocol,
        pixelFiring: PixelFiring?
    ) {
        self.sidebarHost = sidebarHost
        self.sidebarProvider = sidebarProvider
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatTabOpener = aiChatTabOpener
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring

        sidebarPresenceWillChangePublisher = sidebarPresenceWillChangeSubject.eraseToAnyPublisher()
        self.sidebarHost.aiChatSidebarHostingDelegate = self

        NotificationCenter.default.publisher(for: .aiChatNativeHandoffData)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard sidebarHost.isInKeyWindow,
                      let payload = notification.object as? AIChatPayload
                else { return }

                self?.handleAIChatHandoff(with: payload)
            }
            .store(in: &cancellables)
    }

    func toggleSidebar() {
        guard !isAnimatingSidebarTransition,
              let currentTabID = sidebarHost.currentTabID else { return }

        let willShowSidebar = !sidebarProvider.isShowingSidebar(for: currentTabID)

        updateSidebarConstraints(for: currentTabID, isShowingSidebar: willShowSidebar, withAnimation: true)
    }

    func collapseSidebar(withAnimation: Bool) {
        guard let currentTabID = sidebarHost.currentTabID else { return }
        updateSidebarConstraints(for: currentTabID, isShowingSidebar: false, withAnimation: withAnimation)
    }

    func isSidebarOpen(for tabID: TabIdentifier) -> Bool {
        return sidebarProvider.isShowingSidebar(for: tabID)
    }

    func isSidebarOpenForCurrentTab() -> Bool {
        guard let currentTabID = sidebarHost.currentTabID else { return false }
        return isSidebarOpen(for: currentTabID)
    }

    func sidebarHiddenAt(for tabID: TabIdentifier) -> Date? {
        sidebarProvider.sidebarsByTab[tabID]?.hiddenAt
    }

    func sidebarHiddenAtForCurrentTab() -> Date? {
        guard let currentTabID = sidebarHost.currentTabID else { return nil }
        return sidebarHiddenAt(for: currentTabID)
    }

    private func updateSidebarConstraints(for tabID: TabIdentifier, isShowingSidebar: Bool, withAnimation: Bool) {
        isAnimatingSidebarTransition = true
        sidebarPresenceWillChangeSubject.send(.init(tabID: tabID, isShown: isShowingSidebar))

        if isShowingSidebar {
            // Clear sidebar if session has expired (hidden for more than 60 minutes)
            sidebarProvider.clearSidebarIfSessionExpired(for: tabID)

            let sidebarViewController: AIChatSidebarViewController = {
                if let existingViewController = sidebarProvider.getSidebarViewController(for: tabID) {
                    return existingViewController
                } else {
                    return sidebarProvider.makeSidebarViewController(for: tabID, burnerMode: sidebarHost.burnerMode)
                }
            }()

            sidebarViewController.delegate = self
            sidebarHost.embedSidebarViewController(sidebarViewController)

            // Mark sidebar as revealed when it's being shown
            sidebarProvider.sidebarsByTab[tabID]?.setRevealed()
        } else {
            // Mark sidebar as hidden when it's being hidden
            sidebarProvider.sidebarsByTab[tabID]?.setHidden()
        }

        let newConstraintValue = isShowingSidebar ? -self.sidebarProvider.sidebarWidth : 0.0

        sidebarHost.sidebarContainerWidthConstraint?.constant = sidebarProvider.sidebarWidth

        if withAnimation {
            NSAnimationContext.runAnimationGroup { [weak self] context in
                guard let self else { return }

                context.duration = 0.25
                context.allowsImplicitAnimation = true
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sidebarHost.sidebarContainerLeadingConstraint?.animator().constant = newConstraintValue
            } completionHandler: { [weak self, tabID = sidebarHost.currentTabID] in
                guard let self else { return }
                self.isAnimatingSidebarTransition = false

                guard let tabID, !isShowingSidebar else { return }
                self.sidebarProvider.handleSidebarDidClose(for: tabID)
            }
        } else {
            sidebarHost.sidebarContainerLeadingConstraint?.constant = newConstraintValue

            if let tabID = sidebarHost.currentTabID, !isShowingSidebar {
                sidebarProvider.handleSidebarDidClose(for: tabID)
            }
            self.isAnimatingSidebarTransition = false
        }
    }

    func presentSidebar(for prompt: AIChatNativePrompt) {
        guard let currentTabID = sidebarHost.currentTabID else { return }

        if let sidebarViewController = sidebarProvider.getSidebarViewController(for: currentTabID) {
            // If sidebar is open append conversation with prompt
            sidebarViewController.setAIChatPrompt(prompt)
        } else {
            AIChatPromptHandler.shared.setData(prompt)
            // If not showing the sidebar, open it with the prompt
            updateSidebarConstraints(for: currentTabID, isShowingSidebar: true, withAnimation: true)
        }
    }

    private func handleAIChatHandoff(with payload: AIChatPayload) {
        guard let currentTabID = sidebarHost.currentTabID else { return }

        let isShowingSidebar = sidebarProvider.isShowingSidebar(for: currentTabID)

        if !isShowingSidebar {
            /// https://app.asana.com/1/137249556945/project/276630244458377/task/1211982069731816
            sidebarProvider.resetSidebar(for: currentTabID)

            // If not showing the sidebar open it with the payload received
            let sidebarViewController = sidebarProvider.makeSidebarViewController(for: currentTabID, burnerMode: sidebarHost.burnerMode)
            sidebarViewController.aiChatPayload = payload
            updateSidebarConstraints(for: currentTabID, isShowingSidebar: true, withAnimation: true)
            pixelFiring?.fire(
                AIChatPixel.aiChatSidebarOpened(
                    source: .serp,
                    shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                    minutesSinceSidebarHidden: sidebarHiddenAt(for: currentTabID)?.minutesSinceNow()
                ),
                frequency: .dailyAndStandard
            )
        } else {
            // If sidebar is open then pass the payload to a new AIChat tab
            aiChatTabOpener.openAIChatTab(with: .payload(payload), behavior: .newTab(selected: true))
        }
    }
}

extension AIChatSidebarPresenter: AIChatSidebarHostingDelegate {

    func sidebarHostDidSelectTab(with tabID: TabIdentifier) {
        let shouldShowSidebar = isSidebarOpen(for: tabID)
        updateSidebarConstraints(for: tabID, isShowingSidebar: shouldShowSidebar, withAnimation: false)
    }

    func sidebarHostDidUpdateTabs() {
        let allPinnedTabIDs = windowControllersManager.pinnedTabsManagerProvider.currentPinnedTabManagers.flatMap { $0.tabViewModels.keys }.map { $0.uuid }
        let allTabIDs = windowControllersManager.allTabCollectionViewModels.flatMap { $0.tabViewModels.keys }.map { $0.uuid }
        sidebarProvider.cleanUp(for: allPinnedTabIDs + allTabIDs)
    }
}

extension AIChatSidebarPresenter: AIChatSidebarViewControllerDelegate {

    func didClickOpenInNewTabButton() {
        guard let currentTabID = sidebarHost.currentTabID,
              let sidebar = sidebarProvider.sidebarsByTab[currentTabID] else { return }

        pixelFiring?.fire(AIChatPixel.aiChatSidebarExpanded, frequency: .dailyAndStandard)

        let restorationData = sidebar.restorationData
        let currentAIChatURL = sidebar.currentAIChatURL.removingAIChatPlacementParameter()

        toggleSidebar()

        Task { @MainActor in
            if let data = restorationData {
                aiChatTabOpener.openAIChatTab(with: .restoration(data), behavior: .newTab(selected: true))
            } else {
                aiChatTabOpener.openAIChatTab(with: .url(currentAIChatURL), behavior: .newTab(selected: true))
            }
        }
    }

    func didClickCloseButton() {
        pixelFiring?.fire(AIChatPixel.aiChatSidebarClosed(source: .sidebarCloseButton), frequency: .dailyAndStandard)

        windowControllersManager.lastKeyMainWindowController?.window?.makeFirstResponder(nil)
        toggleSidebar()
    }

}
