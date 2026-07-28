//
//  DuckAIPromptDraftSource.swift
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
import Foundation

/// Supplies the prompt draft store currently in effect, and republishes it when it changes.
@MainActor
protocol DuckAIPromptDraftSource: AnyObject {

    var currentDraftStore: DuckAIPromptDraftStoring? { get }

    /// Emits the effective store on subscription and whenever it changes — a browser tab switch
    /// for the address bar, never for the Prompt Bar.
    var currentDraftStorePublisher: AnyPublisher<DuckAIPromptDraftStoring?, Never> { get }
}

/// Address-bar source: the draft belongs to the window's selected tab, so it survives tab switches.
@MainActor
final class TabPromptDraftSource: DuckAIPromptDraftSource {

    private let tabCollectionViewModel: TabCollectionViewModel

    init(tabCollectionViewModel: TabCollectionViewModel) {
        self.tabCollectionViewModel = tabCollectionViewModel
    }

    var currentDraftStore: DuckAIPromptDraftStoring? {
        tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
    }

    /// Maps the emitted tab rather than re-reading `selectedTabViewModel`: `@Published` fires in
    /// `willSet`, so the stored property still holds the outgoing tab during the emission.
    var currentDraftStorePublisher: AnyPublisher<DuckAIPromptDraftStoring?, Never> {
        tabCollectionViewModel.$selectedTabViewModel
            .map { $0?.addressBarSharedTextState as DuckAIPromptDraftStoring? }
            .eraseToAnyPublisher()
    }
}

/// Prompt Bar source: one store for the life of the surface, cleared on dismissal.
@MainActor
final class StaticPromptDraftSource: DuckAIPromptDraftSource {

    let store: DuckAIPromptDraftStoring

    init(store: DuckAIPromptDraftStoring) {
        self.store = store
    }

    var currentDraftStore: DuckAIPromptDraftStoring? {
        store
    }

    var currentDraftStorePublisher: AnyPublisher<DuckAIPromptDraftStoring?, Never> {
        Just(store).eraseToAnyPublisher()
    }
}
