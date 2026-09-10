//
//  DuckAIPromptOriginProviding.swift
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

import Foundation

/// The browser window a prompt surface is anchored to; `nil` for surfaces without one.
@MainActor
protocol DuckAIPromptOriginProviding: AnyObject {

    var originTabCollectionViewModel: TabCollectionViewModel? { get }

    /// The tab the prompt is "about". Its page-context entry is the one whose `tabId` is stripped,
    /// marking it as the page being discussed.
    var activeTabUUID: String? { get }
}

@MainActor
final class WindowPromptOrigin: DuckAIPromptOriginProviding {

    private let tabCollectionViewModel: TabCollectionViewModel

    init(tabCollectionViewModel: TabCollectionViewModel) {
        self.tabCollectionViewModel = tabCollectionViewModel
    }

    var originTabCollectionViewModel: TabCollectionViewModel? {
        tabCollectionViewModel
    }

    var activeTabUUID: String? {
        tabCollectionViewModel.selectedTabViewModel?.tab.uuid
    }
}
