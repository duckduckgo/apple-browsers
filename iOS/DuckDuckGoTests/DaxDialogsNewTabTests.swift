//
//  DaxDialogsNewTabTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import TrackerRadarKit
@testable import DuckDuckGo

final class DaxDialogsNewTabTests: XCTestCase {

    var daxDialogs: DaxDialogs!
    var settings: DaxDialogsSettings!

    override func setUp() {
        settings = MockDaxDialogsSettings()
        let mockVariantManager = MockVariantManager(isSupportedReturns: true)
        daxDialogs = DaxDialogs(
            settings: settings,
            entityProviding: MockEntityProvider(),
            variantManager: mockVariantManager,
            onboardingSubscriptionPromotionHelper: MockOnboardingSubscriptionPromotionHelper()
        )
    }

    override func tearDown() {
        settings = nil
        daxDialogs = nil
    }

    func testIfIsAddFavoriteFlow_OnNextHomeScreenMessageNew_ReturnsAddFavorite() {
        // GIVEN
        daxDialogs.enableAddFavoriteFlow()

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(homeScreenMessage, .addFavorite)
    }

    func testIfTryAnonymousSearchNotShown_OnNextHomeScreenMessageNew_ReturnsInitial() {
        // GIVEN
        settings.tryAnonymousSearchShown = false

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(homeScreenMessage, .initial)
    }

    func testIfTryAnonymousSearchShown_AndTryVisitASiteNotShown_OnNextHomeScreenMessageNew_ReturnsSubsequent() {
        // GIVEN
        settings.tryAnonymousSearchShown = true
        settings.tryVisitASiteShown = false

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(homeScreenMessage, .subsequent)
    }

    func testIfTryAnonymousSearchShown_AndTryVisitASiteShown_AndFireDialogNotShown_OnNextHomeScreenMessageNew_ReturnsNil() {
        // GIVEN
        settings.tryAnonymousSearchShown = true
        settings.tryVisitASiteShown = true

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertNil(homeScreenMessage)
    }

    func testIfFinalDialogSeen_OnNextHomeScreenMessageNew_ReturnsNil() {
        // GIVEN
        settings.browsingFinalDialogShown = true

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        //
        XCTAssertNil(homeScreenMessage)
    }

    func testIfIsNotEnabled_OnNextHomeScreenMessageNew_ReturnsNil() {
        // GIVEN
        settings.isDismissed = true

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        //
        XCTAssertNil(homeScreenMessage)
    }

    func testIfFireDialogShow_OnNextHomeScreenMessageNew_ReturnsFinal() {
        // GIVEN – search path: user browsed a site before fire (nonDDGBrowsingMessageSeen = true)
        settings.fireMessageExperimentShown = true
        settings.browsingWithTrackersShown = true

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(homeScreenMessage, .final)
    }

    // MARK: - Chat Path – peekNextHomeScreenMessageExperiment

    func testWhenFireShownAndNoBrowsingAndChatPathVisitSiteNotSeen_OnNextHomeScreenMessageNew_ReturnsSubsequent() {
        // GIVEN – chat path: fire was seen before visiting any site
        settings.fireMessageExperimentShown = true
        settings.chatPathVisitSiteSeen = false
        // nonDDGBrowsingMessageSeen = false by default

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(homeScreenMessage, .subsequent)
    }

    func testWhenFireShownAndChatPathVisitSiteSeen_AndNoBrowsing_OnNextHomeScreenMessageNew_ReturnsNil() {
        // GIVEN – chat path: visit-site dialog was shown; waiting for user to browse
        settings.fireMessageExperimentShown = true
        settings.chatPathVisitSiteSeen = true
        // nonDDGBrowsingMessageSeen = false by default

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN – no NTP dialog; tracker dialog will surface when user browses
        XCTAssertNil(homeScreenMessage)
    }

    // MARK: - Chat Path – isInChatPathPostFireState

    func testWhenFireShownAndNoBrowsing_IsInChatPathPostFireState_IsTrue() {
        // GIVEN
        settings.fireMessageExperimentShown = true
        // browsingWithTrackersShown = false by default

        // THEN
        XCTAssertTrue(daxDialogs.isInChatPathPostFireState)
    }

    func testWhenFireNotShown_IsInChatPathPostFireState_IsFalse() {
        // GIVEN
        settings.fireMessageExperimentShown = false

        // THEN
        XCTAssertFalse(daxDialogs.isInChatPathPostFireState)
    }

