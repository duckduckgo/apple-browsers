//
//  WindowManager+StateRestoration.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Common
import os.log

extension WindowsManager {

    @discardableResult class func restoreState(from coder: NSCoder, includeRegularTabs: Bool, includePinnedTabs: Bool = true, includeWindows: Bool = true) throws -> WindowManagerStateRestoration {
        guard let state = coder.decodeObject(of: WindowManagerStateRestoration.self,
                                             forKey: NSKeyedArchiveRootObjectKey) else {
            throw coder.error ?? NSError(domain: "WindowsManagerStateRestoration", code: -1, userInfo: nil)
        }

        TabsPreferences.shared.migratePinnedTabsSettingIfNecessary(state.applicationPinnedTabs)
        if let pinnedTabsCollection = state.applicationPinnedTabs {
            Application.appDelegate.windowControllersManager.restorePinnedTabs(pinnedTabsCollection)
        }

        if let aiChatSidebarsByTab = state.aiChatSidebarsByTab {
            Application.appDelegate.aiChatSidebarProvider.restoreState(aiChatSidebarsByTab)
        }

        if includeWindows {
            restoreWindows(from: state, includeRegularTabs: includeRegularTabs)
        }

        return state
    }

    private class func restoreWindows(from state: WindowManagerStateRestoration, includeRegularTabs: Bool) {
        for item in state.windows.reversed() {
            if !includeRegularTabs && (item.pinnedTabs?.tabs.isEmpty ?? true) {
                continue
            }

            setUpWindow(from: item, includeRegularTabs: includeRegularTabs)
        }

        if let idx = state.keyWindowIndex {
            state.windows[safe: idx]?.model.setUpLazyLoadingIfNeeded()
        }

        if !state.windows.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private class func setUpWindow(from item: WindowRestorationItem, includeRegularTabs: Bool) {
        let tabCollectionViewModel = includeRegularTabs ? item.model : TabCollectionViewModel(tabCollection: TabCollection())
        guard let window = openNewWindow(with: tabCollectionViewModel, showWindow: !item.isMiniaturized, isMiniaturized: item.isMiniaturized) else { return }
        window.setContentSize(item.frame.size)
        window.setFrameOrigin(item.frame.origin)

        let pinnedTabsManager = (window.windowController as? MainWindowController)?.mainViewController.tabCollectionViewModel.pinnedTabsManager
        if let pinnedTabs = item.pinnedTabs, let pinnedTabsManager, pinnedTabsManager !== Application.appDelegate.pinnedTabsManager {
            pinnedTabsManager.setUp(movingTabsFrom: pinnedTabs)
        }
    }

}

extension WindowControllersManager {

    @MainActor
    func encodeState(with coder: NSCoder) {
        coder.encode(WindowManagerStateRestoration(mainWindowControllers: mainWindowControllers,
                                                   lastKeyMainWindowController: lastKeyMainWindowController,
                                                   applicationPinnedTabs: Application.appDelegate.pinnedTabsManager.tabCollection,
                                                   aiChatSidebarsByTab: Application.appDelegate.aiChatSidebarProvider.sidebarsByTab),
                     forKey: NSKeyedArchiveRootObjectKey)
    }

    func restorePinnedTabs(_ collection: TabCollection) {
        Application.appDelegate.pinnedTabsManager.setUp(movingTabsFrom: collection)
    }

}

@objc(WMState)
final class WindowManagerStateRestoration: NSObject, NSSecureCoding {
    private enum NSSecureCodingKeys {
        static let controllers = "ctrls"
        static let keyWindowIndex = "key_idx"
        static let pinnedTabs = "pinned_tabs"
        static let aiChatSidebarsByTab = "aiChatSidebarsByTab"
    }

    static var supportsSecureCoding: Bool { true }

    let windows: [WindowRestorationItem]
    let keyWindowIndex: Int?
    let applicationPinnedTabs: TabCollection?
    let aiChatSidebarsByTab: AIChatSidebarsByTab?

