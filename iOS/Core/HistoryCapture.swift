//
//  HistoryCapture.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import History

public class HistoryCapture {

    enum VisitState {
        case added
        case expected
    }

    let historyManager: HistoryManaging
    let tabID: String?
    let fireTab: Bool

    var url: URL?

    public init(historyManager: HistoryManaging, tabID: String?, fireTab: Bool = false) {
        self.historyManager = historyManager
        self.tabID = tabID
        self.fireTab = fireTab
    }

    @MainActor
    public func webViewDidCommit(url: URL) {
        let url = url.urlOrDuckDuckGoCleanQuery
        self.url = url
        historyManager.addVisit(of: url, tabID: tabID, fireTab: fireTab)
    }

    @MainActor
    public func titleDidChange(_ title: String?, forURL url: URL?) {
        guard !fireTab else { return } // Skip for fire tabs
        guard let url = url?.urlOrDuckDuckGoCleanQuery, self.url == url else {
            return
        }

        guard let title, !title.isEmpty else { return }

        historyManager.updateTitleIfNeeded(title: title, url: url)
        historyManager.commitChanges(url: url)
    }

}

extension URL {

    var urlOrDuckDuckGoCleanQuery: URL {
        guard isDuckDuckGoSearch,
                let searchQuery,
                let url = URL.makeSearchURL(query: searchQuery)?.removingInternalSearchParameters() else { return self }
        return url
    }

}
