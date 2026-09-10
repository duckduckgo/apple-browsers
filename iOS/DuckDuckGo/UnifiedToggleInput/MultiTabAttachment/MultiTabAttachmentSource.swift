//
//  MultiTabAttachmentSource.swift
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

import AIChat
import Foundation

struct MultiTabAttachmentCandidate: Equatable {
    let tabId: TabUID
    let title: String
    let url: URL
}

/// Reads metadata from the source sheet's browsing mode without materializing tab controllers.
@MainActor
struct MultiTabAttachmentSource {
    let currentTabID: TabUID
    let mode: BrowsingMode
    let tabsProvider: () -> [Tab]

    func candidates() -> [MultiTabAttachmentCandidate] {
        var seen = Set<TabUID>()
        return tabsProvider()
            .enumerated()
            .filter { $0.element.mode == mode }
            .sorted { lhs, rhs in
                if lhs.element.uid == currentTabID { return rhs.element.uid != currentTabID }
                if rhs.element.uid == currentTabID { return false }
                // Temporary use of lastViewedDate. Replace in https://app.asana.com/1/137249556945/project/1208671677432066/task/1218243445214613?focus=true
                // lastViewedDate is reserved for the daily pixel.
                let lhsDate = lhs.element.lastViewedDate ?? .distantPast
                let rhsDate = rhs.element.lastViewedDate ?? .distantPast
                return lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate > rhsDate
            }
            .compactMap { _, tab in
                guard let link = tab.link,
                      !AIChatTabMetadata.shouldExcludeFromTabPicker(link.url),
                      seen.insert(tab.uid).inserted else { return nil }
                return MultiTabAttachmentCandidate(tabId: tab.uid, title: link.displayTitle, url: link.url)
            }
    }
}
