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

        // Always decode as TabRestorationData — the archive's actual class is TabRestorationData
        // (even though className is mapped to "Tab"), and NSSecureCoding validates the real class.
        if let unarchiver = decoder as? NSKeyedUnarchiver {
            unarchiver.setClass(TabRestorationData.self, forClassName: "Tab")
        }

        guard let restorationDataArray = decoder.decodeObject(
            of: [NSArray.self, TabRestorationData.self],
            forKey: NSKeyedArchiveRootObjectKey
        ) as? [TabRestorationData] else {
            if let unarchiver = decoder as? NSKeyedUnarchiver {
                unarchiver.setClass(Tab.self, forClassName: "Tab")
            }
            return nil
        }

        if let unarchiver = decoder as? NSKeyedUnarchiver {
            unarchiver.setClass(Tab.self, forClassName: "Tab")
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
        // Convert all AnyTab to TabRestorationData for encoding.
        // Register under "Tab" class name so old binaries can still decode the archive.
        if let archiver = coder as? NSKeyedArchiver {
            archiver.setClassName("Tab", for: TabRestorationData.self)
        }

        let restorationData: [TabRestorationData] = tabs.map { anyTab in
            switch anyTab {
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
