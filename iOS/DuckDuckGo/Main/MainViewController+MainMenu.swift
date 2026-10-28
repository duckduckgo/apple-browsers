//
//  MainViewController+MainMenu.swift
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
import FeatureFlags_iOS
import UIKit

extension MainViewController {
    var effectiveMenuBrowsingMode: BrowsingMode {
        tabSwitcherController?.selectedBrowsingMode ?? tabManager.currentBrowsingMode
    }

    var menuNativeChatsAvailable: Bool {
        aiChatSettings.isAIChatEnabled && featureFlagger.isFeatureOn(.aiChatNativeStorage) &&
            mainMenuAIChats.isAvailable(isFireMode: effectiveMenuBrowsingMode == .fire)
    }

    func loadMainMenuChats(completion: @escaping ([MainMenuSpec.Menu]) -> Void) {
        guard aiChatSettings.isAIChatEnabled, menuNativeChatsAvailable else { completion([]); return }
        let isFireMode = effectiveMenuBrowsingMode == .fire
        mainMenuAIChats.loadSnapshot(isFireMode: isFireMode) { [weak self] snapshot in
            guard let self, let snapshot, aiChatSettings.isAIChatEnabled, menuNativeChatsAvailable,
                  isFireMode == (effectiveMenuBrowsingMode == .fire) else { completion([]); return }
            completion(MainMenuSpec.chatHistoryMenus(snapshot: snapshot, aiChatURL: aiChatSettings.aiChatURL, isFireMode: isFireMode))
        }
    }

    func isMenuChatCommandAvailable(_ command: UICommand?) -> Bool {
        guard let command, let kind = MainMenuCommand(action: command.action), kind == .openRecentChat || kind == .deleteAllChats else { return true }
        guard let payload = MainMenuAIChatPayload(propertyList: command.propertyList) else { return false }
        return payload.isEnabled(for: kind, currentMode: tabManager.currentBrowsingMode, switcherMode: tabSwitcherController?.selectedBrowsingMode)
    }

    @objc func menuOpenDuckAI() {
        guard menuCommandAvailability.isEnabled(.openDuckAI) else { return }
        dismissMenuPresentation { [weak self] in
            self?.openAIChat(source: .menuBarOpen, forcesNewTab: true)
        }
    }

