//
//  TabSwitcherViewController+KeyCommands.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

extension TabSwitcherViewController {
    
    override var keyCommands: [UIKeyCommand]? {
        let closeCommands: [UIKeyCommand] = [
            UIKeyCommand(title: "", action: #selector(keyboardCloseWindow), input: UIKeyCommand.inputEscape,
                         modifierFlags: [], discoverabilityTitle: UserText.keyCommandClose),

            UIKeyCommand(title: "", action: #selector(keyboardCloseWindowShortcut), input: "w",
                         modifierFlags: [.command], discoverabilityTitle: UserText.keyCommandClose)
        ]

        let newTabCommands: [UIKeyCommand] = [
            UIKeyCommand(title: "", action: #selector(keyboardNewTab), input: "t",
                         modifierFlags: [ .command ], discoverabilityTitle: UserText.keyCommandNewTab),
            UIKeyCommand(title: "", action: #selector(keyboardNewTab), input: "n",
                         modifierFlags: [ .command ], discoverabilityTitle: UserText.keyCommandNewTab)
        ]

        var newFireTabCommands: [UIKeyCommand] = []
        if fireModeCapability.isFireModeEnabled {
            newFireTabCommands.append(
                UIKeyCommand(title: "", action: #selector(keyboardNewFireTab), input: "n",
                             modifierFlags: [.command, .shift], discoverabilityTitle: UserText.keyCommandNewFireTab)
            )
        }

        let selectionCommands: [UIKeyCommand] = [
            UIKeyCommand(title: "", action: #selector(keyboardSelectCurrent), input: UIKeyCommand.inputEnter,
                         modifierFlags: [], discoverabilityTitle: UserText.keyCommandSelect),

            UIKeyCommand(title: "", action: #selector(keyboardMoveSelectionUp), input: UIKeyCommand.inputUpArrow,
                         modifierFlags: [], discoverabilityTitle: UserText.keyCommandPreviousTab),
            UIKeyCommand(title: "", action: #selector(keyboardMoveSelectionDown), input: UIKeyCommand.inputDownArrow,
                         modifierFlags: [], discoverabilityTitle: UserText.keyCommandNextTab),

            UIKeyCommand(title: "", action: #selector(keyboardMoveSelectionUp), input: UIKeyCommand.inputLeftArrow,
                         modifierFlags: [], discoverabilityTitle: UserText.keyCommandPreviousTab),
            UIKeyCommand(title: "", action: #selector(keyboardMoveSelectionDown), input: UIKeyCommand.inputRightArrow,
                         modifierFlags: [], discoverabilityTitle: UserText.keyCommandNextTab),

            UIKeyCommand(title: "", action: #selector(keyboardRemoveTab), input: UIKeyCommand.inputBackspace,
                         modifierFlags: [], discoverabilityTitle: UserText.keyCommandCloseTab)
        ]

        let commands = [closeCommands, newTabCommands, newFireTabCommands, selectionCommands].flatMap { $0 }
        commands.forEach {
            $0.wantsPriorityOverSystemBehavior = true
        }
        return MainMenuSpec(isEnabled: featureFlagger.isIPadMenuBarEnabled(),
                            context: .init(fireModeEnabled: fireModeCapability.isFireModeEnabled))
            .remainingKeyCommands(from: commands)
    }
    
