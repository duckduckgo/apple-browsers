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

import AppKit
import BrowserServicesKit
import Combine
import AIChat

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

    /// Returns whether the AI Chat sidebar is open on a tab specified by `tabID`.
    func isSidebarOpen(for tabID: TabIdentifier) -> Bool

    /// Emits events whenever sidebar is shown or hidden for a tab.
    var sidebarPresenceWillChangePublisher: AnyPublisher<AIChatSidebarPresenceChange, Never> { get }
}

final class AIChatSidebarPresenter: AIChatSidebarPresenting {

    let sidebarPresenceWillChangePublisher: AnyPublisher<AIChatSidebarPresenceChange, Never>

    private let sidebarHost: AIChatSidebarHosting
    private let sidebarProvider: AIChatSidebarProviding
    private let aiChatTabOpener: AIChatTabOpening
    private let featureFlagger: FeatureFlagger
    private let windowControllersManager: WindowControllersManagerProtocol
    private let sidebarPresenceWillChangeSubject = PassthroughSubject<AIChatSidebarPresenceChange, Never>()

    private var cancellables = Set<AnyCancellable>()

    init(
        sidebarHost: AIChatSidebarHosting,
        sidebarProvider: AIChatSidebarProviding = AIChatSidebarProvider(),
        aiChatTabOpener: AIChatTabOpening,
        featureFlagger: FeatureFlagger,
        windowControllersManager: WindowControllersManagerProtocol
    ) {
        self.sidebarHost = sidebarHost
        self.sidebarProvider = sidebarProvider
        self.aiChatTabOpener = aiChatTabOpener
        self.featureFlagger = featureFlagger
        self.windowControllersManager = windowControllersManager

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
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return }
        guard let currentTabID = sidebarHost.currentTabID else { return }

        let willShowSidebar = !sidebarProvider.isShowingSidebar(for: currentTabID)

        updateSidebarConstraints(for: currentTabID, isShowingSidebar: willShowSidebar, withAnimation: true)
    }

    func isSidebarOpen(for tabID: TabIdentifier) -> Bool {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return false }
        return sidebarProvider.isShowingSidebar(for: tabID)
    }

    private func updateSidebarConstraints(for tabID: TabIdentifier, isShowingSidebar: Bool, withAnimation: Bool) {
        sidebarPresenceWillChangeSubject.send(.init(tabID: tabID, isShown: isShowingSidebar))

        if isShowingSidebar {
            let sidebarViewController = sidebarProvider.sidebar(for: tabID).sidebarViewController
            sidebarViewController.delegate = self
            sidebarHost.embedSidebarViewController(sidebarViewController)
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
                guard let self, let tabID, !isShowingSidebar else { return }
                self.sidebarProvider.handleSidebarDidClose(for: tabID)
            }
        } else {
            sidebarHost.sidebarContainerLeadingConstraint?.constant = newConstraintValue

            if let tabID = sidebarHost.currentTabID, !isShowingSidebar {
                sidebarProvider.handleSidebarDidClose(for: tabID)
            }
        }
    }

    private func handleAIChatHandoff(with payload: AIChatPayload) {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return }
        guard let currentTabID = sidebarHost.currentTabID else { return }

        let isShowingSidebar = sidebarProvider.isShowingSidebar(for: currentTabID)

        if !isShowingSidebar {
            // If not showing the sidebar open it with the payload received
            let sidebarViewController = sidebarProvider.sidebar(for: currentTabID).sidebarViewController
            sidebarViewController.aiChatPayload = payload
            updateSidebarConstraints(for: currentTabID, isShowingSidebar: true, withAnimation: true)
        } else {
            // If sidebar is open then pass the payload to a new AIChat tab
            aiChatTabOpener.openNewAIChatTab(withPayload: payload)
        }
    }
}

extension AIChatSidebarPresenter: AIChatSidebarHostingDelegate {

    func sidebarHostDidSelectTab(with tabID: TabIdentifier) {
        updateSidebarConstraints(for: tabID, isShowingSidebar: isSidebarOpen(for: tabID), withAnimation: false)
    }

    func sidebarHostDidUpdateTabs() {
        let allPinnedTabIDs = windowControllersManager.pinnedTabsManagerProvider.currentPinnedTabManagers.flatMap { $0.tabViewModels.keys }.map { $0.uuid }
        let allTabIDs = windowControllersManager.allTabCollectionViewModels.flatMap { $0.tabViewModels.keys }.map { $0.uuid }
        sidebarProvider.cleanUp(for: allPinnedTabIDs + allTabIDs)
    }
}

extension AIChatSidebarPresenter: AIChatSidebarViewControllerDelegate {

    func didClickOpenInNewTabButton(currentAIChatURL: URL, aiChatRestorationData: AIChatRestorationData?) {
        Task { @MainActor in
            if let data = aiChatRestorationData {
                aiChatTabOpener.openNewAIChatTab(withChatRestorationData: data)
            } else {
                aiChatTabOpener.openNewAIChatTab(currentAIChatURL, with: .newTab(selected: true))
            }
        }
    }

    func didClickCloseButton() {
        toggleSidebar()
    }

}
