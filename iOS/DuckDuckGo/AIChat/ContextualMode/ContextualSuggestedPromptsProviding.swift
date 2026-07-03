//
//  ContextualSuggestedPromptsProviding.swift
//  DuckDuckGo
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

protocol ContextualSuggestedPromptsProviding {
    func resolveSuggestions() async
}

struct StubContextualSuggestedPromptsProvider: ContextualSuggestedPromptsProviding {
    private let delay: TimeInterval

    init(delay: TimeInterval = 5.0) {
        self.delay = delay
    }

    func resolveSuggestions() async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
