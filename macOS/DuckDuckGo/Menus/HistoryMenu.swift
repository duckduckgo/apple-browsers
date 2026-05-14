//
//  HistoryMenu.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Cocoa
import Combine
import Common
import FeatureFlags
import History
import os.log
import PrivacyConfig

final class HistoryMenu: NSMenu {

    enum Location: Equatable {
        case mainMenu, moreOptionsMenu
    }

    let backMenuItem = NSMenuItem(title: UserText.navigateBack, action: #selector(MainViewController.back), keyEquivalent: "[")
    let forwardMenuItem = NSMenuItem(title: UserText.navigateForward, action: #selector(MainViewController.forward), keyEquivalent: "]")

    private let recentlyClosedMenuItem = NSMenuItem(title: UserText.mainMenuHistoryRecentlyClosed)
    private let reopenLastClosedMenuItem = NSMenuItem(title: UserText.reopenLastClosedTab, action: #selector(AppDelegate.reopenLastClosedTab))
    private let reopenAllWindowsFromLastSessionMenuItem = NSMenuItem(title: UserText.mainMenuHistoryReopenAllWindowsFromLastSession,
                                                                     action: #selector(AppDelegate.reopenAllWindowsFromLastSession))
    private lazy var showHistoryMenuItem = NSMenuItem(
        title: UserText.mainMenuHistoryShowAllHistory,
        action: #selector(MainViewController.showHistory),
        keyEquivalent: "y",
        representedObject: location
    )
    private let showHistorySeparator = NSMenuItem.separator()
    private let clearAllHistoryMenuItem = NSMenuItem(title: UserText.mainMenuHistoryDeleteAllHistory,
                                                     action: #selector(AppDelegate.clearAllHistory),
                                                     keyEquivalent: [.command, .shift, .backspace])
        .withAccessibilityIdentifier("HistoryMenu.clearAllHistory")
    private let clearAllHistorySeparator = NSMenuItem.separator()

    private let historyGroupingProvider: HistoryGroupingProvider
    private let recentlyClosedCoordinator: RecentlyClosedCoordinating
    private let featureFlagger: FeatureFlagger
    @MainActor
    private let reopenMenuItemKeyEquivalentManager = ReopenMenuItemKeyEquivalentManager()
    private let location: Location

    @MainActor
    convenience init(location: Location = .mainMenu, historyGroupingDataSource: HistoryGroupingDataSource, recentlyClosedCoordinator: RecentlyClosedCoordinating, featureFlagger: FeatureFlagger) {
        self.init(
            location: location,
            historyGroupingProvider: .init(dataSource: historyGroupingDataSource),
            recentlyClosedCoordinator: recentlyClosedCoordinator,
            featureFlagger: featureFlagger
        )
    }

    @MainActor
    init(location: Location = .mainMenu, historyGroupingProvider: HistoryGroupingProvider, recentlyClosedCoordinator: RecentlyClosedCoordinating, featureFlagger: FeatureFlagger) {
        self.location = location
        self.historyGroupingProvider = historyGroupingProvider
        self.recentlyClosedCoordinator = recentlyClosedCoordinator
        self.featureFlagger = featureFlagger

        super.init(title: UserText.mainMenuHistory)

        self.buildItems {
            switch location {
            case .mainMenu:
                backMenuItem
                forwardMenuItem
            case .moreOptionsMenu:
                showHistoryMenuItem
            }

            NSMenuItem.separator()

            reopenLastClosedMenuItem
            recentlyClosedMenuItem
            reopenAllWindowsFromLastSessionMenuItem
            NSMenuItem.separator()

            if location == .mainMenu {
                showHistorySeparator
                showHistoryMenuItem
            }
            clearAllHistorySeparator
            clearAllHistoryMenuItem
        }

        reopenMenuItemKeyEquivalentManager.reopenLastClosedMenuItem = reopenLastClosedMenuItem
        reopenAllWindowsFromLastSessionMenuItem.setAccessibilityIdentifier("HistoryMenu.reopenAllWindowsFromLastSessionMenuItem")
        reopenMenuItemKeyEquivalentManager.lastSessionMenuItem = reopenAllWindowsFromLastSessionMenuItem
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    override func update() {
        super.update()

        updateRecentlyClosedMenu()
        updateReopenLastClosedMenuItem()

        clearOldVariableMenuItems()
        addRecentlyVisited()
        addClearAllAndShowHistoryOnTheBottom()
    }

    private func clearOldVariableMenuItems() {
        items.removeAll { menuItem in
            recentlyVisitedMenuItems.contains(menuItem) ||
            menuItem == clearAllHistoryMenuItem ||
            (menuItem == showHistoryMenuItem && location == .mainMenu)
        }
    }

    // MARK: - Last Closed & Recently Closed

    @MainActor
    private func updateReopenLastClosedMenuItem() {
        switch recentlyClosedCoordinator.cache.last {
        case is RecentlyClosedWindow:
            reopenLastClosedMenuItem.title = UserText.reopenLastClosedWindow
            reopenLastClosedMenuItem.setAccessibilityIdentifier("HistoryMenu.reopenLastClosedWindow")
        default:
            reopenLastClosedMenuItem.title = UserText.reopenLastClosedTab
            reopenLastClosedMenuItem.setAccessibilityIdentifier("HistoryMenu.reopenLastClosedTab")
        }

    }

    @MainActor
    private func updateRecentlyClosedMenu() {
        let recentlyClosedMenu = RecentlyClosedMenu(recentlyClosedCoordinator: recentlyClosedCoordinator)
        recentlyClosedMenuItem.submenu = recentlyClosedMenu
        recentlyClosedMenuItem.isEnabled = !recentlyClosedMenu.items.isEmpty
    }

    // MARK: - Recently Visited

    var recentlyVisitedHeaderMenuItem: NSMenuItem {
        let item = NSMenuItem(title: UserText.recentlyVisitedMenuSection)
        item.isEnabled = false
        item.setAccessibilityIdentifier("HistoryMenu.recentlyVisitedHeaderMenuItem")
        return item
    }

    private var recentlyVisitedMenuItems = [NSMenuItem]()

    @MainActor
    private func addRecentlyVisited() {
        recentlyVisitedMenuItems = [recentlyVisitedHeaderMenuItem]
        let recentVisits = historyGroupingProvider.getRecentVisits(maxCount: 12)
        for (index, visit) in zip(
            recentVisits.indices, recentVisits
        ) {
            let visitMenuItem = VisitMenuItem(visitViewModel: VisitViewModel(visit: visit))
            visitMenuItem.setAccessibilityIdentifier("HistoryMenu.recentlyVisitedMenuItem.\(index)")
            recentlyVisitedMenuItems.append(visitMenuItem)
        }
        for recentlyVisitedMenuItem in recentlyVisitedMenuItems {
            addItem(recentlyVisitedMenuItem)
        }
    }

    // MARK: - Clear All History

    private func addClearAllAndShowHistoryOnTheBottom() {
        if location == .mainMenu {
            if showHistorySeparator.menu != nil {
                removeItem(showHistorySeparator)
            }
            addItem(showHistorySeparator)
            addItem(showHistoryMenuItem)
        }
        if clearAllHistorySeparator.menu != nil {
            removeItem(clearAllHistorySeparator)
        }
        addItem(clearAllHistorySeparator)
        addItem(clearAllHistoryMenuItem)
    }
}

extension HistoryMenu {

    /**
     * This class manages the shortcut assignment to either of the
     * "Reopen Last Closed Tab" or "Reopen All Windows From Last Session"
     * menu items.
     */
    final class ReopenMenuItemKeyEquivalentManager {
        weak var reopenLastClosedMenuItem: NSMenuItem?
        weak var lastWindowMenuItem: NSMenuItem?
        weak var lastSessionMenuItem: NSMenuItem?

        enum Const {
            static let keyEquivalent = "T"
            static let modifierMask = NSEvent.ModifierFlags.command
        }

        init(isInInitialStatePublisher: Published<Bool>.Publisher, canRestoreLastSessionState: @escaping @autoclosure () -> Bool) {
            self.canRestoreLastSessionState = canRestoreLastSessionState
            self.isInInitialStateCancellable = isInInitialStatePublisher
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] isInInitialState in
                    self?.updateKeyEquivalent(isInInitialState)
                }
        }

        @MainActor
        convenience init() {
            self.init(isInInitialStatePublisher: Application.appDelegate.windowControllersManager.$isInInitialState, canRestoreLastSessionState: NSApp.canRestoreLastSessionState)
        }

        private weak var currentlyAssignedMenuItem: NSMenuItem?
        private var isInInitialStateCancellable: AnyCancellable?
        private var canRestoreLastSessionState: () -> Bool

        private func updateKeyEquivalent(_ isInInitialState: Bool) {
            if isInInitialState && canRestoreLastSessionState() {
                assignKeyEquivalent(to: lastSessionMenuItem)
            } else {
                assignKeyEquivalent(to: reopenLastClosedMenuItem)
            }
        }

        func assignKeyEquivalent(to menuItem: NSMenuItem?) {
            currentlyAssignedMenuItem?.keyEquivalent = ""
            currentlyAssignedMenuItem?.keyEquivalentModifierMask = []
            menuItem?.keyEquivalent = Const.keyEquivalent
            menuItem?.keyEquivalentModifierMask = Const.modifierMask
            currentlyAssignedMenuItem = menuItem
        }
    }

}

private extension NSApplication {

    var canRestoreLastSessionState: Bool {
        delegateTyped.stateRestorationManager?.canRestoreLastSessionState ?? false
    }

}
