//
//  AIChatSidebarProvider.swift
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

typealias TabIdentifier = String

protocol AIChatSidebarProviding {
    var sidebarWidth: CGFloat { get }

    func sidebar(for tabID: TabIdentifier) -> TabSidebar
    func isShowingSidebar(for tabID: TabIdentifier) -> Bool

    func handleSidebarDidClose(for tabID: TabIdentifier)
    func cleanUp(for currentTabIDs: [TabIdentifier])
}

final class AIChatSidebarProvider: AIChatSidebarProviding {

    enum Constants {
        static let sidebarWidth: CGFloat = 450
    }

    private var sidebarTabs: [String: TabSidebar] = [:]

    var sidebarWidth: CGFloat { Constants.sidebarWidth }

    func sidebar(for tabID: TabIdentifier) -> TabSidebar {
        if let tabSidebar = sidebarTabs[tabID] {
            return tabSidebar
        } else {
            let tabSidebar = TabSidebar.makeAIChatSidebar()
            sidebarTabs[tabID] = tabSidebar
            return tabSidebar
        }
    }

    func isShowingSidebar(for tabID: TabIdentifier) -> Bool {
        return sidebarTabs[tabID] != nil
    }

    func handleSidebarDidClose(for tabID: TabIdentifier) {
        if let tabSidebar = sidebarTabs[tabID] {
            tabSidebar.sidebarViewController.removeCompletely()
            sidebarTabs.removeValue(forKey: tabID)
        }
    }

    func cleanUp(for currentTabIDs: [TabIdentifier]) {
        let tabIDsForRemoval = Set(sidebarTabs.keys).subtracting(currentTabIDs)

        for tabID in tabIDsForRemoval {
            handleSidebarDidClose(for: tabID)
        }
    }
}

final class TabSidebar {
    var sidebarViewController: NSViewController

    init(sidebarViewController: NSViewController) {
        self.sidebarViewController = sidebarViewController
    }

    static func makeAIChatSidebar() -> TabSidebar {
        return TabSidebar(sidebarViewController: AIChatSidebarViewController())
    }
}
