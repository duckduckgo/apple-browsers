//
//  MainViewController+KeyCommands.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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

import UIKit
import FeatureFlags_iOS

extension MainViewController {
    
    override var keyCommands: [UIKeyCommand]? {
        let menuSpec = MainMenuSpec(isEnabled: featureFlagger.isIPadMenuBarEnabled(),
                                    context: .init(voiceSearchEnabled: voiceSearchHelper.isVoiceSearchEnabled,
                                                   fireModeEnabled: fireModeCapability.isFireModeEnabled))
        let settingsCommand = UIKeyCommand(title: UserText.settingsTitle, action: #selector(keyboardSettings),
                                          input: ",", modifierFlags: .command)
        settingsCommand.wantsPriorityOverSystemBehavior = true

        let alwaysAvailable: [UIKeyCommand] = [
            settingsCommand,
            UIKeyCommand(title: "", action: #selector(keyboardFire), input: UIKeyCommand.inputBackspace,
                         modifierFlags: [ .control, .alternate ], discoverabilityTitle: UserText.keyCommandFire)
        ]
        
        guard tabSwitcherController == nil else {
            return menuSpec.remainingKeyCommands(from: alwaysAvailable)
        }
        
        var browsingCommands = [UIKeyCommand]()
        if newTabPageViewController == nil {
            browsingCommands = [
                UIKeyCommand(title: "", action: #selector(keyboardFind), input: "f", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandFind),
                UIKeyCommand(title: "", action: #selector(keyboardBrowserForward), input: "]", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandBrowserForward),
                UIKeyCommand(title: "", action: #selector(keyboardBrowserBack), input: "[", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandBrowserBack),
                UIKeyCommand(title: "", action: #selector(keyboardBrowserForward), input: UIKeyCommand.inputRightArrow, modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandBrowserForward),
                UIKeyCommand(title: "", action: #selector(keyboardBrowserBack), input: UIKeyCommand.inputLeftArrow, modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandBrowserBack),
                UIKeyCommand(title: "", action: #selector(keyboardReload), input: "r", modifierFlags: .command,
                             discoverabilityTitle: UserText.keyCommandReload),
                UIKeyCommand(title: "", action: #selector(keyboardPrint), input: "p", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandPrint),
                UIKeyCommand(title: "", action: #selector(keyboardAddBookmark), input: "d", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandAddBookmark),
                UIKeyCommand(title: "", action: #selector(keyboardAddFavorite), input: "d", modifierFlags: [.command, .control],
                             discoverabilityTitle: UserText.keyCommandAddFavorite),
                UIKeyCommand(title: "", action: #selector(keyboardNoOperation), input: "tap link", modifierFlags: [.command, .shift],
                             discoverabilityTitle: UserText.keyCommandOpenInNewTab),
                UIKeyCommand(title: "", action: #selector(keyboardNoOperation), input: "tap link", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandOpenInNewBackgroundTab),
                UIKeyCommand(title: "", action: #selector(keyboardZoomIn), input: "=", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandZoomIn),
                UIKeyCommand(title: "", action: #selector(keyboardZoomIn), input: "+", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandZoomIn),
                UIKeyCommand(title: "", action: #selector(keyboardZoomOut), input: "-", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandZoomOut),
                UIKeyCommand(title: "", action: #selector(keyboardZoomReset), input: "0", modifierFlags: [.command],
                             discoverabilityTitle: UserText.keyCommandResetZoom)
            ]
        }
        
        var findInPageCommands = [UIKeyCommand]()
        if findInPageView?.findInPage != nil {
            findInPageCommands = [
                UIKeyCommand(title: "", action: #selector(keyboardFindNext), input: "g", modifierFlags: .command,
                             discoverabilityTitle: UserText.keyCommandFindNext),
                UIKeyCommand(title: "", action: #selector(keyboardFindPrevious), input: "g", modifierFlags: [.command, .shift ],
                             discoverabilityTitle: UserText.keyCommandFindPrevious)
            ]
        }
        
        var arrowKeys = [UIKeyCommand]()
        if viewCoordinator.omniBar.isTextFieldEditing {
            arrowKeys = [
                UIKeyCommand(title: "", action: #selector(keyboardMoveSelectionUp), input: UIKeyCommand.inputUpArrow, modifierFlags: []),
                UIKeyCommand(title: "", action: #selector(keyboardMoveSelectionDown), input: UIKeyCommand.inputDownArrow, modifierFlags: [])
            ]
        }

        let tabCommands: [UIKeyCommand] = [
            UIKeyCommand(title: "", action: #selector(keyboardCloseTab), input: "w", modifierFlags: .command,
                         discoverabilityTitle: UserText.keyCommandCloseTab),
            UIKeyCommand(title: "", action: #selector(keyboardNewTab), input: "t", modifierFlags: .command,
                         discoverabilityTitle: UserText.keyCommandNewTab),
            UIKeyCommand(title: "", action: #selector(keyboardNewTab), input: "n", modifierFlags: .command,
                         discoverabilityTitle: UserText.keyCommandNewTab)
        ]

        let indexedTabCommands = (1...9).map {
            UIKeyCommand(title: "", action: #selector(keyboardSelectTab(_:)), input: String($0), modifierFlags: .command,
                         discoverabilityTitle: UserText.keyCommandSelect)
        }

        var newFireTabCommands: [UIKeyCommand] = []
        if fireModeCapability.isFireModeEnabled {
            newFireTabCommands.append(
                UIKeyCommand(title: "", action: #selector(keyboardNewFireTab), input: "n", modifierFlags: [.command, .shift],
                             discoverabilityTitle: UserText.keyCommandNewFireTab)
            )
        }

        let other: [UIKeyCommand] = [
            UIKeyCommand(title: "", action: #selector(keyboardNextTab), input: "]", modifierFlags: [.shift, .command],
                         discoverabilityTitle: UserText.keyCommandNextTab),
            UIKeyCommand(title: "", action: #selector(keyboardPreviousTab), input: "[", modifierFlags: [.shift, .command],
                         discoverabilityTitle: UserText.keyCommandPreviousTab),
            UIKeyCommand(title: "", action: #selector(keyboardNextTab), input: "]", modifierFlags: [.shift, .command],
                         discoverabilityTitle: UserText.keyCommandNextTab),
            UIKeyCommand(title: "", action: #selector(keyboardPreviousTab), input: "[", modifierFlags: [.shift, .command],
                         discoverabilityTitle: UserText.keyCommandPreviousTab),
            UIKeyCommand(title: "", action: #selector(keyboardShowAllTabs), input: "\\", modifierFlags: [.shift, .control],
                         discoverabilityTitle: UserText.keyCommandShowAllTabs),
            UIKeyCommand(title: "", action: #selector(keyboardShowAllTabs), input: UIKeyCommand.inputTab, modifierFlags: [.alternate, .command],
                         discoverabilityTitle: UserText.keyCommandShowAllTabs),
            UIKeyCommand(title: "", action: #selector(keyboardShowAllTabs), input: "\\", modifierFlags: [.shift, .command],
                         discoverabilityTitle: UserText.keyCommandShowAllTabs),
            UIKeyCommand(title: "", action: #selector(keyboardLocation), input: "l", modifierFlags: [.command],
                         discoverabilityTitle: UserText.keyCommandLocation),
            UIKeyCommand(title: "", action: #selector(keyboardNextTab), input: UIKeyCommand.inputTab, modifierFlags: .control,
                         discoverabilityTitle: UserText.keyCommandNextTab),
            UIKeyCommand(title: "", action: #selector(keyboardPreviousTab), input: UIKeyCommand.inputTab, modifierFlags: [.control, .shift],
                         discoverabilityTitle: UserText.keyCommandPreviousTab),

            // No discoverability as these should be intuitive
            UIKeyCommand(title: "", action: #selector(keyboardEscape), input: UIKeyCommand.inputEscape, modifierFlags: [])
        ]

        let commands = [alwaysAvailable, browsingCommands, findInPageCommands, arrowKeys, tabCommands, indexedTabCommands,
                        newFireTabCommands, other].flatMap { $0 }
        commands.forEach {
            $0.wantsPriorityOverSystemBehavior = true
        }
        return menuSpec.remainingKeyCommands(from: commands)
    }

    override func validate(_ command: UICommand) {
        super.validate(command)
        guard featureFlagger.isIPadMenuBarEnabled(), let menuCommand = MainMenuCommand(action: command.action) else { return }
        if let title = menuCommandAvailability.title(for: menuCommand) { command.title = title }
        if menuCommandAvailability.isEnabled(menuCommand), isMenuTabSelectionAvailable(command) && isMenuChatCommandAvailable(command) {
            command.attributes.remove(.disabled)
        } else {
            command.attributes.insert(.disabled)
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard featureFlagger.isIPadMenuBarEnabled(), let command = MainMenuCommand(action: action) else {
            return super.canPerformAction(action, withSender: sender)
        }
        return menuCommandAvailability.isEnabled(command) && isMenuTabSelectionAvailable(sender as? UICommand) && isMenuChatCommandAvailable(sender as? UICommand)
    }

    @objc func keyboardMoveSelectionUp() {
        suggestionTrayController?.keyboardMoveSelectionUp()
    }

    @objc func keyboardMoveSelectionDown() {
        suggestionTrayController?.keyboardMoveSelectionDown()
    }

    @objc func keyboardReload() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.reload) else { return }
        guard isShortcutEnabled() else { return }
        self.currentTab?.refresh()
    }

    @objc func keyboardZoomIn() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.zoomIn) else { return }
        guard isShortcutEnabled() else { return }
        currentTab?.zoomIn()
    }

    @objc func keyboardZoomOut() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.zoomOut) else { return }
        guard isShortcutEnabled() else { return }
        currentTab?.zoomOut()
    }

    @objc func keyboardZoomReset() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.actualSize) else { return }
        guard isShortcutEnabled() else { return }
        currentTab?.resetTextZoom()
    }

    @objc func keyboardFindNext() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.findNext) else { return }
        if #available(iOS 16, *), currentTab?.webView.findInteraction?.isFindNavigatorVisible == true {
            currentTab?.webView.findInteraction?.findNext()
        } else {
            self.findInPageView?.findInPage?.next()
        }
    }

    @objc func keyboardFindPrevious() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.findPrevious) else { return }
        if #available(iOS 16, *), currentTab?.webView.findInteraction?.isFindNavigatorVisible == true {
            currentTab?.webView.findInteraction?.findPrevious()
        } else {
            self.findInPageView?.findInPage?.previous()
        }
    }

    @objc func keyboardLocation() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.location) else { return }
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }

        showBars()
        // A tap only counts when it starts editing; ⌘L on an already focused bar is the same.
        if !isInputFocused {
            fireAddressBarClickPixel()
        }
        viewCoordinator.omniBar.beginEditing(animated: true)
    }

    @objc func keyboardFire() {
        if let tabSwitcherController {
            tabSwitcherController.keyboardFire()
            return
        }
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard isShortcutEnabled() else { return }
        onFirePressed()
    }

    @objc func keyboardSettings() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard isShortcutEnabled() else { return }
        if let tabSwitcherController {
            guard tabSwitcherController.presentedViewController == nil else { return }
            tabSwitcherController.dismiss(animated: true) { [weak self] in
                self?.onSettingsPressed()
            }
            return
        }
        guard presentedViewController == nil else { return }
        onSettingsPressed()
    }
    
    @objc func keyboardFind() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.find) else { return }
        guard isShortcutEnabled() else { return }
        currentTab?.requestFindInPage()
    }
    
    @objc func keyboardEscape() {
        guard tabSwitcherController == nil else { return }
        if #available(iOS 16.0, *), currentTab?.findInPageImplementation == .system {
            dismissSystemFindNavigator(for: currentTab)
        } else {
            findInPageView?.done()
        }
        hideSuggestionTray()
        performCancel()
    }
    
    @objc func keyboardNewTab() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.newTab) else { return }
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        
        if featureFlagger.isIPadMenuBarEnabled() || currentTab != nil || featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage) {
            recordUserOpenedTab()
            newTab()
        } else {
            currentTab?.requestFindInPage()
        }
    }

    @objc func keyboardNewFireTab() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.newFireTab) else { return }
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        guard fireModeCapability.isFireModeEnabled else { return }

        recordDuckAISessionPendingExit(.fireTabOpened)
        recordUserOpenedTab()
        tabManager.setBrowsingMode(.fire, source: .keyCommand)
        performCancel()
        newTab()
    }
    
    @objc func keyboardCloseTab() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.closeTab) else { return }
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        
        if featureFlagger.isIPadMenuBarEnabled(), let tab = tabManager.currentTabsModel.currentTab {
            closeTabOnUserRequest(tab)
        } else if let tab = currentTab {
            closeTabOnUserRequest(tab.tabModel)
        }
    }
    
    @objc func keyboardNextTab() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.nextTab) else { return }
        guard tabSwitcherController == nil else { return }
        
        guard let targetTab = tabManager.currentTabsModel.nextTab else { return }
        selectTabFromKeyboard(targetTab)
    }

    @objc func keyboardSelectTab(_ command: UIKeyCommand) {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard tabSwitcherController == nil, presentedViewController == nil else { return }
        guard isShortcutEnabled() else { return }
        guard let input = command.input, let number = Int(input), (1...9).contains(number) else { return }
        guard let index = MainMenuSpec.tabIndex(number: number, count: tabManager.currentTabsModel.count,
                                               menuEnabled: featureFlagger.isIPadMenuBarEnabled()),
              let targetTab = tabManager.currentTabsModel.get(tabAt: index) else { return }
        selectTabFromKeyboard(targetTab)
    }
    
    @objc func keyboardPreviousTab() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.previousTab) else { return }
        guard tabSwitcherController == nil else { return }
        
        guard let targetTab = tabManager.currentTabsModel.previousTab else { return }
        selectTabFromKeyboard(targetTab)
    }

    private func selectTabFromKeyboard(_ targetTab: Tab) {
        let switchesTab = targetTab !== tabManager.currentTabsModel.currentTab
        performCancel()
        selectTab(targetTab)
        if switchesTab {
            recordDirectTabSelection(of: targetTab)
            showKeyboardOnNewTabPageIfAllowed()
        }
    }
    
    @objc func keyboardShowAllTabs() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        if featureFlagger.isIPadMenuBarEnabled() {
            guard menuCommandAvailability.isEnabled(.showTabs) else { return }
            dismissMenuPresentation { [weak self] in
                self?.performCancel()
                self?.showTabSwitcher()
            }
        } else {
            performCancel()
            showTabSwitcher()
        }
    }

    @objc func keyboardBrowserForward() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.forward) else { return }
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        
        currentTab?.goForward()
    }
    
    @objc func keyboardBrowserBack() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.back) else { return }
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }

        recordDuckAISessionPendingExit(.backOrClose)
        currentTab?.goBack()
    }
    
    @objc func keyboardPrint() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.printPage) else { return }
        guard isShortcutEnabled() else { return }
        currentTab?.print()
    }

    @objc func keyboardAddBookmark() {
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.addBookmark) else { return }
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard isShortcutEnabled() else { return }
        saveBookmark(favorite: false)
    }

    @objc func keyboardAddFavorite() {
        guard !featureFlagger.isIPadMenuBarEnabled() || menuCommandAvailability.isEnabled(.addFavorite) else { return }
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard isShortcutEnabled() else { return }
        saveBookmark(favorite: true)
    }
    
    @objc func keyboardNoOperation() { }

    func isShortcutEnabled() -> Bool {
        !duckAIFireOnboardingFlow.controlsLocked
    }

    private func saveBookmark(favorite: Bool) {
        currentTab?.saveAsBookmark(favorite: favorite, viewModel: menuBookmarksViewModel)
    }

}
