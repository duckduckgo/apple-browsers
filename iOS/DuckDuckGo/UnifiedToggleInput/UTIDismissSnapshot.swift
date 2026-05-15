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

/// Render override the UTI applies during the dismiss collapse so it lands on the omnibar's
/// destination state. Does not touch the handler.
struct UTIDismissSnapshot: Equatable {
    /// Short host for sites, query for SERP, empty otherwise.
    let text: String
    /// Placeholder copy to display — toggle UI is left as-is.
    let placeholderMode: TextEntryMode

    static let empty = UTIDismissSnapshot(text: "", placeholderMode: .search)
}
