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
    var mockSettings: MockDaxDialogsSettings!

    override func setUp() {
        mockSettings = MockDaxDialogsSettings()
        settings = mockSettings
        let mockVariantManager = MockVariantManager(isSupportedReturns: true)
        daxDialogs = DaxDialogs(
            settings: settings,
            entityProviding: MockEntityProvider(),
            variantManager: mockVariantManager,
            onboardingSubscriptionPromotionHelper: MockOnboardingSubscriptionPromotionHelper()
        )
    }

    override func tearDown() {
        mockSettings = nil
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
        mockSettings.isChatFirstPath = true
        mockSettings.fireMessageExperimentShown = true
        mockSettings.chatPathVisitSiteSeen = false
        mockSettings.chatPathPhase = .visitSite
        // nonDDGBrowsingMessageSeen = false by default

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(homeScreenMessage, .subsequent)
    }

    func testWhenFireShownAndChatPathVisitSiteSeenAndNoBrowsing_OnNextHomeScreenMessageNew_ReturnsSubsequent() {
        // GIVEN – chat path: visit-site dialog was shown but user hasn't browsed to a non-DDG site yet.
        // Production: DefaultDaxDialogsSettings.chatPathPhase stays .visitSite until seenBrowsingDialog
        // is true, so the NTP keeps returning .subsequent to keep prompting the user.
        mockSettings.isChatFirstPath = true
        mockSettings.fireMessageExperimentShown = true
        mockSettings.chatPathVisitSiteSeen = true
        mockSettings.chatPathPhase = .visitSite // production computed value in this state

        // WHEN
        let homeScreenMessage = daxDialogs.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(homeScreenMessage, .subsequent)
    }

    // MARK: - Chat Path – chatPathPhase

    func testWhenChatPathPhaseIsNone_DaxDialogsReturnsNone() {
        mockSettings.chatPathPhase = .none

        XCTAssertEqual(daxDialogs.chatPathPhase, .none)
    }

    func testWhenChatPathPhaseIsVisitSite_DaxDialogsReturnsVisitSite() {
        mockSettings.chatPathPhase = .visitSite

        XCTAssertEqual(daxDialogs.chatPathPhase, .visitSite)
    }

    func testWhenChatPathPhaseIsTrackerToEOJ_DaxDialogsReturnsTrackerToEOJ() {
        mockSettings.chatPathPhase = .trackerToEOJ

        XCTAssertEqual(daxDialogs.chatPathPhase, .trackerToEOJ)
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

    var isChatFirstPath: Bool = false

    var chatPathPhase: DaxDialogs.ChatPathPhase = .none
}
