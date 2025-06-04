//
//  AIChatSidebarHosting.swift
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
import AppKit

protocol AIChatSidebarHostingDelegate: AnyObject {
    func sidebarHostDidSelectTab(with tabID: TabIdentifier)
    func sidebarHostDidUpdateTabs(_ currentTabIDs: [TabIdentifier])
}

protocol AIChatSidebarHosting {
    var aiChatSidebarHostingDelegate: AIChatSidebarHostingDelegate? { get set }

    var currentTabID: TabIdentifier? { get }

    var sidebarContainerLeadingConstraint: NSLayoutConstraint? { get }
    var sidebarContainerWidthConstraint: NSLayoutConstraint? { get }

    func embedSidebarViewController(_ vc: NSViewController)
}

extension BrowserTabViewController: AIChatSidebarHosting {

    var currentTabID: TabIdentifier? {
        tabViewModel?.tab.id
    }

    func embedSidebarViewController(_ sidebarViewController: NSViewController) {
        addAndLayoutChild(sidebarViewController, into: sidebarContainer)
    }

}
