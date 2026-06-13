//
//  SuggestionHistoryDeletion.swift
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

import Foundation
import Core

/// Deletes a browsing-history entry shown as a suggestion and fires the standard autocomplete
/// delete pixels. Shared by the Search and Duck.ai suggestion delete paths so the pixels stay in sync.
@MainActor
enum SuggestionHistoryDeletion {
    static func delete(_ url: URL, using historyManager: HistoryManaging) async {
        await historyManager.deleteHistoryForURL(url)
        Pixel.fire(pixel: .autocompleteDeleteHistoryEntry)
        DailyPixel.fireDaily(.autocompleteDeleteHistoryEntryDaily)
    }
}
