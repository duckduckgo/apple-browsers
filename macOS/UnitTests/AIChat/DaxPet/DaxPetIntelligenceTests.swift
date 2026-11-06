//
//  DaxPetIntelligenceTests.swift
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

import AIChat
import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 26, *)
@MainActor
final class DaxPetIntelligenceTests: XCTestCase {

    func testDroppedTextAndLinksAreDescribedForTheModel() throws {
        let link = try XCTUnwrap(URL(string: "https://duckduckgo.com/about"))

        let description = DaxPetOnDeviceIntelligence.describe([.text("Quack"), .link(link)])

        XCTAssertEqual(description, "Text:\nQuack\n\nA link: https://duckduckgo.com/about")
    }

    func testLongTextIsCutToWhatTheModelReads() {
        let description = DaxPetOnDeviceIntelligence.describe([.text(String(repeating: "a", count: 10_000))])

        XCTAssertEqual(description.count, "Text:\n".count + DaxPetOnDeviceIntelligence.contentLimit)
    }

    func testFilesWithoutReadableTextAreDescribedByName() {
        let file = AIChatFileAttachment(data: Data("PK".utf8), fileName: "archive.zip", mimeType: "application/zip")

        XCTAssertEqual(DaxPetOnDeviceIntelligence.describe([.file(file)]), "A file named archive.zip")
    }
}

final class DaxPetPageQuoteTests: XCTestCase {

    private let page = """
        # Hotel Adlon Kempinski Berlin
        Unter den Linden 77, Mitte, 10117 Berlin, Germany
        Situated next to the Brandenburg Gate, this luxurious hotel offers a spa with an indoor pool and elegant rooms. \
        Guests love the location.
        """

    func testTheSentenceTheModelMeantIsFoundEvenWhenItRewordedIt() {
        let fragment = DaxPetPageQuote.fragment(matching: "This luxurious hotel next to the Brandenburg Gate offers a spa with a pool.", in: page)

        XCTAssertEqual(fragment, "Situated next to the Brandenburg Gate, this luxurious")
    }

    func testTheFragmentIsWrittenAsOnThePageWithoutHeadingMarks() {
        XCTAssertEqual(DaxPetPageQuote.fragment(matching: "Hotel Adlon Kempinski Berlin", in: page), "Hotel Adlon Kempinski Berlin")
    }

    func testASentenceThatIsNotOnThePageIsNotFound() {
        XCTAssertNil(DaxPetPageQuote.fragment(matching: "The museum opens at nine every morning.", in: page))
    }

    func testTooFewWordsToTellAreNotFound() {
        XCTAssertNil(DaxPetPageQuote.fragment(matching: "Hotel", in: page))
    }
}

final class DaxPetScreenReferenceTests: XCTestCase {

    func testAQuestionAboutSomeoneOnlyTheScreenShowsLeavesThemUnnamed() {
        XCTAssertTrue(DaxPetScreenReference.leavesSubjectUnnamed("when did they release their last album"))
        XCTAssertTrue(DaxPetScreenReference.leavesSubjectUnnamed("how old is he?"))
        XCTAssertTrue(DaxPetScreenReference.leavesSubjectUnnamed("what does this error mean?"))
        XCTAssertTrue(DaxPetScreenReference.leavesSubjectUnnamed("make it shorter"))
    }

    func testAQuestionThatNamesWhatItIsAboutDoesNot() {
        XCTAssertFalse(DaxPetScreenReference.leavesSubjectUnnamed("when did Iron Maiden release their last album?"))
        XCTAssertFalse(DaxPetScreenReference.leavesSubjectUnnamed("how old is Taylor Swift?"))
        XCTAssertFalse(DaxPetScreenReference.leavesSubjectUnnamed("is Lisbon nice in winter? I want to go there"))
    }

    func testAQuestionThatRefersToNothingDoesNot() {
        XCTAssertFalse(DaxPetScreenReference.leavesSubjectUnnamed("recommend me some jazz"))
        XCTAssertFalse(DaxPetScreenReference.leavesSubjectUnnamed("write an email to my landlord"))
    }
}
