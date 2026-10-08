//
//  UnifiedToggleInputTermsOfServiceMeasurementTests.swift
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
@_spi(Testing) import PixelKit
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputTermsOfServiceMeasurementTests: XCTestCase {

    private var sut: UnifiedToggleInputCoordinator!
    private var pixelKitMock: PixelKitMock!
    private var userDefaults: UserDefaults!

    private var suiteName: String { String(describing: self) }

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        pixelKitMock = PixelKitMock()
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        pixelKitMock = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Groups

    func testWhenTheDisclaimerIsOffAndTheOmnibarOpensInDuckAIThenTheSessionIsNotShown() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)

        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_not_shown"])
        XCTAssertEqual(lastParameters, ["surface": "address_bar"])
    }

    func testWhenTheDisclaimerIsOnThenTheSessionIsShownOnlyOnceItRenders() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: true)

        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        XCTAssertEqual(firedNames, [])

        showFooter([.termsConsent])

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_shown"])
    }

    func testWhenTheOmnibarOpensInSearchThenNoSessionStartsUntilItSwitchesToDuckAI() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)

        sut.activateFromOmnibar(inputMode: .search, cardPosition: .bottom)
        XCTAssertEqual(firedNames, [])

        sut.updateInputMode(.aiChat, animated: false)

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_not_shown"])
    }

    func testWhenTheTermsAreAlreadyAcceptedThenNothingIsReported() {
        termsOfServiceStore.recordWebReport()
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)

        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        sut.completeOmnibarDeactivation()

        XCTAssertEqual(firedNames, [])
    }

    /// Chats prove an earlier acceptance, and only the flag-on group records one, so both leave these users out.
    func testWhenChatsExistWithTheDisclaimerOffThenNothingIsReported() {
        termsOfServiceStore.recordExistingChats()
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)

        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        XCTAssertEqual(firedNames, [])
    }

    // MARK: - Outcomes

    func testWhenAskIsTappedWithTheDisclaimerOnScreenThenThePromptAndTheAcceptanceAreReported() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: true)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        showFooter([.termsConsent])

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "how", mode: .aiChat, trigger: .sendButton)
        sut.completeOmnibarDeactivation()

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_shown",
                                    "aichat_terms_of_service_shown_prompt_submitted",
                                    "aichat_terms_of_service_accepted"])
        XCTAssertEqual(parameters(of: "aichat_terms_of_service_shown_prompt_submitted"),
                       ["surface": "address_bar", "send_method": "ask"])
        XCTAssertEqual(parameters(of: "aichat_terms_of_service_accepted"),
                       ["surface": "address_bar", "source": "native_input", "native_disclaimer": "enabled"])
    }

    func testWhenReturnSendsWithTheDisclaimerOffThenThePromptIsReportedAsReturn() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "how", mode: .aiChat, trigger: .textEntry)

        XCTAssertEqual(parameters(of: "aichat_terms_of_service_not_shown_prompt_submitted"),
                       ["surface": "address_bar", "send_method": "return"])
    }

    func testWhenTheOmnibarClosesWithoutAPromptThenTheSessionIsAbandoned() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        sut.completeOmnibarDeactivation()

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_not_shown", "aichat_terms_of_service_not_shown_abandoned"])
    }

    func testWhenTheInputSwitchesToSearchThenTheSessionIsAbandoned() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: true)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        showFooter([.termsConsent])

        sut.updateInputMode(.search, animated: false)

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_shown", "aichat_terms_of_service_shown_abandoned"])
    }

    func testWhenTheAppGoesToTheBackgroundThenTheSessionIsAbandoned() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(firedNames.last, "aichat_terms_of_service_not_shown_abandoned")
    }

    /// The input has already left the Duck.ai tab when the session ends.
    func testWhenTheDuckAITabHidesTheInputThenTheAbandonedSessionKeepsItsSurface() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.showExpanded(inputMode: .aiChat)

        sut.hide()

        XCTAssertEqual(parameters(of: "aichat_terms_of_service_not_shown_abandoned"), ["surface": "duck_ai"])
    }

    func testWhenTheContextualSheetIsPresentedAndDismissedThenItsSessionStartsAndEndsWithIt() {
        sut = makeCoordinator(host: .contextualChat, isDisclaimerEnabled: false, contextualStart: .expandedPreSubmit)
        sut.showExpanded()
        XCTAssertEqual(firedNames, [])

        sut.beginContextualInputPresentation()
        sut.endContextualInputPresentation()

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_not_shown", "aichat_terms_of_service_not_shown_abandoned"])
        XCTAssertEqual(lastParameters, ["surface": "contextual_chat"])
    }

    // MARK: - Link

    func testWhenTheDisclaimersLinkIsTappedThenItIsReported() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: true)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        showFooter([.termsConsent])

        sut.unifiedToggleInputVC(sut.viewController, didTapFooterLink: URL(string: "https://duckduckgo.com/duckai/privacy-terms")!,
                                 messageID: .termsConsent)

        XCTAssertTrue(firedNames.contains("aichat_terms_of_service_link_tapped"))
    }

    // MARK: - Helpers

    private var termsOfServiceStore: DuckAiTermsOfServiceStore {
        DuckAiTermsOfServiceStore(keyValueStore: userDefaults)
    }

    private func makeCoordinator(host: UnifiedToggleInputHost,
                                 isDisclaimerEnabled: Bool,
                                 contextualStart: ContextualInputStart = .expandedOnExistingChat) -> UnifiedToggleInputCoordinator {
        UnifiedToggleInputCoordinator(host: host,
                                      isToggleEnabled: host == .omnibar,
                                      pixelFiring: UTIPixelFiring(pixelKit: { [unowned self] in pixelKitMock }),
                                      contextualStart: contextualStart,
                                      nativeTermsOfServiceFeature: StubNativeTermsOfServiceFeature(isAvailable: isDisclaimerEnabled),
                                      termsOfServiceStore: termsOfServiceStore)
    }

    /// Stands in for the view reporting which footer rows made it on screen.
    private func showFooter(_ ids: [UTIFooterItem.ID]) {
        sut.unifiedToggleInputVC(sut.viewController, didChangeFooterVisibility: ids)
    }

    private var termsOfServiceCalls: [ExpectedFireCall] {
        pixelKitMock.actualFireCalls.filter { $0.pixel.name.hasPrefix("aichat_terms_of_service") }
    }

    private var firedNames: [String] {
        termsOfServiceCalls.map(\.pixel.name)
    }

    private var lastParameters: [String: String]? {
        termsOfServiceCalls.last?.pixel.parameters
    }

    private func parameters(of name: String) -> [String: String]? {
        termsOfServiceCalls.last { $0.pixel.name == name }?.pixel.parameters
    }
}
