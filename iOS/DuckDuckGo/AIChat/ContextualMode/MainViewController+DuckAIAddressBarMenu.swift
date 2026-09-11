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

import AIChat
import Core
import UIKit

enum DuckAIAddressBarMenuType: Equatable {
    case webPage
    case search(query: String)
    case document

    /// Resolves the menu variant for a tab with webPage as default
    static func resolve(isFeatureEnabled: Bool,
                        isShowingDocument: Bool,
                        tabType: TabType,
                        searchQuery: String?) -> DuckAIAddressBarMenuType {
        guard isFeatureEnabled else { return .webPage }
        if isShowingDocument { return .document }
        switch tabType {
        case .web, .aiChat:
            return .webPage
        case .serp:
            guard let query = searchQuery, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .webPage
            }
            return .search(query: query)
        }
    }
}

extension MainViewController {

    /// What the address-bar Duck.ai button should do for the current tab and session.
    var duckAIAddressBarEntry: DuckAIAddressBarEntry {
        DuckAIAddressBarEntry.resolve(
            isContextualModeAvailable: aiChatContextualModeFeature.isAvailable,
            isFloatingInputAvailable: aiChatContextualFloatingInputFeature.isAvailable,
            isIPadChromeMenuButtonAvailable: isChromeMenuButtonAvailable,
            isHomeTab: tabManager.currentTabsModel.currentTab?.isHomeTab ?? true,
            isChatHistoryAvailable: isDuckAIChatsMenuItemAvailable,
            hasChatToReopen: currentTab?.hasContextualChatToReopen ?? false,
            isContextualSurfacePresented: isContextualSurfacePresented
        )
    }

    var isChromeMenuButtonAvailable: Bool {
        DuckAIChromeShortcutVisibility.isChromeMenuButtonAvailable(isIPad: isPad, featureFlagger: featureFlagger)
    }

    var isDuckAIChatsMenuItemAvailable: Bool {
        DuckAIAddressBarMenuFactory.isChatHistoryAvailable(featureFlagger: featureFlagger,
                                                           userInterfaceIdiom: UIDevice.current.userInterfaceIdiom)
            || (isChromeMenuButtonAvailable && featureFlagger.isFeatureOn(.aiChatAddressBarRecentChats))
    }

    /// A contextual surface — the sheet or the floating input — is on screen for this tab.
    var isContextualSurfacePresented: Bool {
        let coordinator = currentTab?.aiChatContextualSheetCoordinator
        return coordinator?.isSheetPresented == true || coordinator?.isFloatingInputPresented == true
    }

    /// Whether the address-bar Duck.ai button shows its contextual glyph. A surface dismissed without
    /// a prompt leaves no chat, so it reverts.
    var hasContextualSession: Bool {
        DuckAIAddressBarEntry.showsContextualGlyph(
            isContextualModeAvailable: aiChatContextualModeFeature.isAvailable,
            isHomeTab: tabManager.currentTabsModel.currentTab?.isHomeTab ?? true,
            hasChatToReopen: currentTab?.hasContextualChatToReopen ?? false,
            isContextualSurfacePresented: isContextualSurfacePresented
        )
    }

    /// Attaches the Duck.ai menu to the address-bar button, or detaches it so a tap acts directly.
    func refreshDuckAIAddressBarMenu(type: DuckAIAddressBarMenuType) {
        let offersMenu = duckAIAddressBarEntry == .menu
        let addressBarButton = omniBar.barView.aiChatButton
        if offersMenu, let button = addressBarButton as? BrowserChromeButton {
            // UIKit reparents the preview, so hand it a stand-in from outside the field's glass group.
            button.menuHighlightTarget = { [weak self, weak button] in
                guard let button else { return nil }
                return self?.duckAIMenuAnchorView(over: button)
            }
        } else {
            (addressBarButton as? BrowserChromeButton)?.menuHighlightTarget = nil
            duckAIMenuAnchor?.removeFromSuperview()
            duckAIMenuAnchor = nil
        }
        attachDuckAIMenu(to: addressBarButton, offersMenu: offersMenu, source: .addressBarIcon, type: type)
        attachDuckAIMenu(to: tabsBarController?.aiChatMenuButton, offersMenu: offersMenu, source: .tabsBarButton, type: type)
    }

