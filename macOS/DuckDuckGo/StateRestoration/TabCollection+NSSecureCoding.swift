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
import Foundation

extension TabCollection: NSSecureCoding {

    static var supportsSecureCoding: Bool { true }

    convenience init?(coder decoder: NSCoder) {
        // Remap Tab's module-qualified class name to TabRestorationData so we can decode
        // archives from old versions (actual Tab objects) and current version (TabRestorationData
        // encoded under Tab's class name for rollback compatibility).
        if let unarchiver = decoder as? NSKeyedUnarchiver {
            unarchiver.setClass(TabRestorationData.self, forClassName: NSStringFromClass(Tab.self))
        }

        guard let restorationDataArray = decoder.decodeObject(
            of: [NSArray.self, TabRestorationData.self],
            forKey: NSKeyedArchiveRootObjectKey
        ) as? [TabRestorationData] else {
            if let unarchiver = decoder as? NSKeyedUnarchiver {
                unarchiver.setClass(Tab.self, forClassName: NSStringFromClass(Tab.self))
            }
            return nil
        }

        if let unarchiver = decoder as? NSKeyedUnarchiver {
            unarchiver.setClass(Tab.self, forClassName: NSStringFromClass(Tab.self))
        }

        let tabs: [AnyTab] = restorationDataArray.map { .unloaded(UnloadedTab(from: $0)) }
        self.init(tabs: tabs)
    }

    func encode(with coder: NSCoder) {
        // Encode TabRestorationData under Tab's module-qualified class name so that:
        // - Old binaries (rollback) can decode it via decodeObject(of: [Tab.self]) which
        //   matches against NSStringFromClass(Tab.self) = "DuckDuckGo_Privacy_Browser.Tab"
        // - New binaries can decode it via the setClass remapping in init?(coder:)
        if let archiver = coder as? NSKeyedArchiver {
            archiver.setClassName(NSStringFromClass(Tab.self), for: TabRestorationData.self)
        }

        let restorationData: [TabRestorationData] = tabs.compactMap { tab in
            switch tab {
            case .loaded(let tab):
                guard tab.webView.configuration.websiteDataStore.isPersistent else { return nil }
                return tab.makeRestorationData()
            case .unloaded(let unloaded):
                guard unloaded.isPersistent else { return nil }
                return TabRestorationData(
                    uuid: unloaded.uuid,
                    content: unloaded.content,
                    title: unloaded.title,
                    favicon: unloaded.favicon,
                    interactionStateData: unloaded.interactionStateData,
                    lastSelectedAt: unloaded.lastSelectedAt,
                    localHistoryIDs: unloaded.localHistoryIDs,
                    tabSnapshotIdentifier: unloaded.tabSnapshotIdentifier
                )
            }
        }

        coder.encode(restorationData, forKey: NSKeyedArchiveRootObjectKey)
    }

}
