//
//  DuckAiTermsOfServiceDisclaimerTests.swift
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

final class DuckAiTermsOfServiceDisclaimerTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var feature: StubNativeTermsOfServiceFeature!

    private var suiteName: String { String(describing: self) }

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        feature = StubNativeTermsOfServiceFeature(isAvailable: true)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        feature = nil
        super.tearDown()
    }

    func testWhenNotAcceptedThenTheDisclaimerShowsTheUTICopy() {
        XCTAssertEqual(makeSUT().message, UTIFooterMessageMapper().termsOfServiceMessage())
    }

    func testWhenTheFeatureIsOffThenThereIsNoDisclaimer() {
        feature.isAvailable = false

        XCTAssertNil(makeSUT().message)
    }

    /// Accepting on the web retires the native disclaimer too.
    func testWhenTheWebReportedAnAcceptanceThenThereIsNoDisclaimer() {
        store.recordWebReport()

        XCTAssertNil(makeSUT().message)
    }

    func testWhenSentWithTheDisclaimerOnScreenThenTheTermsAreAccepted() {
        let sut = makeSUT()

        XCTAssertTrue(sut.acceptIfShown(sut.message))

        XCTAssertTrue(store.hasAccepted)
        XCTAssertNil(sut.message)
    }

    /// Nothing on screen, such as a send made before the card appeared, leaves the web app its own card.
    func testWhenSentWithoutTheDisclaimerOnScreenThenNothingIsAccepted() {
        XCTAssertFalse(makeSUT().acceptIfShown(nil))

        XCTAssertFalse(store.hasAccepted)
    }

    /// The iPad address bar shares its card with the model switch notice.
    func testWhenAnotherMessageIsOnScreenThenNothingIsAccepted() {
        let modelSwitch = UTIFooterMessage(icon: .modelSwitch, title: "Now using 5.6 Luna", subtitle: nil,
                                           primaryAction: nil, isDismissible: true)

        XCTAssertFalse(makeSUT().acceptIfShown(modelSwitch))

        XCTAssertFalse(store.hasAccepted)
    }

    /// The flag going off after the card showed must not record an acceptance the FE won't be told about.
    func testWhenTheFeatureTurnsOffWhileTheDisclaimerIsOnScreenThenNothingIsAccepted() {
        let sut = makeSUT()
        let shown = sut.message
        feature.isAvailable = false

        XCTAssertFalse(sut.acceptIfShown(shown))

        XCTAssertFalse(store.hasAccepted)
    }

    // MARK: - Helpers

    private var store: DuckAiTermsOfServiceStore {
        DuckAiTermsOfServiceStore(keyValueStore: userDefaults)
    }

    private func makeSUT() -> DuckAiTermsOfServiceDisclaimer {
        DuckAiTermsOfServiceDisclaimer(feature: feature, store: store)
    }
}

final class StubNativeTermsOfServiceFeature: DuckAiNativeTermsOfServiceFeatureProviding {
    var isAvailable: Bool

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }
}