    @objc func menuNewChat() {
        guard menuCommandAvailability.isEnabled(.newChat) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            if let tab = currentTab, tab.isAITab {
                openNewChatFromDuckAIPage(tab, source: .menuBarNewChat)
            } else {
                newTab(allowingKeyboard: false, startsNewTabPageSessionVisit: false)
                openAIChat(source: .menuBarNewChat, reportsNewTab: true)
            }
        }
    }

    @objc func menuNewVoiceChat() {
        guard menuCommandAvailability.isEnabled(.newVoiceChat) else { return }
        dismissMenuPresentation { [weak self] in
            self?.startDuckAIVoiceMode(from: .menuBar, entryPointSource: .menuBarVoiceChat)
        }
    }

    @objc func menuNewImageChat() {
        guard menuCommandAvailability.isEnabled(.newImageChat) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            fireAIChatEntryPointPixel(source: .menuBarImageChat, opensNewTab: true, hasPrompt: false)
            let url = AIChatURLParameters.imageModeURL(from: aiChatSettings.aiChatURL)
            loadUrlInNewTab(url, inheritedAttribution: nil) { $0.duckAIEntrySource = .menuBarImageChat }
        }
    }

    @objc func menuOpenRecentChat(_ command: UICommand) {
        guard menuCommandAvailability.isEnabled(.openRecentChat), isMenuChatCommandAvailable(command),
              let payload = MainMenuAIChatPayload(propertyList: command.propertyList), let url = payload.url else { return }
        dismissMenuPresentation { [weak self] in
            guard let self, payload.isEnabled(for: .openRecentChat, currentMode: tabManager.currentBrowsingMode, switcherMode: nil) else { return }
            mainMenuAIChats.chatOpened()
            openChatHistorySelection(url: url, source: .menuBarRecentChat)
        }
    }

    @objc func menuDeleteAllChats(_ command: UICommand) {
        guard menuCommandAvailability.isEnabled(.deleteAllChats), isMenuChatCommandAvailable(command),
              let payload = MainMenuAIChatPayload(propertyList: command.propertyList) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self, payload.isEnabled(for: .deleteAllChats, currentMode: tabManager.currentBrowsingMode, switcherMode: nil) else { return }
            mainMenuAIChats.loadSnapshot(isFireMode: payload.isFireMode) { [weak self] snapshot in
                guard let self, let snapshot, menuCommandAvailability.isEnabled(.deleteAllChats),
                      payload.isEnabled(for: .deleteAllChats, currentMode: tabManager.currentBrowsingMode, switcherMode: nil),
                      let deletion = mainMenuAIChats.deletion(snapshot: snapshot, isFireMode: payload.isFireMode, executor: fireExecutor,
                                                             onDeleted: { [weak self] in self?.refreshMenuChatsAfterDeletion(isFireMode: payload.isFireMode) }) else { return }
                presentMenuChatDeletion(deletion)
            }
        }
    }

    private func refreshMenuChatsAfterDeletion(isFireMode: Bool) {
        for tab in tabManager.tabsModel(for: isFireMode ? .fire : .normal).tabs {
            guard let controller = tabManager.controller(for: tab) else { continue }
            controller.reloadFullModeAIChatIfNeeded()
            controller.reloadContextualAIChatIfNeeded()
        }
    }

    private func presentMenuChatDeletion(_ deletion: MainMenuAIChats.Deletion) {
        let anchor: UIView = viewCoordinator.omniBar.barView.menuButton ?? view
        let sourceRect = anchor.convert(anchor.bounds, to: view.window)
        FireConfirmationPresenter().presentFireConfirmation(
            on: self, sourceRect: sourceRect, tabViewModel: nil, pixelSource: .browsing,
            fireContext: .deleteChats(count: deletion.count, onDelete: { [weak self] in
                self?.dismiss(animated: true) { [weak self] in
                    guard let self else { return }
                    fireButtonAnimator.animate { await deletion.confirm() } onTransitionCompleted: {} completion: {}
                }
            }), browsingMode: deletion.isFireMode ? .fire : .normal, onConfirm: { _ in }, onCancel: {})
    }

    var menuCommandAvailability: MenuCommandAvailability {
        let presentation: MenuCommandAvailability.State.Presentation
        if let tabSwitcherController {
            presentation = tabSwitcherController.presentedViewController == nil ? .tabSwitcher : .blockingModal
        } else if let presented = presentedViewController {
            let root = (presented as? UINavigationController)?.viewControllers.first ?? presented
            if root is AutofillLoginListViewController {
                presentation = .passwords
            } else if root is DownloadsListHostingController {
                presentation = .downloads
            } else if root is SettingsHostingController {
                presentation = .settings
            } else if root is BookmarksViewController {
                presentation = .bookmarks
            } else {
                presentation = .blockingModal
            }
        } else {
            presentation = .browser
        }
        var state = MenuCommandAvailability.State(shortcutsEnabled: isShortcutEnabled(), presentation: presentation)
        state.aiChatEnabled = aiChatSettings.isAIChatEnabled
        state.nativeChatsAvailable = menuNativeChatsAvailable
        state.hasTab = tabManager.currentTabsModel.currentTab != nil
        state.hasWebsite = currentTab?.link != nil && currentTab?.isError != true
        state.isLoading = currentTab?.isLoading == true
        state.findActive = findInPageView?.findInPage != nil
        if #available(iOS 16, *) {
            state.findActive = state.findActive || currentTab?.webView.findInteraction?.isFindNavigatorVisible == true
        }
        state.omnibarEditing = viewCoordinator.omniBar.isTextFieldEditing
        state.fireModeEnabled = fireModeCapability.isFireModeEnabled
        state.voiceSearchEnabled = voiceSearchHelper.isVoiceSearchEnabled
        state.passwordsEnabled = featureFlagger.isFeatureOn(.autofillAccessCredentialManagement)
        state.canHideTabs = tabSwitcherController.map { $0.canDismissOnEmpty || !$0.tabsModel.isEmpty } ?? true
        state.tabCount = tabManager.currentTabsModel.count
        state.canGoBack = currentTab?.canGoBack == true
        state.canGoForward = currentTab?.canGoForward == true
        return MenuCommandAvailability(state: state)
    }

    func isMenuTabSelectionAvailable(_ command: UICommand?) -> Bool {
        guard command?.action == #selector(keyboardSelectTab(_:)),
              let keyCommand = command as? UIKeyCommand, let input = keyCommand.input, let number = Int(input) else { return true }
        return MainMenuSpec.tabIndex(number: number, count: tabManager.currentTabsModel.count, menuEnabled: true) != nil
    }

    @objc func menuToggleBookmarks() {
        guard menuCommandAvailability.isEnabled(.showBookmarks) else { return }
        let hide = menuCommandAvailability.state.presentation == .bookmarks
        dismissMenuPresentation { [weak self] in
            guard !hide else { return }
            self?.onBookmarksPressed()
        }
    }

    @objc func menuImportBookmarks() {
        guard menuCommandAvailability.isEnabled(.importBookmarks) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            if #available(iOS 18.2, *) {
                self.launchDataImport(source: .bookmarks, onFinished: {}, onCancelled: {})
            } else {
                self.bookmarksFileFlow.presentDocumentPicker(from: self)
            }
        }
    }

    @objc func menuExportBookmarks() {
        guard menuCommandAvailability.isEnabled(.exportBookmarks) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            let anchor: UIView
            if let button = self.viewCoordinator.omniBar.barView.menuButton, button.window != nil, !button.isHidden {
                anchor = button
            } else {
                anchor = self.view
            }
            self.bookmarksFileFlow.exportHtmlFile(from: self, anchor: anchor)
        }
    }

    @objc func menuOpenBookmark(_ command: UICommand) {
        guard menuCommandAvailability.isEnabled(.openBookmark),
              let value = command.propertyList as? String, let url = URL(string: value) else { return }
        dismissMenuPresentation { [weak self] in self?.bookmarksDidSelect(url: url) }
    }

    @objc func menuVoiceSearch() {
        guard menuCommandAvailability.isEnabled(.voiceSearch) else { return }
        handleVoiceSearchOpenRequest(preferredTarget: .SERP)
    }

    @objc func menuShare() {
        guard menuCommandAvailability.isEnabled(.share), let link = currentTab?.link else { return }
        let anchor: UIView
        if let button = viewCoordinator.omniBar.barView.customizableButton, button.window != nil, !button.isHidden {
            anchor = button
        } else {
            anchor = view
        }
        currentTab?.onShareAction(forLink: link, fromView: anchor)
    }

    @objc func menuStop() {
        guard menuCommandAvailability.isEnabled(.stop) else { return }
        stopLoading()
    }

    @objc func menuTogglePasswords() {
        guard menuCommandAvailability.isEnabled(.showPasswords) else { return }
        let hide = menuCommandAvailability.state.presentation == .passwords
        dismissMenuPresentation { [weak self] in
            guard !hide, let self else { return }
            self.launchAutofillLogins(source: .menuBar)
        }
    }

    @objc func menuToggleDownloads() {
        guard menuCommandAvailability.isEnabled(.showDownloads) else { return }
        let hide = menuCommandAvailability.state.presentation == .downloads
        dismissMenuPresentation { [weak self] in
            guard !hide else { return }
            self?.segueToDownloads()
        }
    }

    @objc func menuNewTabOnRight() {
        guard menuCommandAvailability.isEnabled(.newTabOnRight) else { return }
        recordUserOpenedTab()
        newTab(placement: .afterCurrentTab)
    }

    @objc func menuDuplicateTab() {
        guard menuCommandAvailability.isEnabled(.duplicateTab) else { return }
        guard let source = currentTab, source.tabModel.link != nil else {
            recordUserOpenedTab()
            newTab(placement: .afterCurrentTab)
            return
        }
        performCancel()
        let duplicate = tabManager.duplicate(source)
        recordUserOpenedTab()
        selectTab(duplicate.tabModel)
    }

    @objc func menuAbout() {
        guard menuCommandAvailability.isEnabled(.about) else { return }
        dismissMenuPresentation { [weak self] in self?.launchSettings(deepLinkTarget: .about) }
    }

    @objc func menuFeedback() {
        guard menuCommandAvailability.isEnabled(.feedback) else { return }
        dismissMenuPresentation { [weak self] in self?.segueToFeedback() }
    }

    @objc func menuOpenLink() { }
    @objc func menuOpenBackgroundLink() { }

    func dismissMenuPresentation(completion: @escaping () -> Void) {
        if let tabSwitcherController {
            guard tabSwitcherController.canDismissOnEmpty || !tabSwitcherController.tabsModel.isEmpty else { return }
            tabSwitcherController.dismiss(animated: true, completion: completion)
        } else if let presentedViewController {
            presentedViewController.dismiss(animated: true, completion: completion)
        } else {
            completion()
        }
    }
}