    override func validate(_ command: UICommand) {
        super.validate(command)
        guard featureFlagger.isIPadMenuBarEnabled(), let menuCommand = MainMenuCommand(action: command.action) else { return }
        let availability = switcherMenuAvailability
        if let title = availability.title(for: menuCommand) { command.title = title }
        if availability.isEnabled(menuCommand) && ((presentingViewController as? MainViewController)?.isMenuChatCommandAvailable(command) ?? false) {
            command.attributes.remove(.disabled)
        } else {
            command.attributes.insert(.disabled)
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard featureFlagger.isIPadMenuBarEnabled(), let command = MainMenuCommand(action: action) else {
            return super.canPerformAction(action, withSender: sender)
        }
        guard [.newTab, .newFireTab, .closeTab, .showTabs].contains(command) else {
            return super.canPerformAction(action, withSender: sender)
        }
        return switcherMenuAvailability.isEnabled(command)
    }

    private var switcherMenuAvailability: MenuCommandAvailability {
        var state = MenuCommandAvailability.State(
            shortcutsEnabled: !isProcessingUpdates && ((presentingViewController as? MainViewController)?.isShortcutEnabled() ?? true),
            presentation: presentedViewController == nil ? .tabSwitcher : .blockingModal)
        if let main = presentingViewController as? MainViewController {
            state.aiChatEnabled = main.aiChatSettings.isAIChatEnabled
            state.nativeChatsAvailable = main.menuNativeChatsAvailable
        }
        state.fireModeEnabled = fireModeCapability.isFireModeEnabled
        state.canHideTabs = canDismissOnEmpty || !tabsModel.isEmpty
        return MenuCommandAvailability(state: state)
    }

    @objc func menuOpenDuckAI() {
        guard switcherMenuAvailability.isEnabled(.openDuckAI) else { return }
        (presentingViewController as? MainViewController)?.menuOpenDuckAI()
    }

    @objc func menuNewChat() {
        guard switcherMenuAvailability.isEnabled(.newChat) else { return }
        (presentingViewController as? MainViewController)?.menuNewChat()
    }

    @objc func menuNewVoiceChat() {
        guard switcherMenuAvailability.isEnabled(.newVoiceChat) else { return }
        (presentingViewController as? MainViewController)?.menuNewVoiceChat()
    }

    @objc func menuNewImageChat() {
        guard switcherMenuAvailability.isEnabled(.newImageChat) else { return }
        (presentingViewController as? MainViewController)?.menuNewImageChat()
    }

    @objc func menuDeleteAllChats(_ command: UICommand) {
        guard switcherMenuAvailability.isEnabled(.deleteAllChats) else { return }
        (presentingViewController as? MainViewController)?.menuDeleteAllChats(command)
    }

    @objc func menuOpenRecentChat(_ command: UICommand) {
        guard switcherMenuAvailability.isEnabled(.openRecentChat) else { return }
        (presentingViewController as? MainViewController)?.menuOpenRecentChat(command)
    }

    @objc func menuToggleBookmarks() {
        guard switcherMenuAvailability.isEnabled(.showBookmarks) else { return }
        (presentingViewController as? MainViewController)?.menuToggleBookmarks()
    }

    @objc func menuImportBookmarks() {
        guard switcherMenuAvailability.isEnabled(.importBookmarks) else { return }
        (presentingViewController as? MainViewController)?.menuImportBookmarks()
    }

    @objc func menuExportBookmarks() {
        guard switcherMenuAvailability.isEnabled(.exportBookmarks) else { return }
        (presentingViewController as? MainViewController)?.menuExportBookmarks()
    }

    @objc func menuOpenBookmark(_ command: UICommand) {
        guard switcherMenuAvailability.isEnabled(.openBookmark) else { return }
        (presentingViewController as? MainViewController)?.menuOpenBookmark(command)
    }

    @objc func keyboardCloseTab() {
        guard switcherMenuAvailability.isEnabled(.closeTab) else { return }
        keyboardCloseWindowShortcut()
    }

    @objc func keyboardShowAllTabs() {
        guard switcherMenuAvailability.isEnabled(.showTabs) else { return }
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        dismissIfPossible()
    }

    @objc func keyboardNewTab() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !isProcessingUpdates else { return }
        guard !featureFlagger.isIPadMenuBarEnabled() || switcherMenuAvailability.isEnabled(.newTab) else { return }
        dismissIfPossible(forceDismissOnEmpty: true)
        delegate?.tabSwitcherDidRequestNewTab(tabSwitcher: self)
    }

    @objc func keyboardNewFireTab() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        guard !isProcessingUpdates else { return }
        guard fireModeCapability.isFireModeEnabled else { return }
        guard !featureFlagger.isIPadMenuBarEnabled() || switcherMenuAvailability.isEnabled(.newFireTab) else { return }

        addNewFireTab(source: .keyCommand)
    }
    
    @objc func keyboardCloseWindow() {
        dismissIfPossible()
    }

    @objc func keyboardCloseWindowShortcut() {
        KeyboardShortcutPixel.fireUsed(with: pixelFiring)
        keyboardCloseWindow()
    }
    
    @objc func keyboardSelectCurrent() {
        guard currentSelection != nil else { return }
        dismissIfPossible()
    }
    
    @objc func keyboardRemoveTab() {
        guard let current = currentSelection,
              let tab = tabsModel.get(tabAt: current) else { return }
        
        activePageController.deleteTab(tab: tab)
        if tabsModel.count > 0 {
            currentSelection = max(0, current - 1)
        } else {
            currentSelection = nil
        }
        refreshTitleViews()
        activePageController.reloadData()
    }
    
    @objc func keyboardMoveSelectionUp() {
        guard let current = currentSelection else {
            softSelect(tabAtIndex: tabsModel.count - 1)
            return
        }
        let targetIndex = current - 1 < 0 ? tabsModel.count - 1 : current - 1
        softSelect(tabAtIndex: targetIndex)
    }
    
    @objc func keyboardMoveSelectionDown() {
        guard let current = currentSelection else {
            softSelect(tabAtIndex: 0)
            return
        }
        let targetIndex = current + 1 >= tabsModel.count ? 0 : current + 1
        softSelect(tabAtIndex: targetIndex)
    }
    
    private func softSelect(tabAtIndex index: Int) {
        guard tabsModel.count > 0 else { return }
        
        var paths = [IndexPath(row: index, section: 0)]
        if let oldSelection = currentSelection {
            paths.append(IndexPath(row: oldSelection, section: 0))
        }
        currentSelection = index
        collectionView.reloadItems(at: paths)
        collectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .top, animated: true)
    }
    
}
