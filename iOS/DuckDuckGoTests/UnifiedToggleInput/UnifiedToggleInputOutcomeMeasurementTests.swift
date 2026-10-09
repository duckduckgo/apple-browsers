//
//  UnifiedToggleInputOutcomeMeasurementTests.swift
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
final class UnifiedToggleInputOutcomeMeasurementTests: XCTestCase {

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

    // MARK: - Prompts

    func testWhenAskIsTappedWithTheDisclaimerOnScreenThenAButtonPromptIsReported() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: true)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        showFooter([.termsConsent])

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "how", mode: .aiChat, trigger: .sendButton)
        sut.completeOmnibarDeactivation()

        XCTAssertEqual(outcomeParameters, [[
            "surface": "address_bar",
            "disclaimer_shown": "true",
            "terms_state": "not_accepted",
            "outcome": "prompt_submitted",
            "submit_method": "button"
        ]])
    }

    func testWhenReturnSendsThePromptThenTheSubmitMethodIsEnter() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "how", mode: .aiChat, trigger: .textEntry)

        XCTAssertEqual(outcomeParameters.last?["submit_method"], "enter")
    }

    func testWhenPasteAndGoSendsThePromptThenTheSubmitMethodIsOther() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "how", mode: .aiChat, trigger: .pasteAndGo)

        XCTAssertEqual(outcomeParameters.last?["submit_method"], "other")
    }

    // MARK: - Abandoned

    func testWhenTheOmnibarClosesWithoutAPromptThenItIsReportedAbandonedWithAnUnknownTermsState() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        sut.completeOmnibarDeactivation()

        XCTAssertEqual(outcomeParameters, [[
            "surface": "address_bar",
            "disclaimer_shown": "false",
            "terms_state": "unknown",
            "outcome": "abandoned"
        ]])
    }

    func testWhenTheInputSwitchesToSearchThenItIsReportedAbandoned() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: true)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        showFooter([.termsConsent])

        sut.updateInputMode(.search, animated: false)

        XCTAssertEqual(outcomeParameters.map { $0["outcome"] }, ["abandoned"])
        XCTAssertEqual(outcomeParameters.last?["disclaimer_shown"], "true")
    }

    func testWhenTheOmnibarOpensInSearchThenNothingIsMeasuredUntilItSwitchesToDuckAI() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.activateFromOmnibar(inputMode: .search, cardPosition: .bottom)
        sut.completeOmnibarDeactivation()
        XCTAssertEqual(outcomeParameters, [])

        sut.activateFromOmnibar(inputMode: .search, cardPosition: .bottom)
        sut.updateInputMode(.aiChat, animated: false)
        sut.completeOmnibarDeactivation()

        XCTAssertEqual(outcomeParameters.map { $0["outcome"] }, ["abandoned"])
    }

    func testWhenTheAppGoesToTheBackgroundThenItIsReportedAbandoned() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(outcomeParameters.map { $0["outcome"] }, ["abandoned"])
    }

    func testWhenTheUserHasAcceptedThenTheTermsStateIsAccepted() {
        termsOfServiceStore.recordAcceptedInNativeInput()
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: true)
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)

        sut.completeOmnibarDeactivation()

        XCTAssertEqual(outcomeParameters.last?["terms_state"], "accepted")
    }

    // MARK: - Surfaces

    /// The input has already left the Duck.ai tab when it's reported.
    func testWhenTheDuckAITabHidesTheInputThenTheAbandonedReportKeepsItsSurface() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.showExpanded(inputMode: .aiChat)

        sut.hide()

        XCTAssertEqual(outcomeParameters.last?["surface"], "duck_ai")
    }

    func testWhenTheDuckAITabShowsAnExistingChatThenFollowUpsAreNotMeasured() {
        sut = makeCoordinator(host: .omnibar, isDisclaimerEnabled: false)
        sut.syncChipVisibility(hasExistingChat: true)
        sut.showExpanded(inputMode: .aiChat)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "and then?", mode: .aiChat, trigger: .sendButton)
        sut.hide()

        XCTAssertEqual(outcomeParameters, [])
    }

    func testWhenTheContextualSheetIsPresentedAndDismissedThenItIsMeasuredWhileItIsOnScreen() {
        sut = makeCoordinator(host: .contextualChat, isDisclaimerEnabled: false, contextualStart: .expandedPreSubmit)
        sut.showExpanded()
        XCTAssertEqual(outcomeParameters, [])

        sut.beginContextualInputPresentation()
        sut.endContextualInputPresentation()

        XCTAssertEqual(outcomeParameters.map { $0["surface"] }, ["contextual_chat"])
        XCTAssertEqual(outcomeParameters.map { $0["outcome"] }, ["abandoned"])
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

    private var outcomeParameters: [[String: String]] {
        pixelKitMock.actualFireCalls
            .filter { $0.pixel.name == DuckAiInputOutcomeEvent.pixelName }
            .compactMap(\.pixel.parameters)
    }
}
