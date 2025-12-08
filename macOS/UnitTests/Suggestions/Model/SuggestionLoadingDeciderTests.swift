//
//  SuggestionLoadingDeciderTests.swift
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

import Testing
@testable import DuckDuckGo_Privacy_Browser

struct SuggestionLoadingDeciderTests {

    let featureFlagger: MockFeatureFlagger
    let decider: SuggestionLoadingDecider

    init() {
        featureFlagger = MockFeatureFlagger()
        decider = SuggestionLoadingDecider(featureFlagger: featureFlagger)
    }

    static let suggestionLoadingArgs: [(String, Bool, Int)] = [
        ("duckduckgo", true, #line),
        ("duckduckgo/", true, #line),
        ("http://duckduckgo", true, #line),
        ("http://server/h", true, #line),
        ("http://duckduckgo/m", true, #line),
        ("2.14/3", true, #line),
        ("http://duckduckgo/", false, #line),
    ]

    @Test("Suggestion loading deciding for various inputs", arguments: suggestionLoadingArgs)
    func suggestionLoading(input: String, expectation: Bool, line: Int) throws {
        let decision = decider.shouldLoadSuggestions(for: input)
        #expect(decision == expectation, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }
}
