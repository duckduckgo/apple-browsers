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

    func sidebar(for tabID: TabIdentifier) -> AIChatSidebar
    func isShowingSidebar(for tabID: TabIdentifier) -> Bool

    func handleSidebarDidClose(for tabID: TabIdentifier)
    func cleanUp(for currentTabIDs: [TabIdentifier])
}

final class AIChatSidebarProvider: AIChatSidebarProviding {

    enum Constants {
        static let sidebarWidth: CGFloat = 450
    }

    private var sidebarsByTabIDs: [TabIdentifier: AIChatSidebar] = [:]

    var sidebarWidth: CGFloat { Constants.sidebarWidth }

    func sidebar(for tabID: TabIdentifier) -> AIChatSidebar {
        if let sidebar = sidebarsByTabIDs[tabID] {
            return sidebar
        } else {
            let sidebar = AIChatSidebar()
            sidebarsByTabIDs[tabID] = sidebar
            return sidebar
        }
    }

    func isShowingSidebar(for tabID: TabIdentifier) -> Bool {
        return sidebarsByTabIDs[tabID] != nil
    }

    func handleSidebarDidClose(for tabID: TabIdentifier) {
        if let tabSidebar = sidebarsByTabIDs[tabID] {
            tabSidebar.sidebarViewController.removeCompletely()
            sidebarsByTabIDs.removeValue(forKey: tabID)
        }
    }

    func cleanUp(for currentTabIDs: [TabIdentifier]) {
        let tabIDsForRemoval = Set(sidebarsByTabIDs.keys).subtracting(currentTabIDs)

        for tabID in tabIDsForRemoval {
            handleSidebarDidClose(for: tabID)
        }
    }
}