    private func attachDuckAIMenu(to button: UIButton?, offersMenu: Bool, source: AIChatEntryPointSource, type: DuckAIAddressBarMenuType) {
        guard let button else { return }
        guard offersMenu else {
            button.menu = nil
            button.showsMenuAsPrimaryAction = false
            return
        }

        // Deferred so the shown pixel records an actual display rather than the menu being attached.
        button.menu = UIMenu(title: UserText.duckAiFeatureName, children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                self?.recordNewTabPageSessionAction { $0.tapDuckaiButton() }
                self?.duckAIAddressBarPixelHandler.fireAddressBarMenuShown()
                completion(self?.duckAIAddressBarMenuChildren(source: source, type: type) ?? [])
            }
        ])
        button.showsMenuAsPrimaryAction = true
    }

    /// Transparent stand-in over the button, outside the glass field, for the menu to reparent.
    private func duckAIMenuAnchorView(over button: UIView) -> UIView? {
        guard let container: UIView = viewCoordinator.navigationBarContainer else { return nil }
        let anchor = duckAIMenuAnchor ?? {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            duckAIMenuAnchor = view
            return view
        }()
        if anchor.superview !== container {
            container.addSubview(anchor)
        }
        // Laid out first: the bar repositions its buttons after a surface closes.
        container.layoutIfNeeded()
        anchor.frame = container.convert(button.bounds, from: button)
        return anchor
    }

    func askAboutCurrentPageFromAddressBar() {
        guard let currentTab else { return }
        omniBar.endEditing()
        // The floating input is a contextual surface that bypasses `openAIChat` and the sheet, so
        // report the entry here; promoting it to the sheet later must not report a second one.
        fireAIChatEntryPointPixel(source: .contextualChat, opensNewTab: false, hasPrompt: false)
        if aiChatContextualFloatingInputFeature.isAvailable {
            currentTab.presentContextualFloatingInput(from: self)
        } else {
            currentTab.presentContextualAIChatSheet(from: self, attachingPage: true)
        }
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

    private func duckAIAddressBarMenuChildren(source: AIChatEntryPointSource, type: DuckAIAddressBarMenuType) -> [UIMenuElement] {
        DuckAIAddressBarMenuFactory.makeActions(
            featureFlagger: featureFlagger,
            userInterfaceIdiom: UIDevice.current.userInterfaceIdiom,
            isHomeTab: tabManager.currentTabsModel.currentTab?.isHomeTab ?? true,
            type: type,
            onNewChat: { [weak self] in
                self?.duckAIAddressBarPixelHandler.fireAddressBarMenuNewChatSelected()
                self?.openFreshDuckAIChatFromAddressBarMenu(source: source)
            },
            onContextAction: { [weak self] in
                switch type {
                case .webPage, .document:
                    self?.duckAIAddressBarPixelHandler.fireAddressBarMenuAskAboutPageSelected()
                    self?.askAboutCurrentPageFromAddressBar()
                case .search(let query):
                    // TODO: fire a dedicated "ask about search" pixel
                    self?.openFreshDuckAIChatFromAddressBarMenu(source: source, query: query)
                }
            },
            onRecentChats: { [weak self] in
                self?.duckAIAddressBarPixelHandler.fireAddressBarMenuRecentChatsSelected()
                self?.openRecentChatsFromAddressBarMenu()
            }
        )
    }

    private func openRecentChatsFromAddressBarMenu() {
        omniBar.endEditing()
        recordNewTabPageSessionDeparture()
        if isPad {
            openDuckAIChatsFromAddressBarMenu()
        } else {
            openAIChatHistory(source: .addressBar)
        }
    }

    private func openDuckAIChatsFromAddressBarMenu() {
        let url = AIChatURLParameters.sidebarOpenURL(from: aiChatSettings.aiChatURL)
        if tabManager.currentTabsModel.currentTab?.link != nil {
            loadUrlInNewTab(url, inheritedAttribution: nil)
        } else {
            loadUrl(url)
        }
    }

    /// `openAIChat()` rather than `openAIChatFromAddressBar`: the latter sends the omnibar's text as
    /// a prompt whenever the field is being edited. New Chat opens empty (`query == nil`); the SERP
    /// "Continue in Duck.ai" action passes the search query and auto-sends it.
    private func openFreshDuckAIChatFromAddressBarMenu(source: AIChatEntryPointSource, query: String? = nil) {
        omniBar.endEditing()
        // iPad has no unified toggle input, so the boundary rule would load the chat over the page.
        openAIChat(source: source, query, autoSend: query != nil, forcesNewTab: isPad)
    }
}
