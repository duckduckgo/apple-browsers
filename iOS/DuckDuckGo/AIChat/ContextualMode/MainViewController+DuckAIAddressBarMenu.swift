//
//  MainViewController+DuckAIAddressBarMenu.swift
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

import Core
import UIKit

extension MainViewController {

    /// What the address-bar Duck.ai button should do for the current tab and session.
    var duckAIAddressBarEntry: DuckAIAddressBarEntry {
        let coordinator = currentTab?.aiChatContextualSheetCoordinator
        return DuckAIAddressBarEntry.resolve(
            isContextualModeAvailable: aiChatContextualModeFeature.isAvailable,
            isFloatingInputAvailable: aiChatContextualFloatingInputFeature.isAvailable,
            isHomeTab: currentTab?.tabModel.isHomeTab ?? true,
            hasActiveChat: coordinator?.sessionState.hasActiveChat ?? false,
            isContextualSurfacePresented: coordinator?.isSheetPresented == true || coordinator?.isFloatingInputPresented == true
        )
    }

    /// Attaches the Duck.ai menu to the address-bar button, or detaches it so a tap acts directly.
    func refreshDuckAIAddressBarMenu() {
        let button = omniBar.barView.aiChatButton
        guard duckAIAddressBarEntry == .menu else {
            button?.menu = nil
            button?.showsMenuAsPrimaryAction = false
            return
        }

        // Deferred so the shown pixel records an actual display rather than the menu being attached.
        button?.menu = UIMenu(title: UserText.duckAiFeatureName, children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                self?.duckAIAddressBarPixelHandler.fireAddressBarMenuShown()
                completion(self?.duckAIAddressBarMenuChildren() ?? [])
            }
        ])
        button?.showsMenuAsPrimaryAction = true
    }

    func askAboutCurrentPageFromAddressBar() {
        guard let currentTab else { return }
        omniBar.endEditing()
        currentTab.presentContextualFloatingInput(from: self)
    }

    /// Tapping the address bar is one of the floating input's dismissal routes, and the page stays
    /// interactive underneath so that tap reaches the omnibar in the first place.
    func dismissFloatingContextualInputIfPresented() {
        // No presence check — `dismissFloatingInput` already no-ops when nothing is up, and a second
        // gate here would be one more thing to keep in step with it.
        currentTab?.aiChatContextualSheetCoordinator.dismissFloatingInput()
    }

    func dismissContextualDuckAISurface() {
        guard let coordinator = currentTab?.aiChatContextualSheetCoordinator else { return }
        if coordinator.isFloatingInputPresented {
            coordinator.dismissFloatingInput()
        } else {
            coordinator.dismissSheet()
        }
    }

    private func duckAIAddressBarMenuChildren() -> [UIMenuElement] {
        DuckAIAddressBarMenuFactory.makeActions(
            pageFavicon: currentPageFavicon(),
            onNewChat: { [weak self] in
                self?.duckAIAddressBarPixelHandler.fireAddressBarMenuNewChatSelected()
                self?.openFreshDuckAIChatFromAddressBarMenu()
            },
            onAskAboutPage: { [weak self] in
                self?.duckAIAddressBarPixelHandler.fireAddressBarMenuAskAboutPageSelected()
                self?.askAboutCurrentPageFromAddressBar()
            }
        )
    }

    private func currentPageFavicon() -> UIImage? {
        guard let domain = currentTab?.url?.host else { return nil }
        let result = FaviconsHelper.loadFaviconSync(forDomain: domain, usingCache: .tabs, useFakeFavicon: false)
        guard !result.isFake else { return nil }
        return result.image
    }

    /// `openAIChat()` rather than `openAIChatFromAddressBar`: the latter sends the omnibar's text as
    /// a prompt whenever the field is being edited, and New Chat must always open empty.
    private func openFreshDuckAIChatFromAddressBarMenu() {
        omniBar.endEditing()
        openAIChat()
    }
}
