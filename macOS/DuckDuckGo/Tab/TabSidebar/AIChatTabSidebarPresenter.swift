//
//  AIChatTabSidebarPresenter.swift
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

protocol AIChatTabSidebarPresenting {
    func toggleSidebar()
}

final class AIChatTabSidebarPresenter: AIChatTabSidebarPresenting {
    private var sidebarHost: AIChatTabSidebarHosting
    private var sidebarProvider: AIChatTabSidebarProviding
    private var featureFlagger: FeatureFlagger

    init(sidebarHost: AIChatTabSidebarHosting,
         sidebarProvider: AIChatTabSidebarProviding = AIChatTabSidebarProvider(),
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.sidebarHost = sidebarHost
        self.sidebarProvider = sidebarProvider
        self.featureFlagger = featureFlagger

        self.sidebarHost.aiChatTabSidebarHostingDelegate = self
    }

    func toggleSidebar() {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return }
        guard let currentTabID = sidebarHost.currentTabID else { return }

        let willAnimateSidebarReveal = !sidebarProvider.isShowingSidebar(for: currentTabID)

        if willAnimateSidebarReveal {
            let sidebarViewController = sidebarProvider.tabSidebar(for: currentTabID).sidebarViewController
            sidebarHost.addAndLayoutChild(sidebarViewController, into: sidebarHost.sidebarContainer)
            updateWebContainerAndTabSidebarConstraints(forSidebarRevealed: true, animated: true)
        } else {
            updateWebContainerAndTabSidebarConstraints(forSidebarRevealed: false, animated: true)
        }
    }

    private func updateSidebar(for tabID: TabIdentifier) {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return }

        if sidebarProvider.isShowingSidebar(for: tabID) {
            let vc = sidebarProvider.tabSidebar(for: tabID).sidebarViewController
            sidebarHost.addAndLayoutChild(vc, into: sidebarHost.sidebarContainer)
            updateWebContainerAndTabSidebarConstraints(forSidebarRevealed: true, animated: false)
        } else {
            updateWebContainerAndTabSidebarConstraints(forSidebarRevealed: false, animated: false)
        }
    }

    private func updateWebContainerAndTabSidebarConstraints(forSidebarRevealed: Bool, animated: Bool) {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else { return }

        let newConstraintValue = forSidebarRevealed ? -self.sidebarProvider.sidebarWidth : 0.0

        sidebarHost.sidebarContainerWidthConstraint?.constant = sidebarProvider.sidebarWidth

        if animated {
            NSAnimationContext.runAnimationGroup { [weak self] context in
                guard let self else { return }

                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sidebarHost.sidebarContainerLeadingConstraint?.animator().constant = newConstraintValue
            } completionHandler: { [weak self, tabID = sidebarHost.currentTabID] in
                guard let self, let tabID, !forSidebarRevealed else { return }
                self.sidebarProvider.handleSidebarDidClose(for: tabID)
            }
        } else {
            sidebarHost.sidebarContainerLeadingConstraint?.constant = newConstraintValue

            if let tabID = sidebarHost.currentTabID, !forSidebarRevealed {
                sidebarProvider.handleSidebarDidClose(for: tabID)
            }
        }
    }
}

extension AIChatTabSidebarPresenter: AIChatTabSidebarHostingDelegate {

    func updateSidebarStateForSelectedTab(with tabID: TabIdentifier) {
        updateSidebar(for: tabID)
    }

    func refreshSidebarState(for currentTabIDs: [TabIdentifier]) {
        sidebarProvider.cleanUp(for: currentTabIDs)
    }
}
