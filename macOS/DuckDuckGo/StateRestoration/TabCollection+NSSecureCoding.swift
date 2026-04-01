//
//  TabCollection+NSSecureCoding.swift
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

import AppKit
import FeatureFlags
import Foundation

extension TabCollection: NSSecureCoding {

    static var supportsSecureCoding: Bool { true }

    convenience init?(coder decoder: NSCoder) {
        let useSuspendedTabs = NSApp.delegateTyped.featureFlagger.isFeatureOn(.deferredTabWebViewCreation)

        // Remap both class names to TabRestorationData so we can decode archives from any version:
        // - "DuckDuckGo_Privacy_Browser.Tab": written by both old versions (actual Tab objects)
        //   and current version (TabRestorationData encoded under Tab's module-qualified name)
        // - "Tab": kept as a fallback for any intermediate builds that used the short name
        if let unarchiver = decoder as? NSKeyedUnarchiver {
            unarchiver.setClass(TabRestorationData.self, forClassName: "Tab")
            unarchiver.setClass(TabRestorationData.self, forClassName: NSStringFromClass(Tab.self))
        }

        guard let restorationDataArray = decoder.decodeObject(
            of: [NSArray.self, TabRestorationData.self],
            forKey: NSKeyedArchiveRootObjectKey
        ) as? [TabRestorationData] else {
            if let unarchiver = decoder as? NSKeyedUnarchiver {
                unarchiver.setClass(Tab.self, forClassName: "Tab")
                unarchiver.setClass(Tab.self, forClassName: NSStringFromClass(Tab.self))
            }
            return nil
        }

        if let unarchiver = decoder as? NSKeyedUnarchiver {
            unarchiver.setClass(Tab.self, forClassName: "Tab")
            unarchiver.setClass(Tab.self, forClassName: NSStringFromClass(Tab.self))
        }

        if useSuspendedTabs {
            let tabs: [AnyTab] = restorationDataArray.map { .suspended(SuspendedTab(from: $0)) }
            self.init(tabs: tabs)
        } else {
            // Eager restoration: materialize all tabs immediately (pre-feature behavior)
            let tabs: [Tab] = MainActor.assumeMainThread {
                restorationDataArray.map { SuspendedTab(from: $0).materialize() }
            }
            self.init(tabs: tabs)
        }
    }

    func encode(with coder: NSCoder) {
        // Encode TabRestorationData under Tab's module-qualified class name so that:
        // - Old binaries (rollback) can decode it via decodeObject(of: [Tab.self]) which
        //   matches against NSStringFromClass(Tab.self) = "DuckDuckGo_Privacy_Browser.Tab"
        // - New binaries can decode it via the setClass remapping in init?(coder:)
        if let archiver = coder as? NSKeyedArchiver {
            archiver.setClassName(NSStringFromClass(Tab.self), for: TabRestorationData.self)
        }

        let restorationData: [TabRestorationData] = tabs.map { tab in
            switch tab {
            case .loaded(let tab):
                return TabRestorationData(
                    uuid: tab.uuid,
                    content: tab.content,
                    title: tab.title,
                    favicon: tab.favicon,
                    interactionStateData: tab.getActualInteractionStateData(),
                    lastSelectedAt: tab.lastSelectedAt,
                    visitedDomainURLs: tab.localHistory.compactMap(\.identifier),
                    tabSnapshotIdentifier: tab.tabSnapshotIdentifier?.uuidString
                )
            case .suspended(let suspended):
                return TabRestorationData(
                    uuid: suspended.uuid,
                    content: suspended.content,
                    title: suspended.title,
                    favicon: suspended.favicon,
                    interactionStateData: suspended.interactionStateData,
                    lastSelectedAt: suspended.lastSelectedAt,
                    visitedDomainURLs: suspended.visitedDomainURLs,
                    tabSnapshotIdentifier: suspended.tabSnapshotIdentifier
                )
            }
        }

        coder.encode(restorationData, forKey: NSKeyedArchiveRootObjectKey)
    }

}
