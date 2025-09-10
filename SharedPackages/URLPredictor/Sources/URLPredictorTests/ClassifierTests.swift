//
//  ClassifierTests.swift
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
import Testing
@testable import URLPredictor

struct ClassifierTests {

    @Test("classifies non-URL as search phrase")
    func classifiesInvalidURLAsSearchPhrase() async throws {
        #expect(try Classifier.classify(input: "one two three") == .search(query: "one two three"))
    }

    @Test("classifies single-slash scheme URL as URL")
    func classifiesSingleSlashSchemeURLAsURL() async throws {
        #expect(try Classifier.classify(input: "http:/example.com") == .navigate(url: URL(string: "http://example.com/")!))
    }
}
