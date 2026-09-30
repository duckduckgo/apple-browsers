//
//  ContentOverlayViewControllerImportPromoTests.swift
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

import Common
import PrivacyConfig
import PrivacyConfigTestsUtils
import WebKit
import XCTest
@testable import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class ContentOverlayViewControllerImportPromoTests: XCTestCase {

    private var reporter: MockAutofillImportPromoReporter!
    private var sut: ContentOverlayViewController!
    private var overlayID: ObjectIdentifier!

    override func setUp() {
        super.setUp()
        reporter = MockAutofillImportPromoReporter()
        sut = makeSUT()
        overlayID = ObjectIdentifier(sut)
    }

    override func tearDown() {
        overlayID = nil
        sut = nil
        reporter = nil
        super.tearDown()
    }

    // Builds the overlay without loading its view: `viewDidLoad` would build the autofill script and web view.
    // `viewWillDisappear` only needs `webView`, so a bare one is injected.
    private func makeSUT() -> ContentOverlayViewController {
        let sut = ContentOverlayViewController(
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            webTrackingProtectionPreferences: WebTrackingProtectionPreferences(
                persistor: MockWebTrackingProtectionPreferencesPersistor(),
                windowControllersManager: WindowControllersManagerMock()
            ),
            featureFlagger: MockFeatureFlagger(),
            tld: TLD(),
            pinningManager: MockPinningManager()
        )
        sut.autofillImportPromoReporter = reporter
        sut.usageProvider = StubAutofillUsageProvider()
        sut.webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        return sut
    }

    private func sendPixel(named pixelName: String) {
        sut.secureVaultManager(SecureVaultManager(), didReceivePixel: AutofillUserScript.JSPixel(pixelName: pixelName, pixelParameters: nil))
    }

    private func showImportPrompt() {
        sendPixel(named: "autofill_import_credentials_prompt_shown")
    }

    func testWhenImportPromptShownPixelReceivedThenShowIsReported() {
        showImportPrompt()

        XCTAssertEqual(reporter.calls, [.shown(overlayID)])
    }

    func testWhenOtherAutofillPixelReceivedThenNothingIsReported() {
        sendPixel(named: "autofill_show")

        XCTAssertEqual(reporter.calls, [])
    }

    func testWhenViewWillDisappearTwiceAfterShowThenHideIsReportedOnce() {
        showImportPrompt()

        sut.viewWillDisappear()
        sut.viewWillDisappear()

        XCTAssertEqual(reporter.calls, [.shown(overlayID), .hidden(overlayID)])
    }

    func testWhenViewWillDisappearWithoutShowThenNothingIsReported() {
        sut.viewWillDisappear()

        XCTAssertEqual(reporter.calls, [])
    }

    func testWhenPermanentlyDismissedWhileShowingThenDismissalIsReported() {
        showImportPrompt()

        sut.autofillDidPermanentlyDismissCredentialsImportPrompt()

        XCTAssertEqual(reporter.calls, [.shown(overlayID), .permanentlyDismissed(overlayID)])
    }

    func testWhenPermanentlyDismissedWhileNotShowingThenNothingIsReported() {
        sut.autofillDidPermanentlyDismissCredentialsImportPrompt()
        showImportPrompt()
        sut.viewWillDisappear()
        sut.autofillDidPermanentlyDismissCredentialsImportPrompt()

        XCTAssertEqual(reporter.calls, [.shown(overlayID), .hidden(overlayID)])
    }

    func testWhenShownAgainAfterHideThenEachStretchIsReported() {
        showImportPrompt()
        sut.viewWillDisappear()
        showImportPrompt()
        sut.viewWillDisappear()

        XCTAssertEqual(reporter.calls, [.shown(overlayID), .hidden(overlayID), .shown(overlayID), .hidden(overlayID)])
    }
}

@MainActor
private final class MockAutofillImportPromoReporter: AutofillImportPromoReporting {
    enum Call: Equatable {
        case shown(ObjectIdentifier)
        case importStarted(ObjectIdentifier)
        case permanentlyDismissed(ObjectIdentifier)
        case hidden(ObjectIdentifier)
    }

    private(set) var calls: [Call] = []

    func overlayDidShowImportPrompt(_ overlay: AnyObject) {
        calls.append(.shown(ObjectIdentifier(overlay)))
    }

    func overlayDidStartImport(_ overlay: AnyObject) {
        calls.append(.importStarted(ObjectIdentifier(overlay)))
    }

    func overlayDidPermanentlyDismissImportPrompt(_ overlay: AnyObject) {
        calls.append(.permanentlyDismissed(ObjectIdentifier(overlay)))
    }

    func overlayDidHideImportPrompt(_ overlay: AnyObject) {
        calls.append(.hidden(ObjectIdentifier(overlay)))
    }
}

// Keeps the generic-pixel branch away from `UserDefaults.standard`.
private struct StubAutofillUsageProvider: AutofillUsageProvider {
    var formattedFillDate: String? { nil }
    var fillDate: Date? { nil }
    var searchDauDate: Date? { nil }
    var lastActiveDate: Date? { nil }
    var formattedLastActiveDate: String? { nil }
    var isOnboarded: Bool { false }
}
