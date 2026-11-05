//
//  CrossModeResubmitDetectorTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo

final class ResubmitTextMatcherTests: XCTestCase {

    func testCaseSpacingAndPunctuationAreIgnored() {
        XCTAssertTrue(ResubmitTextMatcher.matches("Best pizza in Warsaw?", "  best pizza   in warsaw "))
        XCTAssertTrue(ResubmitTextMatcher.matches("Hi!", "hi"))
    }

    func testShortTextsMustMatchExactly() {
        XCTAssertFalse(ResubmitTextMatcher.matches("hi", "ii"))
        XCTAssertFalse(ResubmitTextMatcher.matches("cat", "car"))
    }

    func testFourToSevenCharacterTextsAllowOneTypo() {
        XCTAssertTrue(ResubmitTextMatcher.matches("pizza", "piza"))
        XCTAssertTrue(ResubmitTextMatcher.matches("weather", "wether"))
        XCTAssertFalse(ResubmitTextMatcher.matches("weather", "wethr"))
        XCTAssertFalse(ResubmitTextMatcher.matches("cheese", "choose"))
    }

    func testLongerTextsAllowTwoTypos() {
        XCTAssertTrue(ResubmitTextMatcher.matches("restaurant", "resturant"))
        XCTAssertTrue(ResubmitTextMatcher.matches("best pizza in warsaw", "best piza in warsw"))
        XCTAssertFalse(ResubmitTextMatcher.matches("best pizza in warsaw", "best pasta in warsaw"))
    }

    func testLongTextsMatchOnlyWhenIdentical() {
        let pasted = String(repeating: "stack trace line ", count: 100)
        XCTAssertTrue(ResubmitTextMatcher.matches(pasted, pasted.uppercased()))
        XCTAssertFalse(ResubmitTextMatcher.matches(pasted, pasted + "x"))
    }

    func testEmptyTextNeverMatches() {
        XCTAssertFalse(ResubmitTextMatcher.matches("", ""))
        XCTAssertFalse(ResubmitTextMatcher.matches("?!", "..."))
    }
}

final class CrossModeResubmitDelayBucketTests: XCTestCase {

    func testElapsedTimeMapsToFifteenSecondBucketsUpToOneMinute() {
        let cases: [(TimeInterval, CrossModeResubmitDetector.DelayBucket?)] = [
            (0, .upTo15s), (15, .upTo15s), (15.5, .upTo30s), (30, .upTo30s),
            (31, .upTo45s), (45, .upTo45s), (46, .upTo60s), (60, .upTo60s), (60.5, nil)
        ]
        for (elapsed, bucket) in cases {
            XCTAssertEqual(CrossModeResubmitDetector.DelayBucket(elapsed: elapsed), bucket, "elapsed \(elapsed)")
        }
    }
}

@MainActor
final class CrossModeResubmitDetectorTests: XCTestCase {

    private var now: TimeInterval = 1_000

    private func makeDetector() -> CrossModeResubmitDetector {
        CrossModeResubmitDetector(uptime: { [unowned self] in now })
    }

    @discardableResult
    private func submit(_ text: String, _ mode: TextEntryMode, to detector: CrossModeResubmitDetector,
                        canStartComparison: Bool = true) -> CrossModeResubmitDetector.DelayBucket? {
        detector.registerSubmission(text, mode: mode, canStartComparison: canStartComparison)
    }

    func testWhenPromptIsResentAsSearchThenReportsDelayOnce() {
        let detector = makeDetector()
        XCTAssertNil(submit("Weather Warsaw", .aiChat, to: detector))
        now += 20

        XCTAssertEqual(submit("weather warsaw", .search, to: detector), .upTo30s)
        XCTAssertNil(submit("weather warsaw", .aiChat, to: detector))
    }

    func testWhenSearchIsResentAsPromptThenReportsDelay() {
        let detector = makeDetector()
        submit("weather warsaw", .search, to: detector)
        now += 5

        XCTAssertEqual(submit("weather warsaw", .aiChat, to: detector), .upTo15s)
    }

    func testWhenSameModeIsUsedAgainThenNoResubmit() {
        let detector = makeDetector()
        submit("weather warsaw", .aiChat, to: detector)

        XCTAssertNil(submit("weather warsaw", .aiChat, to: detector))
    }

    func testWhenTextDiffersThenNoResubmit() {
        let detector = makeDetector()
        submit("weather warsaw", .aiChat, to: detector)

        XCTAssertNil(submit("pizza near me", .search, to: detector))
    }

    func testWhenMoreThanAMinutePassesThenNoResubmit() {
        let detector = makeDetector()
        submit("weather warsaw", .aiChat, to: detector)
        now += 61

        XCTAssertNil(submit("weather warsaw", .search, to: detector))
    }

    func testWhenClearedThenNoResubmit() {
        let detector = makeDetector()
        submit("weather warsaw", .aiChat, to: detector)
        detector.clear()

        XCTAssertNil(submit("weather warsaw", .search, to: detector))
    }

    func testWhenSubmissionCannotStartAComparisonThenItIsNotRecorded() {
        let detector = makeDetector()
        submit("weather warsaw", .aiChat, to: detector, canStartComparison: false)

        XCTAssertNil(submit("weather warsaw", .search, to: detector))
    }

    func testWhenFollowUpCannotStartAComparisonThenItStillMatches() {
        let detector = makeDetector()
        submit("weather warsaw", .aiChat, to: detector)

        XCTAssertEqual(submit("weather warsaw", .search, to: detector, canStartComparison: false), .upTo15s)
    }

    func testWhenSubmissionHasNoTextThenPendingOriginIsKept() {
        let detector = makeDetector()
        submit("best pizza warsaw", .search, to: detector)
        submit("", .aiChat, to: detector)
        now += 20

        XCTAssertEqual(submit("best pizza warsaw", .aiChat, to: detector), .upTo30s)
    }
}
