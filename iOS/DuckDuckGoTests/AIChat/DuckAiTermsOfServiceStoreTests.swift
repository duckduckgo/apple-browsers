//
//  DuckAiTermsOfServiceStoreTests.swift
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

import XCTest
@testable import DuckDuckGo

final class DuckAiTermsOfServiceStoreTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var sut: DuckAiTermsOfServiceStore!

    private var suiteName: String { String(describing: self) }

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        sut = DuckAiTermsOfServiceStore(keyValueStore: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        sut = nil
        super.tearDown()
    }

    func testWhenNothingIsRecordedThenTermsAreNotAccepted() {
        XCTAssertFalse(sut.hasAccepted)
    }

    /// Acceptances the web reported before native could accept already live under this key.
    func testWhenTheExistingKeyIsSetThenTermsAreAccepted() {
        userDefaults.set(true, forKey: "aichat.hasAcceptedTermsAndConditions")

        XCTAssertTrue(sut.hasAccepted)
    }

    func testWhenAcceptedInNativeInputThenTermsAreAccepted() {
        sut.recordAcceptedInNativeInput()

        XCTAssertTrue(sut.hasAccepted)
    }

    func testWhenWebReportsAFirstAcceptanceThenItIsNotARepeat() {
        XCTAssertEqual(sut.recordWebReport(), .firstAcceptance)
        XCTAssertTrue(sut.hasAccepted)
    }

    func testWhenWebReportsAgainThenItIsARepeat() {
        sut.recordWebReport()

        XCTAssertEqual(sut.recordWebReport(), .alreadyAccepted)
    }

    /// The web records the acceptance a native send carried, and that report is the same acceptance.
    func testWhenWebReportsAnAcceptanceMadeInNativeInputThenItIsNotARepeat() {
        sut.recordAcceptedInNativeInput()

        XCTAssertEqual(sut.recordWebReport(), .firstAcceptance)
    }

    /// Only the one report the native send owes is excused; a later re-prompt still reads as a repeat.
    func testWhenWebReportsTwiceAfterANativeAcceptanceThenTheSecondIsARepeat() {
        sut.recordAcceptedInNativeInput()
        sut.recordWebReport()

        XCTAssertEqual(sut.recordWebReport(), .alreadyAccepted)
    }

    /// Already accepted on the web, so the native send owes the web no report.
    func testWhenAcceptedInNativeInputAfterTheWebThenTheNextWebReportIsARepeat() {
        sut.recordWebReport()
        sut.recordAcceptedInNativeInput()

        XCTAssertEqual(sut.recordWebReport(), .alreadyAccepted)
    }
}
