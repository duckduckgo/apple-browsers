//
//  NewTabPageControllerStore.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Combine
import UIKit

/// Retains loaded redesigned pages across tab switches, including their view and scroll state.
@MainActor
final class NewTabPageControllerStore {

    private let builder: NewTabPageBuilder
    private let pages = NSMapTable<Tab, RedesignedNewTabPageViewController>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
    private var memoryWarningCancellable: AnyCancellable?

    init(builder: NewTabPageBuilder, notificationCenter: NotificationCenter = .default) {
        self.builder = builder
        memoryWarningCancellable = notificationCenter.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.removeDetachedPages()
            }
    }

    func page(for tab: Tab,
              isNewTab: Bool,
              openedAfterIdle: Bool,
              daxDialogFactory: any NewTabDaxDialogProviding) -> any NewTabPage {
        if !isNewTab, builder.usesRedesignedPage(for: tab), let page = pages.object(forKey: tab) {
            return page
        }

        let page = builder.makeNewTabPage(tab: tab,
                                          openedAfterIdle: openedAfterIdle,
                                          daxDialogFactory: daxDialogFactory)
        pages.setObject(page as? RedesignedNewTabPageViewController, forKey: tab)
        return page
    }

    func removePage(for tab: Tab) {
        pages.removeObject(forKey: tab)
    }

    func removePages(for tabs: [Tab]) {
        tabs.forEach { removePage(for: $0) }
    }

    private func removeDetachedPages() {
        let tabs = pages.keyEnumerator().allObjects.compactMap { $0 as? Tab }
        for tab in tabs where pages.object(forKey: tab)?.parent == nil {
            removePage(for: tab)
        }
    }
}
