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
        DuckAIAddressBarEntry.resolve(
            isContextualModeAvailable: aiChatContextualModeFeature.isAvailable,
            isFloatingInputAvailable: aiChatContextualFloatingInputFeature.isAvailable,
            isHomeTab: currentTab?.tabModel.isHomeTab ?? true,
            hasChatToReopen: currentTab?.hasContextualChatToReopen ?? false,
            isContextualSurfacePresented: isContextualSurfacePresented
        )
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
            isHomeTab: currentTab?.tabModel.isHomeTab ?? true,
            hasChatToReopen: currentTab?.hasContextualChatToReopen ?? false,
            isContextualSurfacePresented: isContextualSurfacePresented
        )
    }

    /// Attaches the Duck.ai menu to the address-bar button, or detaches it so a tap acts directly.
    func refreshDuckAIAddressBarMenu() {
        let button = omniBar.barView.aiChatButton
        guard duckAIAddressBarEntry == .menu else {
            button?.menu = nil
            button?.showsMenuAsPrimaryAction = false
            (button as? BrowserChromeButton)?.menuHighlightTarget = nil
            duckAIMenuAnchor?.removeFromSuperview()
            duckAIMenuAnchor = nil
            return
        }

        // UIKit reparents the preview, so hand it a stand-in from outside the field's glass group.
        if let button = button as? BrowserChromeButton {
            button.menuHighlightTarget = { [weak self, weak button] in
                guard let button else { return nil }
                return self?.duckAIMenuAnchorView(over: button)
            }
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

    /// `openAIChat()` rather than `openAIChatFromAddressBar`: the latter sends the omnibar's text as
    /// a prompt whenever the field is being edited, and New Chat must always open empty.
    private func openFreshDuckAIChatFromAddressBarMenu() {
        omniBar.endEditing()
        openAIChat(source: .addressBarIcon)
    }
}
