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

import FeatureFlags_iOS
import UIKit

extension MainViewController {
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
        state.aiChatEnabled = aiChatSettings.isAIChatEnabled
        state.duckAIShortcutAvailable = aiChatSettings.isAIChatEnabled && featureFlagger.isFeatureOn(.aiChatChromeShortcutIPad)
        state.duckAIButtonVisible = isDuckAIChromeButtonVisible
        state.passwordsEnabled = featureFlagger.isFeatureOn(.autofillAccessCredentialManagement)
        state.canHideTabs = tabSwitcherController.map { $0.canDismissOnEmpty || !$0.tabsModel.isEmpty } ?? true
        state.tabCount = tabManager.currentTabsModel.count
        state.canGoBack = currentTab?.canGoBack == true
        state.canGoForward = currentTab?.canGoForward == true
        return MenuCommandAvailability(state: state, nextStepsItems: NextStepsItemsVisibility(keyValueStore: keyValueStore))
    }

    func isMenuTabSelectionAvailable(_ command: UICommand?) -> Bool {
        guard command?.action == #selector(keyboardSelectTab(_:)),
              let keyCommand = command as? UIKeyCommand, let input = keyCommand.input, let number = Int(input) else { return true }
        return MainMenuSpec.tabIndex(number: number, count: tabManager.currentTabsModel.count, menuEnabled: true) != nil
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

    @objc func menuToggleDuckAIButton() {
        guard menuCommandAvailability.isEnabled(.toggleDuckAIButton) else { return }
        setDuckAIChromeButtonVisible(!isDuckAIChromeButtonVisible)
    }

    private var duckAIButtonFollowsTabBarShortcutSetting: Bool {
        featureFlagger.isFeatureOn(.aiChatChromeMenuButtonIPad)
    }

    private var isDuckAIChromeButtonVisible: Bool {
        guard aiChatSettings.isAIChatTabBarUserSettingsEnabled else { return false }
        return duckAIButtonFollowsTabBarShortcutSetting || aiChatSettings.isAIChatTabBarDuckAIButtonVisible
    }

    private func setDuckAIChromeButtonVisible(_ isVisible: Bool) {
        if duckAIButtonFollowsTabBarShortcutSetting || !aiChatSettings.isAIChatTabBarUserSettingsEnabled {
            aiChatSettings.enableAIChatTabBarUserSettings(enable: isVisible)
        } else {
            aiChatSettings.setAIChatTabBarDuckAIButtonVisible(isVisible)
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

    @objc func menuImportData() {
        guard menuCommandAvailability.isEnabled(.importData) else { return }
        dismissMenuPresentation { [weak self] in
            self?.launchDataImport(source: .settings, onFinished: {}, onCancelled: {})
        }
    }

    @objc func menuSetDefaultBrowser() {
        guard menuCommandAvailability.isEnabled(.setDefaultBrowser) else { return }
        NextStepsItemsVisibility(keyValueStore: keyValueStore).recordSetAsDefaultTapped()
        dismissMenuPresentation { [weak self] in
            self?.systemSettingsPiPTutorialManager.playPiPTutorialAndNavigateTo(destination: .defaultBrowser)
        }
    }

    @objc func menuAddToDock() {
        guard menuCommandAvailability.isEnabled(.addToDock) else { return }
        NextStepsItemsVisibility(keyValueStore: keyValueStore).recordAddToDockTapped()
        dismissMenuPresentation { [weak self] in
            let instructions = UIStoryboard(name: "HomeRow", bundle: nil).instantiateViewController(withIdentifier: "instructions")
            instructions.modalPresentationStyle = .fullScreen
            self?.present(instructions, animated: true)
        }
    }

    @objc func menuAddWidget() {
        guard menuCommandAvailability.isEnabled(.addWidget) else { return }
        NextStepsItemsVisibility(keyValueStore: keyValueStore).recordAddWidgetTapped()
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            let widgetEducation = WidgetEducationViewController()
            let navigationController = UINavigationController(rootViewController: widgetEducation)
            widgetEducation.navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: UserText.autofillNavigationButtonItemTitleClose, style: .plain, target: self, action: #selector(menuDismissPresentedScreen))
            self.present(navigationController, animated: true)
        }
    }

    @objc private func menuDismissPresentedScreen() {
        dismiss(animated: true)
    }

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
