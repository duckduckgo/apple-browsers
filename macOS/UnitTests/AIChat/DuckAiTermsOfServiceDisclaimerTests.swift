//
//  DuckAiTermsOfServiceDisclaimerTests.swift
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

import FeatureFlags_macOS
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DuckAiTermsOfServiceDisclaimerTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var store: DuckAiTermsOfServiceStore!

    private var suiteName: String { String(describing: self) }

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = DuckAiTermsOfServiceStore(keyValueStore: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testWhenFlagIsOnAndTermsAreNotAcceptedThenTheDisclaimerIsRequired() {
        XCTAssertTrue(makeDisclaimer().isRequired)
    }

    func testWhenFlagIsOffThenTheDisclaimerIsNotRequired() {
        XCTAssertFalse(makeDisclaimer(isFlagOn: false).isRequired)
    }

    /// Accepting on the web, or in another window's input, retires it too.
    func testWhenTermsAreAcceptedThenTheDisclaimerIsNotRequired() {
        store.recordWebReport()

        XCTAssertFalse(makeDisclaimer().isRequired)
    }

    func testWhenAskIsClickedWithTheDisclaimerShownThenTermsAreAccepted() {
        let disclaimer = makeDisclaimer()

        XCTAssertTrue(disclaimer.acceptIfShown(true))
        XCTAssertTrue(store.hasAccepted)
        XCTAssertFalse(disclaimer.isRequired)
    }

    /// A send made without seeing the disclaimer accepts nothing; the web app shows its own card instead.
    func testWhenAskIsClickedWithoutTheDisclaimerShownThenTermsAreNotAccepted() {
        XCTAssertFalse(makeDisclaimer().acceptIfShown(false))
        XCTAssertFalse(store.hasAccepted)
    }

    func testWhenFlagIsOffThenAskAcceptsNothing() {
        XCTAssertFalse(makeDisclaimer(isFlagOn: false).acceptIfShown(true))
        XCTAssertFalse(store.hasAccepted)
    }

    /// The web reports the acceptance the native send carried, and that report must not read as a duplicate.
    func testWhenAcceptedByAskThenTheWebReportIsTheFirstAcceptance() {
        makeDisclaimer().acceptIfShown(true)

        XCTAssertEqual(store.recordWebReport(), .firstAcceptance)
    }

    func testWhenCreateImageIsSelectedThenTheDisclaimerNamesCreate() {
        let sendButton = DuckAiTermsOfServiceSendButton(isImageGenerationMode: true)

        XCTAssertEqual(sendButton, .create)
        XCTAssertEqual(sendButton.title, UserText.aiChatCreateButtonTitle)
        XCTAssertEqual(sendButton.disclaimerFormat, UserText.aiChatTermsOfServiceCreateDisclaimer)
    }

    func testWhenCreateImageIsNotSelectedThenTheDisclaimerNamesAsk() {
        let sendButton = DuckAiTermsOfServiceSendButton(isImageGenerationMode: false)

        XCTAssertEqual(sendButton, .ask)
        XCTAssertEqual(sendButton.title, UserText.aiChatAskButtonTitle)
        XCTAssertEqual(sendButton.disclaimerFormat, UserText.aiChatTermsOfServiceDisclaimer)
    }

    /// macOS copy names the click, not a tap.
    func testDisclaimerCopySaysClicking() {
        for sendButton in DuckAiTermsOfServiceSendButton.allCases {
            XCTAssertTrue(sendButton.disclaimerFormat.contains("clicking"))
            XCTAssertTrue(sendButton.disclaimerFormat.contains("%@"))
        }
    }

    private func makeDisclaimer(isFlagOn: Bool = true) -> DuckAiTermsOfServiceDisclaimer {
        DuckAiTermsOfServiceDisclaimer(
            featureFlagger: MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatNativeTermsOfService.rawValue: isFlagOn]),
            store: store
        )
    }
}
