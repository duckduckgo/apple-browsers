//
//  ChatContextTests.swift
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
import Testing
@testable import DuckAIChatCore

@Suite struct ChatContextTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func requestNeedsSomethingToActOn() {
        #expect(throws: ChatContextError.requestWithoutSource) {
            try ChatContext(page: nil, selections: [], opening: .request(.summarize))
        }
        #expect(throws: Never.self) {
            try ChatContext(page: nil, selections: [], opening: .prompt("Hi"))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func reasoningPillRoundsUpToAtLeastOneSecond() {
        #expect(Reasoning(text: "", timing: .done(.milliseconds(200))).displaySeconds == 1)
        #expect(Reasoning(text: "", timing: .done(.milliseconds(2_100))).displaySeconds == 3)
        #expect(Reasoning(text: "", timing: .thinking(since: Fixture.time(0))).displaySeconds == nil)
    }
}
