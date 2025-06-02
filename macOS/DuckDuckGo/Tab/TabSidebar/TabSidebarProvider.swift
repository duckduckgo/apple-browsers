//
//  TabSidebarProvider.swift
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

protocol TabSidebarProviding {
    var sidebarWidth: CGFloat { get }

    func tabSidebar(for tab: Tab) -> TabSidebar
    func isShowingSidebar(for tab: Tab) -> Bool
    func handleSidebarDidClose(for tab: Tab)
}

final class TabSidebarProvider: TabSidebarProviding {

    enum Constants {
        static let sidebarWidth: CGFloat = 450
    }

    private var sidebarTabs: NSMapTable = NSMapTable<Tab, TabSidebar>.weakToStrongObjects()

    var sidebarWidth: CGFloat { Constants.sidebarWidth }

    func tabSidebar(for tab: Tab) -> TabSidebar {
        if let tabSidebar = sidebarTabs.object(forKey: tab) {
            return tabSidebar
        } else {
            let tabSidebar = TabSidebar.makeAIChatTabSidebar()
            sidebarTabs.setObject(tabSidebar, forKey: tab)
            return tabSidebar
        }
    }

    func isShowingSidebar(for tab: Tab) -> Bool {
        return sidebarTabs.object(forKey: tab) != nil
    }

    func handleSidebarDidClose(for tab: Tab) {
        if let tabSidebar = sidebarTabs.object(forKey: tab) {
            tabSidebar.sidebarViewController.removeCompletely()
            sidebarTabs.removeObject(forKey: tab)
        }
    }
}
