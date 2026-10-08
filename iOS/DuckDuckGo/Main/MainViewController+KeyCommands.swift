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
        let settingsCommand = UIKeyCommand(title: UserText.settingsTitle, action: #selector(keyboardSettings),
                                          input: ",", modifierFlags: .command)
        settingsCommand.wantsPriorityOverSystemBehavior = true

        let alwaysAvailable: [UIKeyCommand] = [
            settingsCommand,
            UIKeyCommand(title: "", action: #selector(keyboardFire), input: UIKeyCommand.inputBackspace,
                         modifierFlags: [ .control, .alternate ], discoverabilityTitle: UserText.keyCommandFire)
        ]
        
        guard tabSwitcherController == nil else {
            return alwaysAvailable
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
        return commands
    }

    @objc func keyboardMoveSelectionUp() {
        suggestionTrayController?.keyboardMoveSelectionUp()
    }

    @objc func keyboardMoveSelectionDown() {
        suggestionTrayController?.keyboardMoveSelectionDown()
    }

    @objc func keyboardReload() {
        guard isShortcutEnabled() else { return }
        self.currentTab?.refresh()
    }

    @objc func keyboardZoomIn() {
        guard isShortcutEnabled() else { return }
        currentTab?.zoomIn()
    }

    @objc func keyboardZoomOut() {
        guard isShortcutEnabled() else { return }
        currentTab?.zoomOut()
    }

    @objc func keyboardZoomReset() {
        guard isShortcutEnabled() else { return }
        currentTab?.resetTextZoom()
    }

    @objc func keyboardFindNext() {
        self.findInPageView?.findInPage?.next()
    }

    @objc func keyboardFindPrevious() {
        self.findInPageView?.findInPage?.previous()
    }

    @objc func keyboardLocation() {
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }

        showBars()
        viewCoordinator.omniBar.beginEditing(animated: true)
    }

    @objc func keyboardFire() {
        onQuickFirePressed()
    }

    @objc func keyboardSettings() {
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
        guard isShortcutEnabled() else { return }
        currentTab?.requestFindInPage()
    }
    
    @objc func keyboardEscape() {
        guard tabSwitcherController == nil else { return }
        if #available(iOS 16.0, *) {
            dismissSystemFindNavigator(for: currentTab)
        } else {
            findInPageView?.done()
        }
        hideSuggestionTray()
        performCancel()
    }
    
    @objc func keyboardNewTab() {
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        
        // A New Tab Page often has no tab controller yet, and find-in-page then does nothing.
        if currentTab != nil || featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage) {
            newTab()
        } else {
            keyboardFind()
        }
    }

    @objc func keyboardNewFireTab() {
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        guard fireModeCapability.isFireModeEnabled else { return }

        recordDuckAISessionPendingExit(.fireTabOpened)
        tabManager.setBrowsingMode(.fire, source: .keyCommand)
        performCancel()
        newTab()
    }
    
    @objc func keyboardCloseTab() {
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        
        guard let tab = currentTab else { return }
        closeTab(tab.tabModel)
        showKeyboardOnNewTabPageIfAllowed()
    }
    
    @objc func keyboardNextTab() {
        guard tabSwitcherController == nil else { return }
        
        guard let targetTab = tabManager.currentTabsModel.nextTab else { return }
        let switchesTab = targetTab !== tabManager.currentTabsModel.currentTab
        performCancel()
        selectTab(targetTab)
        if switchesTab {
            showKeyboardOnNewTabPageIfAllowed()
        }
    }

    @objc func keyboardSelectTab(_ command: UIKeyCommand) {
        guard tabSwitcherController == nil, presentedViewController == nil else { return }
        guard isShortcutEnabled() else { return }
        guard let input = command.input, let number = Int(input), (1...9).contains(number),
              let targetTab = tabManager.currentTabsModel.get(tabAt: number - 1) else { return }

        performCancel()
        selectTab(targetTab)
    }
    
    @objc func keyboardPreviousTab() {
        guard tabSwitcherController == nil else { return }
        
        guard let targetTab = tabManager.currentTabsModel.previousTab else { return }
        let switchesTab = targetTab !== tabManager.currentTabsModel.currentTab
        performCancel()
        selectTab(targetTab)
        if switchesTab {
            showKeyboardOnNewTabPageIfAllowed()
        }
    }
    
    @objc func keyboardShowAllTabs() {
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        
        performCancel()
        showTabSwitcher()
    }
    
    @objc func keyboardBrowserForward() {
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }
        
        currentTab?.goForward()
    }
    
    @objc func keyboardBrowserBack() {
        guard tabSwitcherController == nil else { return }
        guard isShortcutEnabled() else { return }

        recordDuckAISessionPendingExit(.backOrClose)
        currentTab?.goBack()
    }
    
    @objc func keyboardPrint() {
        guard isShortcutEnabled() else { return }
        currentTab?.print()
    }

    @objc func keyboardAddBookmark() {
        guard isShortcutEnabled() else { return }
        saveBookmark(favorite: false)
    }

    @objc func keyboardAddFavorite() {
        guard isShortcutEnabled() else { return }
        saveBookmark(favorite: true)
    }
    
    @objc func keyboardNoOperation() { }

    private func isShortcutEnabled() -> Bool {
        !duckAIFireOnboardingFlow.controlsLocked
    }

    private func saveBookmark(favorite: Bool) {
        currentTab?.saveAsBookmark(favorite: favorite, viewModel: menuBookmarksViewModel)
    }

}