    func testWhenFireShownAndBrowsingDialogSeen_IsInChatPathPostFireState_IsFalse() {
        // GIVEN – search path: fire + browsing already happened
        settings.fireMessageExperimentShown = true
        settings.browsingWithTrackersShown = true

        // THEN
        XCTAssertFalse(daxDialogs.isInChatPathPostFireState)
    }

    // MARK: - Chat Path – isChatPathEOJState

    func testWhenFireAndVisitSiteSeenAndFinalNotShown_IsChatPathEOJState_IsTrue() {
        // GIVEN
        settings.fireMessageExperimentShown = true
        settings.chatPathVisitSiteSeen = true
        settings.browsingFinalDialogShown = false

        // THEN
        XCTAssertTrue(daxDialogs.isChatPathEOJState)
    }

    func testWhenFireShownButChatPathVisitSiteNotSeen_IsChatPathEOJState_IsFalse() {
        // GIVEN
        settings.fireMessageExperimentShown = true
        settings.chatPathVisitSiteSeen = false

        // THEN
        XCTAssertFalse(daxDialogs.isChatPathEOJState)
    }

    func testWhenFireAndVisitSiteSeenButFinalAlreadyShown_IsChatPathEOJState_IsFalse() {
        // GIVEN
        settings.fireMessageExperimentShown = true
        settings.chatPathVisitSiteSeen = true
        settings.browsingFinalDialogShown = true

        // THEN
        XCTAssertFalse(daxDialogs.isChatPathEOJState)
    }

    func testWhenFireNotShown_IsChatPathEOJState_IsFalse() {
        // GIVEN
        settings.fireMessageExperimentShown = false
        settings.chatPathVisitSiteSeen = true

        // THEN
        XCTAssertFalse(daxDialogs.isChatPathEOJState)
    }

    // MARK: - Chat Path – setChatPathVisitSiteSeen

    func testWhenSetChatPathVisitSiteSeen_ThenFlagIsPersisted() {
        // GIVEN
        settings.chatPathVisitSiteSeen = false

        // WHEN
        daxDialogs.setChatPathVisitSiteSeen()

        // THEN
        XCTAssertTrue(settings.chatPathVisitSiteSeen)
    }

    // MARK: - Zombie State Recovery

    func testWhenNTPStepsCompleteAndTrackerDialogSeenButFireSkipped_ThenNextHomeScreenMessageReturnsFinal() {
        // GIVEN
        settings.tryAnonymousSearchShown = true
        settings.tryVisitASiteShown = true
        settings.browsingWithTrackersShown = true
        settings.fireMessageExperimentShown = false

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(homeScreenMessage, .final)
    }

    func testWhenFinalDialogSeenButNotDismissed_ThenNextHomeScreenMessageDismissesOnboarding() {
        // GIVEN
        settings.browsingFinalDialogShown = true
        settings.isDismissed = false

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertNil(homeScreenMessage)
        XCTAssertTrue(settings.isDismissed)
    }

    func testWhenFireButtonPulseStarted_ThenFireEducationMarkedAsSeen() {
        // GIVEN
        settings.fireMessageExperimentShown = false

        // WHEN
        daxDialogs.fireButtonPulseStarted()

        // THEN
        XCTAssertTrue(settings.fireMessageExperimentShown)
        XCTAssertTrue(settings.privacyButtonPulseShown)
    }
}

class MockDaxDialogsSettings: DaxDialogsSettings {
    
    var isDismissed: Bool = false

    var homeScreenMessagesSeen: Int = 0

    var tryAnonymousSearchShown: Bool = false

    var tryVisitASiteShown: Bool = false

    var browsingAfterSearchShown: Bool = false

    var browsingWithTrackersShown: Bool = false

    var browsingWithoutTrackersShown: Bool = false

    var browsingMajorTrackingSiteShown: Bool = false

    var fireButtonEducationShownOrExpired: Bool = false

    var fireMessageExperimentShown: Bool = false

    var privacyButtonPulseShown: Bool = false

    var fireButtonPulseDateShown: Date?

    var browsingFinalDialogShown: Bool = false

    var subscriptionPromotionDialogShown: Bool = false

    var chatPathVisitSiteSeen: Bool = false
}
