//
//  EvalRunnerTests.swift
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

import DuckAIChatCore
import DuckAIChatProviders
import DuckAIEvals
import Foundation
import Testing

@Suite struct EvalRunnerTests {

    private let page = EvalPage(title: "Duck", url: URL(string: "https://en.wikipedia.org/wiki/Duck"),
                                content: "Ducks are waterfowl in the family Anatidae.", language: "en")

    private func stub(_ reply: String = "One two three", failure: ChatError? = nil, wordsPerSecond: Double = 10_000) -> StubProvider {
        StubProvider(configuration: .init(reply: reply, wordsPerSecond: wordsPerSecond, loadTime: .zero, readTime: .zero, failure: failure))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func everyTaskBuildsATurnFromItsInput() throws {
        let cases = [
            EvalCase(id: "s", task: .summarizePage, page: page, selection: nil, languageName: nil),
            EvalCase(id: "t", task: .translatePage, page: page, selection: nil, languageName: "German"),
            EvalCase(id: "ss", task: .summarizeSelection, page: page, selection: "Mallards dabble.", languageName: nil),
            EvalCase(id: "ts", task: .translateSelection, page: page, selection: "Mallards dabble.", languageName: "French"),
            EvalCase(id: "p", task: .suggestPrompts, page: page, selection: nil, languageName: "English")
        ]

        let turns = try cases.map { try $0.turn(conversation: ConversationID(), budget: PromptBudget(contextWindowTokens: 8_192)) }

        #expect(turns[0].input.contains("Ducks are waterfowl"))
        #expect(turns[0].maxOutputTokens == 512)
        #expect(turns[1].instructions.contains("German") || turns[1].input.contains("German"))
        #expect(turns[2].input.contains("Mallards dabble."))
        #expect(!turns[2].input.contains("Ducks are waterfowl"))
        #expect(turns[3].instructions.contains("French") || turns[3].input.contains("French"))
        #expect(turns[4].maxOutputTokens == 80)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func aCaseMissingItsInputThrows() {
        let broken = EvalCase(id: "x", task: .summarizeSelection, page: page, selection: nil, languageName: nil)

        #expect(throws: EvalCaseError.missingInput(caseID: "x")) {
            try broken.turn(conversation: ConversationID(), budget: PromptBudget(contextWindowTokens: 8_192))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func recordsOutputTimingAndStatsPerRun() async {
        let cases = [EvalCase(id: "s", task: .summarizePage, page: page, selection: nil, languageName: nil)]

        let report = await EvalRunner(provider: stub()).run(cases, runs: 2, device: "test", osVersion: "1")

        #expect(report.records.map(\.runIndex) == [0, 1])
        let record = report.records[0]
        #expect(record.caseID == "s")
        #expect(record.providerID == "stub")
        #expect(record.outcome == .completed)
        #expect(record.output == "One two three")
        #expect(record.generatedTokens == 3)
        #expect(record.timeToFirstToken != nil)
        #expect(record.totalTime >= record.timeToFirstToken ?? 0)
        #expect(record.estimatedInputTokens > 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func failuresAndTimeoutsAreRecordsNotThrows() async {
        let cases = [
            EvalCase(id: "bad", task: .summarizeSelection, page: page, selection: nil, languageName: nil),
            EvalCase(id: "s", task: .summarizePage, page: page, selection: nil, languageName: nil)
        ]

        let failing = await EvalRunner(provider: stub("a b c d", failure: .network)).run(cases, device: "test", osVersion: "1")
        #expect(failing.records.map(\.outcome) == [.failed, .failed])

        let slow = await EvalRunner(provider: stub(String(repeating: "w ", count: 500), wordsPerSecond: 20),
                                    timeout: .milliseconds(200)).run([cases[1]], device: "test", osVersion: "1")
        #expect(slow.records.first?.outcome == .timedOut)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func reportRoundTripsThroughJSON() async throws {
        let cases = [EvalCase(id: "s", task: .summarizePage, page: page, selection: nil, languageName: nil)]
        let report = await EvalRunner(provider: stub()).run(cases, device: "test", osVersion: "1", now: Date(timeIntervalSince1970: 0))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(EvalReport.self, from: encoder.encode(report)) == report)
    }
}
