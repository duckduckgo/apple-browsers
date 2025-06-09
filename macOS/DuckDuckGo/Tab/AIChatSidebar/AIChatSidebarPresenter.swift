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

import Foundation
import BrowserServicesKit
import Combine

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
protocol AIChatSidebarPresenting {

    /// Toggles the AI Chat sidebar visibility on a current tab, using appropriate animation.
    func toggleSidebar()

    /// Returns whether the AI Chat sidebar is open on a current tab.
    var isSidebarOpen: Bool { get }

    /// Emits events whenever sidebar is shown or hidden for a tab.
    var sidebarPresenceWillChangePublisher: AnyPublisher<AIChatSidebarPresenceChange, Never> { get }
}

final class AIChatSidebarPresenter: AIChatSidebarPresenting {

    let sidebarPresenceWillChangePublisher: AnyPublisher<AIChatSidebarPresenceChange, Never>

    private let sidebarHost: AIChatSidebarHosting
    private let sidebarProvider: AIChatSidebarProviding
    private let featureFlagger: FeatureFlagger
    private let sidebarPresenceWillChangeSubject = PassthroughSubject<AIChatSidebarPresenceChange, Never>()

    init(sidebarHost: AIChatSidebarHosting,
         sidebarProvider: AIChatSidebarProviding = AIChatSidebarProvider(),
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.sidebarHost = sidebarHost
        self.sidebarProvider = sidebarProvider
        self.featureFlagger = featureFlagger

        sidebarPresenceWillChangePublisher = sidebarPresenceWillChangeSubject.eraseToAnyPublisher()
        self.sidebarHost.aiChatSidebarHostingDelegate = self
    }

    func toggleSidebar() {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return }
        guard let currentTabID = sidebarHost.currentTabID else { return }

        let willShowSidebar = !sidebarProvider.isShowingSidebar(for: currentTabID)

        sidebarPresenceWillChangeSubject.send(.init(tabID: currentTabID, isShown: willShowSidebar))
        updateSidebarConstraints(for: currentTabID, isShowingSidebar: willShowSidebar, withAnimation: true)
    }

    var isSidebarOpen: Bool {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return false }
        guard let currentTabID = sidebarHost.currentTabID else { return false }
        return sidebarProvider.isShowingSidebar(for: currentTabID)
    }

    private func updateSidebarConstraints(for tabID: TabIdentifier, isShowingSidebar: Bool, withAnimation: Bool) {
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
}

extension AIChatSidebarPresenter: AIChatSidebarHostingDelegate {

    func sidebarHostDidSelectTab(with tabID: TabIdentifier) {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return }

        let isShowingSidebar = sidebarProvider.isShowingSidebar(for: tabID)
        updateSidebarConstraints(for: tabID, isShowingSidebar: isShowingSidebar, withAnimation: false)
    }

    func sidebarHostDidUpdateTabs(_ currentTabIDs: [TabIdentifier]) {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return }

        sidebarProvider.cleanUp(for: currentTabIDs)
    }
}

extension AIChatSidebarPresenter: AIChatSidebarViewControllerDelegate {

    func didClickOpenInNewTabButton() {
        Task { @MainActor in
            NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(nil, target: .newTabSelected)
        }
    }

    func didClickCloseButton() {
        toggleSidebar()
    }

}
