//
//  EvalSetTests.swift
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

import DuckAIEvals
import Testing

@Suite struct EvalSetTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func buildsMatrixForTwoArticles() {
        let cases = EvalSet.make(articles: [("en", "Duck", "Ducks swim."), ("de", "Ente", "Enten schwimmen.")])

        #expect(cases.count == 12)
        #expect(Set(cases.map(\.id)).count == 12)
        let suffixes = ["summarize-page", "summarize-page-short", "summarize-selection",
                        "suggest-prompts", "translate-page", "translate-selection"]
        #expect(cases.map(\.id) == ["en-Duck", "de-Ente"].flatMap { slug in suffixes.map { "\(slug)/\($0)" } })
        #expect(cases.filter { $0.task == .translatePage }.map(\.languageName) == ["German", "English"])
    }
}
