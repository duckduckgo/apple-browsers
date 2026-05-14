//
//  UTIDismissSnapshot.swift
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

/// Snapshot of the visual state the UTI should display at the start of a dismiss animation,
/// matching what the omnibar will render once the UTI is gone. Applied directly to the view
/// without touching the handler — purely a render override for the duration of the collapse.
struct UTIDismissSnapshot: Equatable {
    /// Text to place in the input — short host for sites, query for SERP, empty otherwise.
    let text: String
    /// Mode whose placeholder copy should appear. The toggle UI itself is left where the user
    /// left it; only the placeholder string flips so it matches the post-dismiss omnibar.
    let placeholderMode: TextEntryMode

    static let empty = UTIDismissSnapshot(text: "", placeholderMode: .search)
}
