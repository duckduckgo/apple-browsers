//
//  ScoreTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import XCTest

@testable import Suggestions

final class ScoreTests: XCTestCase {

    func testWhenFirstCharacterIsNonAlphaNumeric_ThenStillScored() {
        assertHasNonZeroScore("\"Cats and Dogs\"", "\"")
        assertHasNonZeroScore("\"Cats and Dogs\"", "\"C")
        assertHasNonZeroScore("\"Cats and Dogs\"", "\"Cats")
        assertHasNonZeroScore("\"Cats and Dogs\"", "and")
        assertHasNonZeroScore("\"Cats and Dogs\"", "\"Cats Dogs")
        assertHasNonZeroScore("\"Cats and Dogs\"", "Dogs Cats")
        assertHasNonZeroScore("\"Cats and Dogs\"", "Dogs \"Cats")
        assertHasNonZeroScore("«Рукописи не горят»: первый :", "«")
    }

    func testWhenTitleStartsWithQuotes_ThenStillScoresHighlyForWordsAtStart() {

        assertHasNonZeroScore("\"Cats and Dogs\"", "Cats")
        assertHasNonZeroScore("«Рукописи не горят»: первый замысел «Мастера и Маргариты». Лекция из курса «Мир Булгакова». АУДИО - YouTube", "Р")
        assertHasNonZeroScore("«Рукописи не горят»: первый замысел «Мастера и Маргариты». Лекция из курса «Мир Булгакова». АУДИО - YouTube", "Ру")
        assertHasNonZeroScore("«Рукописи не горят»: первый замысел «Мастера и Маргариты». Лекция из курса «Мир Булгакова». АУДИО - YouTube", "Рукописи")
    }

    func assertHasNonZeroScore(_ title: String, _ query: String) {
        let score = Score(title: title,
                           url: URL(string: "https://www.testcase.com/notroot")!,
                           visitCount: 0,
                           query: query)
        XCTAssertTrue(score > 0, "\(score)")
    }

    func testWhenQueryIsJustWhitespaces_ThenTokensAreEmpty() {
        let query = "  \t\n\t\t \t \t  \n\n\n "
        let tokens = query.tokenized()

        XCTAssertEqual(tokens.count, 0)
    }

    func testWhenQueryContainsTabsOrNewlines_ThenResultIsTheSameAsIfThereAreSpaces() {
        let spaceQuery = "testing query tokens"
        let tabQuery = "testing\tquery\ttokens"
        let newlineQuery = "testing\nquery\ntokens"
        let spaceTokens = spaceQuery.tokenized()
        let tabTokens = tabQuery.tokenized()
        let newlineTokens = newlineQuery.tokenized()

        XCTAssertEqual(spaceTokens, ["testing", "query", "tokens"])
        XCTAssertEqual(spaceTokens, tabTokens)
        XCTAssertEqual(spaceTokens, newlineTokens)
    }

    func testWhenURLMatchesWithQuery_ThenScoreIsIncreased() {
        let query = "testcase.com/no"
        let score1 = Score(title: "Test case website",
                           url: URL(string: "https://www.testcase.com/notroot")!,
                           visitCount: 100,
                           query: query)

        XCTAssert(score1 > 0)
    }

    func testWhenTitleMatchesFromTheBeginning_ThenScoreIsIncreased() {
        let query = "test"
        let score1 = Score(title: "Test case website",
                           url: URL(string: "https://www.website.com")!,
                           visitCount: 100,
                           query: query)

        let score2 = Score(title: "Case test website 2",
                           url: URL(string: "https://www.website2.com")!,
                           visitCount: 100,
                           query: query)

        XCTAssert(score1 > score2)
    }

    func testWhenDomainMatchesFromTheBeginning_ThenScoreIsIncreased() {
        let query = "test"
        let score1 = Score(title: "Website",
                           url: URL(string: "https://www.test.com")!,
                           visitCount: 100,
                           query: query)

        let score2 = Score(title: "Website 2",
                           url: URL(string: "https://www.websitetest.com")!,
                           visitCount: 100,
                           query: query)

        XCTAssert(score1 > score2)
    }

    func testWhenThereIsMoreVisitCount_ThenScoreIsIncreased() {
        let query = "website"
        let score1 = Score(title: "Website",
                           url: URL(string: "https://www.website.com")!,
                           visitCount: 100,
                           query: query)

        let score2 = Score(title: "Website 2",
                           url: URL(string: "https://www.website2.com")!,
                           visitCount: 101,
                           query: query)

        XCTAssert(score1 < score2)
    }

}
private func Score(title: String, url: URL, visitCount: Int, query: String) -> Int {
    return ScoringService.score(title: title,
                                url: url,
                                visitCount: visitCount,
                                lowercasedQuery: query.lowercased())
}
