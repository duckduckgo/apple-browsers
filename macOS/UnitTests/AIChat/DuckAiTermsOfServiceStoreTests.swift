//
//  DuckAiTermsOfServiceStoreTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class DuckAiTermsOfServiceStoreTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var notificationCenter: NotificationCenter!
    private var sut: DuckAiTermsOfServiceStore!

    private var suiteName: String { String(describing: self) }

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        notificationCenter = NotificationCenter()
        sut = DuckAiTermsOfServiceStore(keyValueStore: userDefaults, notificationCenter: notificationCenter)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        notificationCenter = nil
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

    /// The same key and defaults `AIChatPreferencesStorage` reads and writes.
    func testWhenAcceptedThenPreferencesStorageReadsItToo() {
        sut.recordAcceptedInNativeInput()

        XCTAssertTrue(DefaultAIChatPreferencesStorage(userDefaults: userDefaults).hasAcceptedTermsAndConditions)
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

    func testWhenAcceptedFromExistingChatsThenTermsAreAccepted() {
        sut.recordAcceptedFromExistingChats()

        XCTAssertTrue(sut.hasAccepted)
    }

    /// A page that loaded before synced chats arrived can still show its card, and accepting there is the same acceptance.
    func testWhenWebReportsAfterAnAcceptanceFromExistingChatsThenItIsNotARepeat() {
        sut.recordAcceptedFromExistingChats()

        XCTAssertEqual(sut.recordWebReport(), .firstAcceptance)
    }

    /// Already accepted on the web, so the native send owes the web no report.
    func testWhenAcceptedInNativeInputAfterTheWebThenTheNextWebReportIsARepeat() {
        sut.recordWebReport()
        sut.recordAcceptedInNativeInput()

        XCTAssertEqual(sut.recordWebReport(), .alreadyAccepted)
    }

    func testWhenResetForDebuggingThenTermsAreNotAccepted() {
        sut.recordAcceptedInNativeInput()

        sut.resetForDebugging()

        XCTAssertFalse(sut.hasAccepted)
        XCTAssertEqual(sut.recordWebReport(), .firstAcceptance)
    }

    // MARK: - Change notifications

    func testWhenAcceptedInNativeInputThenChangeIsPosted() {
        expectChange()

        sut.recordAcceptedInNativeInput()

        waitForExpectations(timeout: 1)
    }

    func testWhenAcceptedFromExistingChatsThenChangeIsPosted() {
        expectChange()

        sut.recordAcceptedFromExistingChats()

        waitForExpectations(timeout: 1)
    }

    func testWhenAcceptedAgainThenNoChangeIsPosted() {
        sut.recordAcceptedInNativeInput()
        expectNoChange()

        sut.recordAcceptedInNativeInput()

        waitForExpectations(timeout: 0.1)
    }

    func testWhenWebReportsAFirstAcceptanceThenChangeIsPosted() {
        expectChange()

        sut.recordWebReport()

        waitForExpectations(timeout: 1)
    }

    func testWhenWebReportsAgainThenNoChangeIsPosted() {
        sut.recordWebReport()
        expectNoChange()

        sut.recordWebReport()

        waitForExpectations(timeout: 0.1)
    }

    func testWhenResetForDebuggingThenChangeIsPosted() {
        sut.recordAcceptedInNativeInput()
        expectChange()

        sut.resetForDebugging()

        waitForExpectations(timeout: 1)
    }

    private func expectChange() {
        expectation(forNotification: .duckAiTermsOfServiceDidChange, object: nil, notificationCenter: notificationCenter)
    }

    private func expectNoChange() {
        expectation(forNotification: .duckAiTermsOfServiceDidChange, object: nil, notificationCenter: notificationCenter).isInverted = true
    }
}