    init?(coder: NSCoder) {
        guard let restorationArray = coder.decodeObject(of: [NSArray.self, WindowRestorationItem.self],
                                             forKey: NSSecureCodingKeys.controllers) as? [WindowRestorationItem] else {
            Logger.general.error("WindowsManager:initWithCoder: could not decode Restoration Array: \(String(describing: coder.error), privacy: .public)")
            return nil
        }
        self.windows = restorationArray
        self.keyWindowIndex = coder.containsValue(forKey: NSSecureCodingKeys.keyWindowIndex)
            ? coder.decodeInteger(forKey: NSSecureCodingKeys.keyWindowIndex)
            : nil

        self.applicationPinnedTabs = coder.containsValue(forKey: NSSecureCodingKeys.pinnedTabs)
            ? coder.decodeObject(of: TabCollection.self, forKey: NSSecureCodingKeys.pinnedTabs)
            : nil

        self.aiChatSidebarsByTab = coder.containsValue(forKey: NSSecureCodingKeys.aiChatSidebarsByTab)
            ? coder.decodeObject(of: [NSDictionary.self, NSString.self, AIChatSidebar.self], forKey: NSSecureCodingKeys.aiChatSidebarsByTab) as? [String: AIChatSidebar]
            : nil

        super.init()
    }

    @MainActor
    init(mainWindowControllers: [MainWindowController], lastKeyMainWindowController: MainWindowController?, applicationPinnedTabs: TabCollection, aiChatSidebarsByTab: AIChatSidebarsByTab) {
        self.windows = mainWindowControllers
            .filter { $0.window?.isPopUpWindow == false }
            .sorted { (lhs, rhs) in
                let leftIndex = lhs.window?.orderedIndex ?? Int.min
                let rightIndex = rhs.window?.orderedIndex ?? Int.min
                return leftIndex < rightIndex
            }
            .compactMap { WindowRestorationItem(windowController: $0) }
        self.keyWindowIndex = lastKeyMainWindowController.flatMap {
            mainWindowControllers.firstIndex(of: $0)
        }

        self.applicationPinnedTabs = applicationPinnedTabs
        self.aiChatSidebarsByTab = aiChatSidebarsByTab
    }

    func encode(with coder: NSCoder) {
        coder.encode(windows as NSArray, forKey: NSSecureCodingKeys.controllers)
        keyWindowIndex.map(coder.encode(forKey: NSSecureCodingKeys.keyWindowIndex))
        coder.encode(applicationPinnedTabs, forKey: NSSecureCodingKeys.pinnedTabs)
        coder.encode(aiChatSidebarsByTab, forKey: NSSecureCodingKeys.aiChatSidebarsByTab)
    }
}

@objc(WR)
final class WindowRestorationItem: NSObject, NSSecureCoding {
    private enum NSSecureCodingKeys {
        static let frame = "frame"
        static let model = "model"
        static let isMiniaturized = "isMiniaturized"
        static let pinnedTabs = "pinnedTabs"

    }

    let model: TabCollectionViewModel
    let frame: NSRect
    let isMiniaturized: Bool
    let pinnedTabs: TabCollection?

    @MainActor
    init?(windowController: MainWindowController) {
        guard !windowController.mainViewController.tabCollectionViewModel.isBurner else {
            // Don't persist burner windows
            return nil
        }

        self.frame = windowController.window!.frame
        self.model = windowController.mainViewController.tabCollectionViewModel
        self.isMiniaturized = windowController.window!.isMiniaturized
        if windowController.mainViewController.tabCollectionViewModel.pinnedTabsManager !== Application.appDelegate.pinnedTabsManager {
            self.pinnedTabs = windowController.mainViewController.tabCollectionViewModel.pinnedTabsCollection
        } else {
            self.pinnedTabs = nil
        }
    }

    static var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        guard let model = coder.decodeObject(of: TabCollectionViewModel.self, forKey: NSSecureCodingKeys.model) else {
            Logger.general.error("WindowRestoration:initWithCoder: could not decode model object: \(String(describing: coder.error))")
            return nil
        }
        self.model = model
        self.frame = coder.decodeRect(forKey: NSSecureCodingKeys.frame)
        self.isMiniaturized = coder.decodeBool(forKey: NSSecureCodingKeys.isMiniaturized)
        self.pinnedTabs = coder.containsValue(forKey: NSSecureCodingKeys.pinnedTabs)
        ? coder.decodeObject(of: TabCollection.self, forKey: NSSecureCodingKeys.pinnedTabs)
        : nil
    }

    func encode(with coder: NSCoder) {
        coder.encode(frame, forKey: NSSecureCodingKeys.frame)
        coder.encode(model, forKey: NSSecureCodingKeys.model)
        coder.encode(isMiniaturized, forKey: NSSecureCodingKeys.isMiniaturized)
        coder.encode(pinnedTabs, forKey: NSSecureCodingKeys.pinnedTabs)
    }
}
