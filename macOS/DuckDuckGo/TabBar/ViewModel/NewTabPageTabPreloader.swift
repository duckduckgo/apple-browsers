//
//  NewTabPageTabPreloader.swift
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

@MainActor
protocol NewTabPageTabPreloading: AnyObject {

    func newTab() -> Tab?
    func reloadTab()

}

final class NewTabPageTabPreloader: NewTabPageTabPreloading {

    private var getViewSize: () -> CGSize?
    private var preloadedTab: Tab?
    private var preloadedTabViewSize: CGSize?

    init(viewSizeProvider: @escaping () -> CGSize?) {
        getViewSize = viewSizeProvider
        loadNewTab()
    }

    private func loadNewTab() {
        let viewSize = getViewSize()
        preloadedTabViewSize = viewSize
        preloadedTab = Tab(
            content: .newtab,
            shouldLoadInBackground: true,
            burnerMode: .regular,
            webViewSize: viewSize ?? CGSize(width: 1024, height: 768))
    }

    func newTab() -> Tab? {
        defer {
            loadNewTab()
        }

        return preloadedTab
    }

    func reloadTab() {
        // Avoid unnecessary reloading
        if let preloadedTabViewSize, preloadedTabViewSize == getViewSize() {
            return
        }

        loadNewTab()
    }

}
