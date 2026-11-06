//
//  DaxDialogTests.swift
//  UnitTests
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import ContentBlocking
import FeatureFlags_iOS
import Onboarding
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyDashboard
import TrackerRadarKit
import XCTest

@testable import Core
@testable import DuckDuckGo

struct MockEntityProvider: EntityProviding {
    
    func entity(forHost host: String) -> Entity? {
        let mapper = ["www.example.com": ("https://www.example.com", [], 1.0),
                      "www.facebook.com": ("Facebook", [], 4.0),
                      "www.google.com": ("Google", [], 5.0),
                      "www.instagram.com": ("Facebook", ["facebook.com"], 4.0),
                      "www.amazon.com": ("Amazon.com", [], 3.0),
                      "www.1dmp.io": ("https://www.1dmp.io", [], 0.5)]
        if let entityElements = mapper[host] {
            return Entity(displayName: entityElements.0, domains: entityElements.1, prevalence: entityElements.2)
        } else {
            return nil
        }
    }
}

final class DaxDialog: XCTestCase {

    struct URLs {
        
        static let example = URL(string: "https://www.example.com")!
        static let ddg = URL(string: "https://duckduckgo.com?q=test")!
        static let ddg2 = URL(string: "https://duckduckgo.com?q=testSomethingElse")!
        static let facebook = URL(string: "https://www.facebook.com")!
        static let google = URL(string: "https://www.google.com")!
        static let ownedByFacebook = URL(string: "https://www.instagram.com")!
        static let ownedByFacebook2 = URL(string: "https://www.whatsapp.com")!
        static let amazon = URL(string: "https://www.amazon.com")!
        static let tracker = URL(string: "https://www.1dmp.io")!

    }

    let settings: MockDaxDialogsSettings = MockDaxDialogsSettings()
    lazy var mockVariantManager = MockVariantManager(isSupportedReturns: false)
    lazy var onboarding = DaxDialogs(settings: settings,
                                     entityProviding: MockEntityProvider(),
                                     variantManager: mockVariantManager,
                                     timeLimit: makeDisabledContextualOnboardingTimeLimit())
    private var entityProvider: EntityProviding!

    override func setUp() {
        super.setUp()
        setupUserDefault(with: #file)
        entityProvider = MockEntityProvider()
    }

    func testWhenStartingAddFavoriteFlowThenNextMessageIsAddFavorite() {
        // WHEN
        onboarding.enableAddFavoriteFlow()

        // THEN
        XCTAssertEqual(onboarding.nextHomeScreenMessageNew(), .addFavorite)
        XCTAssertTrue(onboarding.isAddFavoriteFlow)
    }
    
    func testWhenLaunchOptionsHandlerSkipsOnboardingThenDialogsAreNotEnabled() {
        let settings = MockDaxDialogsSettings()
        settings.isDismissed = false
        let launchOptionsHandler = LaunchOptionsHandler()
        let onboarding = DaxDialogs(settings: settings,
                                    entityProviding: MockEntityProvider(),
                                    launchOptionsHandler: launchOptionsHandler,
                                    timeLimit: makeDisabledContextualOnboardingTimeLimit())
        XCTAssertTrue(onboarding.isEnabled)

        let launchOptionsHandlerDisabled = LaunchOptionsHandler(environment: ["ONBOARDING": "false"])
        let onboardingDisabled = DaxDialogs(settings: settings,
                                            entityProviding: MockEntityProvider(),
                                            launchOptionsHandler: launchOptionsHandlerDisabled,
                                            timeLimit: makeDisabledContextualOnboardingTimeLimit())
        XCTAssertFalse(onboardingDisabled.isEnabled)
    }

    func testWhenEachVersionOfTrackersMessageIsShownThenFormattedCorrectly() {
        let testCases = [
            (urls: [ URLs.google ], expected: DaxDialogs.BrowsingSpec.withOneTracker.format(args: "Google"), line: #line),
            (urls: [ URLs.google, URLs.amazon ], expected: DaxDialogs.BrowsingSpec.withMultipleTrackers.format(args: 0, "Google", "Amazon.com"), line: #line),
            (urls: [ URLs.amazon, URLs.ownedByFacebook ], expected: DaxDialogs.BrowsingSpec.withMultipleTrackers.format(args: 0, "Facebook", "Amazon.com"), line: #line),
            (urls: [ URLs.facebook, URLs.google ], expected: DaxDialogs.BrowsingSpec.withMultipleTrackers.format(args: 0, "Google", "Facebook"), line: #line),
            (urls: [ URLs.facebook, URLs.google, URLs.amazon ], expected: DaxDialogs.BrowsingSpec.withMultipleTrackers.format(args: 1, "Google", "Facebook"), line: #line),
            (urls: [ URLs.facebook, URLs.google, URLs.amazon, URLs.tracker ], expected: DaxDialogs.BrowsingSpec.withMultipleTrackers.format(args: 2, "Google", "Facebook"), line: #line)
        ]

        testCases.forEach { testCase in
            
            let onboarding = DaxDialogs(settings: MockDaxDialogsSettings(),
                                        entityProviding: MockEntityProvider(),
                                        variantManager: mockVariantManager,
                                        timeLimit: makeDisabledContextualOnboardingTimeLimit())
            let privacyInfo = makePrivacyInfo(url: URLs.example)
            
            testCase.urls.forEach { url in
                let detectedTracker = detectedTrackerFrom(url, pageUrl: URLs.example.absoluteString)
                privacyInfo.trackerInfo.addDetectedTracker(detectedTracker, onPageWithURL: URLs.example)
            }
            
            XCTAssertFalse(onboarding.shouldShowFireButtonPulse)
            
            // Assert the expected case
            XCTAssertEqual(testCase.expected, onboarding.nextBrowsingMessageIfShouldShow(for: privacyInfo), line: UInt(testCase.line))
        }
        
    }
    
    func testWhenPrimingDaxDialogForUseThenDismissedIsFalse() {
        let settings = MockDaxDialogsSettings()
        settings.isDismissed = true
        
        let onboarding = DaxDialogs(settings: settings, entityProviding: entityProvider, timeLimit: makeDisabledContextualOnboardingTimeLimit())
        onboarding.primeForUse()
        XCTAssertFalse(settings.isDismissed)
    }
    
    func testDaxDialogsDismissedByDefault() {
        XCTAssertTrue(DefaultDaxDialogsSettings().isDismissed)
    }

    func testWhenBrowsingSpecIsWithOneTrackerThenHighlightAddressBarIsFalse() throws {
        // GIVEN
        let sut = makeSUT(settings: MockDaxDialogsSettings())
        let privacyInfo = makePrivacyInfo(url: URLs.example)
        let detectedTracker = detectedTrackerFrom(URLs.google, pageUrl: URLs.example.absoluteString)
        privacyInfo.trackerInfo.addDetectedTracker(detectedTracker, onPageWithURL: URLs.example)

        // WHEN
        let result = try XCTUnwrap(sut.nextBrowsingMessageIfShouldShow(for: privacyInfo))

        // THEN
        XCTAssertEqual(result.type, .withOneTracker)
    }

    func testWhenBrowsingSpecIsWithMultipleTrackerThenHighlightAddressBarIsFalse() throws {
        // GIVEN
        let sut = makeSUT(settings: MockDaxDialogsSettings())
        let privacyInfo = makePrivacyInfo(url: URLs.example)
        [URLs.google, URLs.amazon].forEach { tracker in
            let detectedTracker = detectedTrackerFrom(tracker, pageUrl: URLs.example.absoluteString)
            privacyInfo.trackerInfo.addDetectedTracker(detectedTracker, onPageWithURL: URLs.example)
        }

        // WHEN
        let result = try XCTUnwrap(sut.nextBrowsingMessageIfShouldShow(for: privacyInfo))

        // THEN
        XCTAssertEqual(result.type, .withMultipleTrackers)
    }

    func testWhenURLIsDuckDuckGoSearchAndSearchDialogHasNotBeenSeenThenReturnSpecTypeAfterSearch() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingAfterSearchShown = false
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))

        // THEN
        XCTAssertEqual(result?.type, .afterSearch)
    }

    func testWhenURLIsMajorTrackerWebsiteAndMajorTrackerDialogHasNotBeenSeenThenReturnSpecTypeSiteIsMajorTracker() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingMajorTrackingSiteShown = false
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.facebook)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: privacyInfo)

        // THEN
        XCTAssertEqual(result?.type, .siteIsMajorTracker)
    }

    func testWhenURLIsOwnedByMajorTrackerAndMajorTrackerDialogHasNotBeenSeenThenReturnSpecTypeSiteOwnedByMajorTracker() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingMajorTrackingSiteShown = false
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.ownedByFacebook)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: privacyInfo)

        // THEN
        XCTAssertEqual(result?.type, .siteOwnedByMajorTracker)
    }

    func testWhenURLHasTrackersAndMultipleTrackersDialogHasNotBeenSeenThenReturnSpecTypeWithMultipleTrackers() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = false
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.example)
        [URLs.google, URLs.amazon].forEach { url in
            let detectedTracker = detectedTrackerFrom(url, pageUrl: URLs.example.absoluteString)
            privacyInfo.trackerInfo.addDetectedTracker(detectedTracker, onPageWithURL: URLs.example)
        }

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: privacyInfo)

        // THEN
        XCTAssertEqual(result?.type, .withMultipleTrackers)
    }

    func testWhenURLHasNoTrackersAndIsNotSERPAndNoTrakcersDialogHasNotBeenSeenThenReturnSpecTypeWithoutTrackers() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithoutTrackersShown = false
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.example))

        // THEN
        XCTAssertEqual(result?.type, .withoutTrackers)
    }

    func testWhenURLIsDuckDuckGoSearchAndHasVisitedWebsiteThenSpecTypeSearchIsReturned() throws {
        try [DaxDialogs.BrowsingSpec.withoutTrackers, .siteIsMajorTracker, .siteOwnedByMajorTracker, .withOneTracker, .withMultipleTrackers].forEach { spec in
            // GIVEN
            let settings = MockDaxDialogsSettings()
            let sut = DaxDialogs(settings: settings, entityProviding: entityProvider, timeLimit: makeDisabledContextualOnboardingTimeLimit())
            sut.overrideShownFlagFor(spec, flag: true)

            // WHEN
            let result = try XCTUnwrap(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg)))

            // THEN
            XCTAssertEqual(result.type, .afterSearch)
        }
    }

    func testWhenFireButtonSeen_AndFinalDialogNotSeen_AndSearchDone_ThenFinalBrowsingSpecIsReturned() throws {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingAfterSearchShown = true
        settings.fireMessageExperimentShown = true
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = try XCTUnwrap(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg)))

        // THEN
        XCTAssertEqual(result, .final)
    }

    func testWhenFireButtonSeen_AndFinalDialogNotSeen_AndWebsiteWithoutTracker_ThenFinalBrowsingSpecIsReturned() throws {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithoutTrackersShown = true
        settings.fireMessageExperimentShown = true
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = try XCTUnwrap(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.example)))

        // THEN
        XCTAssertEqual(result, .final)
    }

    func testWhenFireButtonSeen_AndFinalDialogNotSeen_AndWebsiteWithTracker_ThenFinalBrowsingSpecIsReturned() throws {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = true
        settings.fireMessageExperimentShown = true
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.example)
        let detectedTracker = detectedTrackerFrom(URLs.google, pageUrl: URLs.example.absoluteString)
        privacyInfo.trackerInfo.addDetectedTracker(detectedTracker, onPageWithURL: URLs.example)

        // WHEN
        let result = try XCTUnwrap(sut.nextBrowsingMessageIfShouldShow(for: privacyInfo))

        // THEN
        XCTAssertEqual(result, .final)
    }

    func testWhenFireButtonSeen_AndFinalDialogNotSeen_AndWebsiteMajorTracker_ThenFinalBrowsingSpecIsReturned() throws {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingMajorTrackingSiteShown = true
        settings.fireMessageExperimentShown = true
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.ownedByFacebook)

        // WHEN
        let result = try XCTUnwrap(sut.nextBrowsingMessageIfShouldShow(for: privacyInfo))

        // THEN
        XCTAssertEqual(result, .final)
    }

    func testWhenFireButtonSeen_AndFinalDialogSeen_AndSearchDone_ThenBrowsingSpecIsNil() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingAfterSearchShown = true
        settings.fireMessageExperimentShown = true
        settings.browsingFinalDialogShown = true
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))

        // THEN
        XCTAssertNil(result)
    }

    func testWhenFireButtonSeen_AndFinalDialogSeen_AndWebsiteWithoutTracker_ThenBrowsingSpecIsNotFinal() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithoutTrackersShown = true
        settings.fireMessageExperimentShown = true
        settings.browsingFinalDialogShown = true
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.example))

        // THEN
        XCTAssertNil(result)
    }

    func testWhenFireButtonSeen_AndFinalDialogSeen_AndWebsiteWithTracker_ThenBrowsingSpecIsNil() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = true
        settings.fireMessageExperimentShown = true
        settings.browsingFinalDialogShown = true
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.example)
        let detectedTracker = detectedTrackerFrom(URLs.google, pageUrl: URLs.example.absoluteString)
        privacyInfo.trackerInfo.addDetectedTracker(detectedTracker, onPageWithURL: URLs.example)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: privacyInfo)

        // THEN
        XCTAssertNil(result)
    }

    func testWhenFireButtonSeen_AndFinalDialogSeen_AndWebsiteMajorTracker_ThenFinalBrowsingSpecIsReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingMajorTrackingSiteShown = true
        settings.fireMessageExperimentShown = true
        settings.browsingFinalDialogShown = true
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.ownedByFacebook)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: privacyInfo)

        // THEN
        XCTAssertNil(result)
    }

    func testWhenFireButtonSeen_AndFinalDialogSeen_AndSearchNotSeen_ThenAfterSearchSpecIsReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithoutTrackersShown = true
        settings.browsingWithTrackersShown = true
        settings.browsingMajorTrackingSiteShown = true
        settings.fireMessageExperimentShown = true
        settings.browsingFinalDialogShown = true
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))

        // THEN
        XCTAssertEqual(result, .afterSearch)
    }

    func testWhenSearchDialogSeen_OnReload_SearchDialogReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))

        // THEN
        XCTAssertEqual(result1, .afterSearch)
        XCTAssertEqual(result1, result2)
    }

    func testWhenSearchDialogSeen_OnLoadingAnotherSearch_NilReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg2))

        // THEN
        XCTAssertEqual(result1, .afterSearch)
        XCTAssertNil(result2)
    }

    func testWhenMajorTrackerDialogSeen_OnReload_MajorTrackerDialogReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))

        // THEN
        XCTAssertEqual(result1?.type, .siteIsMajorTracker)
        XCTAssertEqual(result1, result2)
    }

    func testWhenMajorTrackerDialogSeen_OnLoadingAnotherSearch_NilReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.google))

        // THEN
        XCTAssertEqual(result1?.type, .siteIsMajorTracker)
        XCTAssertNil(result2)
    }

    func testWhenMajorTrackerOwnerMessageSeen_OnReload_MajorTrackerOwnerDialogReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ownedByFacebook))
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ownedByFacebook))

        // THEN
        XCTAssertEqual(result1?.type, .siteOwnedByMajorTracker)
        XCTAssertEqual(result1, result2)
    }

    func testWhenMajorTrackerOwnerMessageSeen_OnLoadingAnotherSearch_NilReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ownedByFacebook))
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ownedByFacebook2))

        // THEN
        XCTAssertEqual(result1?.type, .siteOwnedByMajorTracker)
        XCTAssertNil(result2)
    }

    func testWhenWithoutTrackersMessageSeen_OnReload_WithoutTrackersDialogReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.tracker))
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.tracker))

        // THEN
        XCTAssertEqual(result1?.type, .withoutTrackers)
        XCTAssertEqual(result1, result2)
    }

    func testWhenWithoutTrackersMessageSeen_OnLoadingAnotherSearch_NilReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.tracker))
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.example))

        // THEN
        XCTAssertEqual(result1?.type, .withoutTrackers)
        XCTAssertNil(result2)
    }

    func testWhenFinalMessageSeen_OnReload_NilReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithoutTrackersShown = true
        settings.fireMessageExperimentShown = true
        let sut = makeSUT(settings: settings)

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.example))
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.example))

        // THEN
        XCTAssertEqual(result1?.type, .final)
        XCTAssertNil(result2)
    }

    func testWhenVisitWebsiteSeen_OnReload_VisitWebsiteNotReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)
        sut.setSearchMessageSeen()

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))
        sut.setSearchMessageSeen()
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))
        let result3 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))

        // THEN
        XCTAssertEqual(result1?.type, .afterSearch)
        XCTAssertNil(result2)
        XCTAssertNil(result3)
    }

    func testWhenVisitWebsiteSeen_OnLoadingAnotherSearch_NilIsReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)
        sut.setSearchMessageSeen()

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))
        sut.setSearchMessageSeen()
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))
        let result3 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg2))

        // THEN
        XCTAssertEqual(result1?.type, .afterSearch)
        XCTAssertNil(result2)
        XCTAssertNil(result3)
    }

    func testWhenFireMessageSeen_OnReload_FireMessageReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)
        sut.setSearchMessageSeen()

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))
        sut.setFireEducationMessageSeen()
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))
        let result3 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))

        // THEN
        XCTAssertEqual(result1?.type, .siteIsMajorTracker)
        XCTAssertEqual(result2?.type, .fire(.standard))
        XCTAssertEqual(result2, result3)
    }

    func testWhenSearchNotSeen_AndFireMessageSeen_OnLoadingAnotherSearch_ExpectedDialogIseturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)
        sut.setSearchMessageSeen()

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))
        sut.setFireEducationMessageSeen()
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))
        let result3 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))

        // THEN
        XCTAssertEqual(result1?.type, .siteIsMajorTracker)
        XCTAssertEqual(result2?.type, .fire(.standard))
        XCTAssertEqual(result3?.type, .afterSearch)
    }

    func testWhenSearchSeen_AndFireMessageSeen_OnLoadingAnotherSearch_ExpectedDialogIseturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)
        sut.setSearchMessageSeen()

        // WHEN
        let result1 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))
        sut.setFireEducationMessageSeen()
        let result2 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))
        let result3 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg))
        settings.browsingAfterSearchShown = true
        let result4 = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ddg2))

        // THEN
        XCTAssertEqual(result1?.type, .siteIsMajorTracker)
        XCTAssertEqual(result2?.type, .fire(.standard))
        XCTAssertEqual(result3?.type, .afterSearch)
        XCTAssertEqual(result4?.type, .final)
    }

    func testWhenBrowserWithTrackersShown_AndPrivacyAnimationNotShown_ThenShowPrivacyAnimationPulse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = true
        settings.privacyButtonPulseShown = false
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.shouldShowPrivacyButtonPulse

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenBrowserWithTrackersShown_AndPrivacyAnimationShown_ThenDoNotShowPrivacyAnimationPulse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = true
        settings.privacyButtonPulseShown = true
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.shouldShowPrivacyButtonPulse

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenBrowserWithTrackersShown_AndFireButtonPulseActive_ThenDoNotShowPrivacyAnimationPulse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = true
        settings.privacyButtonPulseShown = false
        let sut = makeSUT(settings: settings)
        sut.fireButtonPulseStarted()

        // WHEN
        let result = sut.shouldShowPrivacyButtonPulse

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenCallSetPrivacyButtonPulseSeen_ThenSetPrivacyButtonPulseShownFlagToTrue() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)
        XCTAssertFalse(settings.privacyButtonPulseShown)

        // WHEN
        sut.setPrivacyButtonPulseSeen()

        // THEN
        XCTAssertTrue(settings.privacyButtonPulseShown)
    }

    func testWhenSetFireEducationMessageSeenIsCalled_ThenSetPrivacyButtonPulseShownToTrue() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)
        XCTAssertFalse(settings.privacyButtonPulseShown)

        // WHEN
        sut.setFireEducationMessageSeen()

        // THEN
        XCTAssertTrue(settings.privacyButtonPulseShown)
    }

    func testWhenFireButtonAnimationPulseNotShown__AndShouldShowFireButtonPulseIsCalled_ThenReturnTrue() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.privacyButtonPulseShown = true
        settings.browsingWithTrackersShown = true
        settings.fireButtonPulseDateShown = nil
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.shouldShowFireButtonPulse

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenFireButtonAnimationPulseShown_AndShouldShowFireButtonPulseIsCalled_ThenReturnFalse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.privacyButtonPulseShown = true
        settings.browsingWithTrackersShown = true
        settings.fireButtonPulseDateShown = Date()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.shouldShowFireButtonPulse

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenFireEducationMessageSeen_AndFinalMessageNotSeen_ThenShowFinalMessage() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.fireMessageExperimentShown = true
        settings.browsingFinalDialogShown = false
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(result, .final)
    }

    func testWhenNextHomeScreenMessageNewIsCalled_ThenLastVisitedOnboardingWebsiteAndLastShownDaxDialogAreSetToNil() {
        // GIVEN
        let sut = makeSUT(settings: MockDaxDialogsSettings())
        sut.setLastShownDialog(type: DaxDialogs.BrowsingSpec.fire.type)
        sut.setLastVisitedURL(URL(string: "https://www.example.com"))
        XCTAssertNotNil(sut.lastShownDaxDialogType)
        XCTAssertNotNil(sut.lastVisitedOnboardingWebsiteURL)

        // WHEN
        _ = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertNil(sut.lastShownDaxDialogType)
        XCTAssertNil(sut.lastVisitedOnboardingWebsiteURL)
    }

    func testWhenEnableAddFavoritesFlowIsCalled_ThenIsAddFavoriteFlowIsTrue() {
        // GIVEN
        let sut = makeSUT(settings: MockDaxDialogsSettings())
        XCTAssertFalse(sut.isAddFavoriteFlow)

        // WHEN
        sut.enableAddFavoriteFlow()

        // THEN
        XCTAssertTrue(sut.isAddFavoriteFlow)
    }

    func testWhenBlockedTrackersDialogSeen_AndMajorTrackerNotSeen_ThenReturnNilSpec() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = true
        settings.browsingMajorTrackingSiteShown = false
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))

        // THEN
        XCTAssertNil(result)
    }

    func testWhenBlockedTrackersDialogNotSeen_AndMajorTrackerNotSeen_ThenReturnMajorNetworkSpec() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = false
        settings.browsingMajorTrackingSiteShown = false
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.facebook))

        // THEN
        XCTAssertEqual(result?.type, .siteIsMajorTracker)
    }

    func testWhenBlockedTrackersDialogSeen_AndOwnedByMajorTrackerNotSeen_ThenReturnNilSpec() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = true
        settings.browsingMajorTrackingSiteShown = false
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ownedByFacebook))

        // THEN
        XCTAssertNil(result)
    }

    func testWhenBlockedTrackersDialogNotSeen_AndOwnedByMajorTrackerNotSeen_ThenReturnOwnedByMajorNetworkSpec() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = false
        settings.browsingMajorTrackingSiteShown = false
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.ownedByFacebook))

        // THEN
        XCTAssertEqual(result?.type, .siteOwnedByMajorTracker)
    }

    func testWhenDismissIsCalled_ThenLastVisitedOnboardingWebsiteAndLastShownDaxDialogAreSetToNil() {
        // GIVEN
        let sut = makeSUT(settings: MockDaxDialogsSettings())
        sut.setLastShownDialog(type: DaxDialogs.BrowsingSpec.fire.type)
        sut.setLastVisitedURL(URL(string: "https://www.example.com"))
        XCTAssertNotNil(sut.lastShownDaxDialogType)
        XCTAssertNotNil(sut.lastVisitedOnboardingWebsiteURL)

        // WHEN
        sut.dismiss()

        // THEN
        XCTAssertNil(sut.lastShownDaxDialogType)
        XCTAssertNil(sut.lastVisitedOnboardingWebsiteURL)
    }

    func testWhenSetDaxDialogDismiss_ThenLastVisitedOnboardingWebsiteAndLastShownDaxDialogAreSetToNil() {
        // GIVEN
        let sut = makeSUT(settings: MockDaxDialogsSettings())
        sut.setLastShownDialog(type: DaxDialogs.BrowsingSpec.fire.type)
        sut.setLastVisitedURL(URL(string: "https://www.example.com"))
        XCTAssertNotNil(sut.lastShownDaxDialogType)
        XCTAssertNotNil(sut.lastVisitedOnboardingWebsiteURL)

        // WHEN
        sut.setDaxDialogDismiss()

        // THEN
        XCTAssertNil(sut.lastShownDaxDialogType)
        XCTAssertNil(sut.lastVisitedOnboardingWebsiteURL)
    }

    func testWhenClearedBrowserDataIsCalled_ThenLastVisitedOnboardingWebsiteAndLastShownDaxDialogAreSetToNil() throws {
        // GIVEN
        let sut = makeSUT(settings: MockDaxDialogsSettings())
        sut.setLastShownDialog(type: DaxDialogs.BrowsingSpec.fire.type)
        sut.setLastVisitedURL(URL(string: "https://www.example.com"))
        XCTAssertNotNil(sut.lastShownDaxDialogType)
        XCTAssertNotNil(sut.lastVisitedOnboardingWebsiteURL)

        // WHEN
        sut.clearedBrowserData()

        // THEN
        XCTAssertNil(sut.lastShownDaxDialogType)
        XCTAssertNil(sut.lastVisitedOnboardingWebsiteURL)
    }

    func testWhenIsEnabledIsFalse_AndReloadWebsite_ThenReturnNilBrowsingSpec() throws {
        // GIVEN
        let lastVisitedWebsitePath = "https://www.example.com"
        let lastVisitedWebsiteURL = try XCTUnwrap(URL(string: lastVisitedWebsitePath))
        let sut = makeSUT(settings: MockDaxDialogsSettings())
        sut.setLastShownDialog(type: DaxDialogs.BrowsingSpec.fire.type)
        sut.setLastVisitedURL(lastVisitedWebsiteURL)
        sut.dismiss()

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: lastVisitedWebsiteURL))

        // THEN
        XCTAssertNil(result)
    }

    func testWhenIsEnabledIsCalled_AndShouldShowDaxDialogsIsTrue_ThenReturnTrue() {
        // GIVEN
        let sut = DaxDialogs(settings: settings, entityProviding: entityProvider, timeLimit: makeDisabledContextualOnboardingTimeLimit())

        // WHEN
        let result = sut.isEnabled

        // THEN
        XCTAssertTrue(result)
    }

    // MARK: - States

    func testWhenShouldDisplayPromotionAndHasNotSeenPromotion_OnNextHomeScreenMessageNew_ReturnsSubscriptionPromotion() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = true
        settings.subscriptionPromotionDialogShown = false
        let mockOnboardingPromotionHelper = MockOnboardingSubscriptionPromotionHelper()
        mockOnboardingPromotionHelper.shouldDisplayValue = true
        let sut = makeSUT(settings: settings, onboardingSubscriptionPromotionHelper: mockOnboardingPromotionHelper)

        // WHEN
        let result = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(result, .subscriptionPromotion)
    }

    func testWhenShouldNotDisplayPromotion_OnNextHomeScreenMessageNew_DoesNotReturnSubscriptionPromotion() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = true
        settings.subscriptionPromotionDialogShown = false
        let mockOnboardingPromotionHelper = MockOnboardingSubscriptionPromotionHelper()
        mockOnboardingPromotionHelper.shouldDisplayValue = false
        let sut = makeSUT(settings: settings, onboardingSubscriptionPromotionHelper: mockOnboardingPromotionHelper)

        // WHEN
        let result = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertNotEqual(result, .subscriptionPromotion)
    }

    func testWhenUserHasSeenPromotion_OnNextHomeScreenMessageNew_DoesNotReturnSubscriptionPromotion() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = true
        settings.subscriptionPromotionDialogShown = true
        let mockOnboardingPromotionHelper = MockOnboardingSubscriptionPromotionHelper()
        mockOnboardingPromotionHelper.shouldDisplayValue = true
        let sut = makeSUT(settings: settings, onboardingSubscriptionPromotionHelper: mockOnboardingPromotionHelper)

        // WHEN
        let result = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertNotEqual(result, .subscriptionPromotion)
    }

    func testWhenFinalDialogNotSeen_OnNextHomeScreenMessageNew_DoesNotReturnSubscriptionPromotion() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = false
        settings.subscriptionPromotionDialogShown = false
        let mockOnboardingPromotionHelper = MockOnboardingSubscriptionPromotionHelper()
        mockOnboardingPromotionHelper.shouldDisplayValue = true
        let sut = makeSUT(settings: settings, onboardingSubscriptionPromotionHelper: mockOnboardingPromotionHelper)

        // WHEN
        let result = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertNotEqual(result, .subscriptionPromotion)
    }

    // MARK: - Subscription Promotion Dialog Seen

    func testWhenSubscriptionPromotionDialogSeenIsSet_ThenSettingsValueIsUpdated() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)
        XCTAssertFalse(settings.subscriptionPromotionDialogShown)

        // WHEN
        sut.subscriptionPromotionDialogSeen = true

        // THEN
        XCTAssertTrue(settings.subscriptionPromotionDialogShown)
    }

    func testWhenSubscriptionPromotionDialogSeenIsGet_ThenSettingsValueIsReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.subscriptionPromotionDialogShown = true
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.subscriptionPromotionDialogSeen

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenCurrentHomeSpecIsSubscriptionPromotion_ThenIsShowingSubscriptionPromotionIsTrue() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = true
        settings.subscriptionPromotionDialogShown = false
        let mockOnboardingPromotionHelper = MockOnboardingSubscriptionPromotionHelper()
        mockOnboardingPromotionHelper.shouldDisplayValue = true
        let sut = makeSUT(settings: settings, onboardingSubscriptionPromotionHelper: mockOnboardingPromotionHelper)

        // WHEN
        _ = sut.nextHomeScreenMessageNew()
        let result = sut.isShowingSubscriptionPromotion

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenCurrentHomeSpecIsNotSubscriptionPromotion_ThenIsShowingSubscriptionPromotionIsFalse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.isShowingSubscriptionPromotion

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenCurrentHomeSpecIsFinal_ThenIsShowingSubscriptionPromotionIsFalse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        _ = sut.nextHomeScreenMessageNew()
        let result = sut.isShowingSubscriptionPromotion

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenURLVisitedIsMajorTracker_ThenSetTryVisitSuggestionSeenTrue() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingMajorTrackingSiteShown = false
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.facebook)
        XCTAssertFalse(settings.tryVisitASiteShown)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: privacyInfo)

        // THEN
        XCTAssertEqual(result?.type, .siteIsMajorTracker)
        XCTAssertTrue(settings.tryVisitASiteShown)
    }

    func testWhenURLVisitedIsOwnedByMajorTracker_ThenSetTryVisitSuggestionSeenTrue() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingMajorTrackingSiteShown = false
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.ownedByFacebook)
        XCTAssertFalse(settings.tryVisitASiteShown)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: privacyInfo)

        // THEN
        XCTAssertEqual(result?.type, .siteOwnedByMajorTracker)
        XCTAssertTrue(settings.tryVisitASiteShown)
    }

    func testWhenURLVisitedHasMultipleTrackers_ThenSetTryVisitSuggestionSeenFalse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = false
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.example)
        [URLs.google, URLs.amazon].forEach { tracker in
            let detectedTracker = detectedTrackerFrom(tracker, pageUrl: URLs.example.absoluteString)
            privacyInfo.trackerInfo.addDetectedTracker(detectedTracker, onPageWithURL: URLs.example)
        }
        XCTAssertFalse(settings.tryVisitASiteShown)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: privacyInfo)

        // THEN
        XCTAssertEqual(result?.type, .withMultipleTrackers)
        XCTAssertTrue(settings.tryVisitASiteShown)
    }

    func testWhenURLVisitedHasOneTracker_ThenSetTryVisitSuggestionSeenFalse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithTrackersShown = false
        let sut = makeSUT(settings: settings)
        let privacyInfo = makePrivacyInfo(url: URLs.example)
        let detectedTracker = detectedTrackerFrom(URLs.google, pageUrl: URLs.example.absoluteString)
        privacyInfo.trackerInfo.addDetectedTracker(detectedTracker, onPageWithURL: URLs.example)
        XCTAssertFalse(settings.tryVisitASiteShown)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: privacyInfo)

        // THEN
        XCTAssertEqual(result?.type, .withOneTracker)
        XCTAssertTrue(settings.tryVisitASiteShown)
    }

    func testWhenURLVisitedHasOneNoTrackers_ThenSetTryVisitSuggestionSeenFalse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingWithoutTrackersShown = false
        let sut = makeSUT(settings: settings)
        XCTAssertFalse(settings.tryVisitASiteShown)

        // WHEN
        let result = sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.example))

        // THEN
        XCTAssertEqual(result?.type, .withoutTrackers)
        XCTAssertTrue(settings.tryVisitASiteShown)
    }


    func testAfterTimeLimitOnlyBlockedTrackersDialogRemainsEligible() {
        let settings = MockDaxDialogsSettings()
        settings.browsingWithoutTrackersShown = true
        let sut = makeTimedOutSUT(settings: settings)

        for url in [URLs.ddg, URLs.example, URLs.facebook, URLs.ownedByFacebook] {
            XCTAssertNil(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: url)))
        }
        XCTAssertNil(sut.nextHomeScreenMessageNew())
        XCTAssertEqual(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfoWithBlockedTrackers(url: URLs.example))?.type, .withOneTracker)
        XCTAssertTrue(settings.browsingWithTrackersShown)
        XCTAssertFalse(sut.shouldShowFireButtonPulse)
        XCTAssertFalse(sut.shouldShowPrivacyButtonPulse)
        XCTAssertFalse(sut.isEnabled)
    }

    func testAfterTimeLimitSearchDoesNotShowTrackersDialogEvenWithBlockedTrackers() {
        let sut = makeTimedOutSUT()

        XCTAssertNil(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfoWithBlockedTrackers(url: URLs.ddg)))
        XCTAssertEqual(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfoWithBlockedTrackers(url: URLs.example))?.type, .withOneTracker)
    }

    func testAfterTimeLimitBlockedTrackersDialogCanReloadUntilDismissed() {
        let sut = makeTimedOutSUT()
        let info = makePrivacyInfoWithBlockedTrackers(url: URLs.example)

        XCTAssertEqual(sut.nextBrowsingMessageIfShouldShow(for: info)?.type, .withOneTracker)
        XCTAssertEqual(sut.nextBrowsingMessageIfShouldShow(for: info)?.type, .withOneTracker)
        sut.setDaxDialogDismiss()
        XCTAssertNil(sut.nextBrowsingMessageIfShouldShow(for: info))
        XCTAssertNil(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfoWithBlockedTrackers(url: URLs.amazon)))
    }

    func testAfterTimeLimitTrackersDialogDoesNotReturnAfterNavigatingAway() {
        let sut = makeTimedOutSUT()
        let info = makePrivacyInfoWithBlockedTrackers(url: URLs.example)

        XCTAssertEqual(sut.nextBrowsingMessageIfShouldShow(for: info)?.type, .withOneTracker)
        XCTAssertNil(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfo(url: URLs.amazon)))
        XCTAssertNil(sut.nextBrowsingMessageIfShouldShow(for: info))
    }

    func testAfterTimeLimitAlreadySeenTrackersDialogsSuppressException() {
        for sawMajorTracker in [true, false] {
            let settings = MockDaxDialogsSettings()
            settings.browsingMajorTrackingSiteShown = sawMajorTracker
            settings.browsingWithTrackersShown = !sawMajorTracker
            let sut = makeTimedOutSUT(settings: settings)

            XCTAssertNil(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfoWithBlockedTrackers(url: URLs.example)))
        }
    }

    func testAfterTimeLimitSkippedOnboardingSuppressesTrackersException() {
        let sut = makeTimedOutSUT(tutorialSettings: MockTutorialSettings(hasSeenOnboarding: true, hasSkippedOnboarding: true))

        XCTAssertNil(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfoWithBlockedTrackers(url: URLs.example)))
        XCTAssertNil(sut.nextHomeScreenMessageNew())
    }

    func testAfterTimeLimitMajorTrackerSiteUsesOnlyActualBlockedTrackersMessage() {
        let sut = makeTimedOutSUT()

        XCTAssertEqual(sut.nextBrowsingMessageIfShouldShow(for: makePrivacyInfoWithBlockedTrackers(url: URLs.facebook))?.type, .withOneTracker)
    }

    private func makeTimedOutSUT(settings: MockDaxDialogsSettings = MockDaxDialogsSettings(),
                                 tutorialSettings: TutorialSettings = MockTutorialSettings(hasSeenOnboarding: true)) -> DaxDialogs {
        let timeLimit = makeDisabledContextualOnboardingTimeLimit()
        timeLimit.endedByTimeLimit = true
        settings.isDismissed = true
        return DaxDialogs(settings: settings,
                          entityProviding: entityProvider,
                          variantManager: MockVariantManager(),
                          timeLimit: timeLimit,
                          tutorialSettings: tutorialSettings)
    }

    private func makePrivacyInfoWithBlockedTrackers(url: URL) -> PrivacyInfo {
        let info = makePrivacyInfo(url: url)
        let tracker = detectedTrackerFrom(URLs.google, pageUrl: url.absoluteString)
        info.trackerInfo.addDetectedTracker(tracker, onPageWithURL: url)
        return info
    }

    private func detectedTrackerFrom(_ url: URL, pageUrl: String) -> DetectedRequest {
        let entity = entityProvider.entity(forHost: url.host!)
        return DetectedRequest(url: url.absoluteString,
                               eTLDplus1: nil,
                               knownTracker: KnownTracker(domain: entity?.displayName,
                                                          defaultAction: .block,
                                                          owner: nil,
                                                          prevalence: nil,
                                                          subdomains: [],
                                                          categories: [],
                                                          rules: nil),
                               entity: entity,
                               state: .blocked,
                               pageUrl: pageUrl)
    }
    
    private func makePrivacyInfo(url: URL) -> PrivacyInfo {
        let protectionStatus = ProtectionStatus(unprotectedTemporary: false, enabledFeatures: [], allowlisted: false, denylisted: false)
        return PrivacyInfo(url: url,
                           parentEntity: entityProvider.entity(forHost: url.host!),
                           protectionStatus: protectionStatus)
    }

    private func makeSUT(settings: DaxDialogsSettings, onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping = MockOnboardingSubscriptionPromotionHelper()) -> DaxDialogs {
        DaxDialogs(settings: settings,
                   entityProviding: entityProvider,
                   variantManager: MockVariantManager(),
                   onboardingSubscriptionPromotionHelper: onboardingSubscriptionPromotionHelper,
                   timeLimit: makeDisabledContextualOnboardingTimeLimit())
    }
}

final class MockOnboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping {

    var proceedButtonText = ""

    var shouldDisplayValue: Bool = false

    var shouldDisplay: Bool {
        shouldDisplayValue
    }

    func redirectURLComponents(featurePage: DuckDuckGo.OnboardingSubscriptionPromotionPage?) -> URLComponents? {
        return nil
    }

    func fireImpressionPixel() {}

    func fireTapPixel() {}

    func fireDismissPixel() {}
}

func makeDisabledContextualOnboardingTimeLimit() -> ContextualOnboardingTimeLimit {
    ContextualOnboardingTimeLimit(store: InMemoryKeyValueStore(),
                                 featureFlagger: MockFeatureFlagger(),
                                 privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                 statisticsStore: MockStatisticsStore())
}

final class ContextualOnboardingTimeLimitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var store: InMemoryKeyValueStore!
    private var flagger: MockFeatureFlagger!
    private var configuration: MockPrivacyConfiguration!
    private var configurationManager: MockPrivacyConfigurationManager!
    private var statistics: MockStatisticsStore!

    override func setUp() {
        super.setUp()
        store = InMemoryKeyValueStore()
        flagger = MockFeatureFlagger(enabledFeatureFlags: [.contextualOnboardingTimeLimit])
        configuration = TimeLimitPrivacyConfiguration()
        configurationManager = MockPrivacyConfigurationManager()
        configurationManager.privacyConfig = configuration
        statistics = MockStatisticsStore()
    }

    func testDaysLimitIncludesExactBoundaryAndWinsWhenBothLimitsAreReached() {
        let limit = makeLimit()
        limit.startDate = now.addingTimeInterval(-7 * 86_400 + 1)
        XCTAssertNil(limit.reachedLimit())
        limit.startDate = now.addingTimeInterval(-7 * 86_400)
        XCTAssertEqual(limit.reachedLimit(), .days)
        limit.appOpens = 29
        XCTAssertEqual(limit.reachedLimit(), .days)
    }

    func testOpensLimitEndsOnTwentyNinthOpen() {
        let limit = makeLimit()
        for _ in 0..<28 { limit.recordAppOpen() }
        XCTAssertEqual(limit.appOpens, 28)
        XCTAssertNil(limit.reachedLimit())
        limit.recordAppOpen()
        XCTAssertEqual(limit.reachedLimit(), .appOpens)
    }

    func testFlagChangesDuringSessionUseAlreadyCountedOpens() {
        flagger.enabledFeatureFlags = []
        let limit = makeLimit()
        for _ in 0..<29 { limit.recordAppOpen() }
        XCTAssertNil(limit.reachedLimit())
        XCTAssertEqual(limit.appOpens, 29)
        flagger.enabledFeatureFlags = [.contextualOnboardingTimeLimit]
        XCTAssertEqual(limit.reachedLimit(), .appOpens)
        flagger.enabledFeatureFlags = []
        XCTAssertNil(limit.reachedLimit())
    }

    func testStartDateUsesInstallDateAndSurvivesStatisticsChangesAndNewInstances() {
        let installDate = now.addingTimeInterval(-3 * 86_400)
        statistics.installDate = installDate
        let limit = makeLimit()
        XCTAssertEqual(limit.startDate, installDate)
        limit.recordAppOpen()
        statistics.installDate = now
        XCTAssertEqual(makeLimit().startDate, installDate)
        XCTAssertEqual(makeLimit().appOpens, 1)
    }

    func testMissingInstallDateUsesFirstAccessDate() {
        statistics.installDate = nil
        XCTAssertEqual(makeLimit().startDate, now)
        statistics.installDate = now.addingTimeInterval(-10 * 86_400)
        XCTAssertEqual(makeLimit().startDate, now)
    }

    func testRemoteSettingsAreReadAgainDuringSession() {
        let limit = makeLimit()
        limit.appOpens = 3
        configuration.subfeatureSettings = #"{"maxDaysSinceInstall":10,"maxAppOpens":3}"#
        XCTAssertEqual(limit.maxDaysSinceInstall, 10)
        XCTAssertEqual(limit.maxAppOpens, 3)
        XCTAssertNil(limit.reachedLimit())
        configuration.subfeatureSettings = #"{"maxDaysSinceInstall":2,"maxAppOpens":2}"#
        XCTAssertEqual(limit.reachedLimit(), .appOpens)
    }

    func testMalformedRemoteLimitsFallBackToDefaults() {
        let limit = makeLimit()
        for value in ["null", "true", "false", "0", "-1", "1.5", "1e100", #""7""#] {
            configuration.subfeatureSettings = "{\"maxDaysSinceInstall\":\(value),\"maxAppOpens\":\(value)}"
            XCTAssertEqual(limit.maxDaysSinceInstall, 7, value)
            XCTAssertEqual(limit.maxAppOpens, 28, value)
        }
        configuration.subfeatureSettings = "not JSON"
        XCTAssertEqual(limit.maxDaysSinceInstall, 7)
        XCTAssertEqual(limit.maxAppOpens, 28)
        configuration.subfeatureSettings = #"{"maxDaysSinceInstall":1,"maxAppOpens":1}"#
        XCTAssertEqual(limit.maxDaysSinceInstall, 1)
        XCTAssertEqual(limit.maxAppOpens, 1)
    }

    func testDebugOverridesTakePrecedenceAndInvalidValuesAreIgnored() {
        configuration.subfeatureSettings = #"{"maxDaysSinceInstall":10,"maxAppOpens":20}"#
        let limit = makeLimit()
        limit.maxDaysOverride = 2
        limit.maxAppOpensOverride = 3
        XCTAssertEqual(limit.maxDaysSinceInstall, 2)
        XCTAssertEqual(limit.maxAppOpens, 3)
        XCTAssertEqual(makeLimit().maxAppOpens, 3)
        limit.maxDaysOverride = 0
        limit.maxAppOpensOverride = -1
        XCTAssertEqual(limit.maxDaysSinceInstall, 10)
        XCTAssertEqual(limit.maxAppOpens, 20)
    }

    func testLaunchOverridesTakePrecedenceOverDebugAndRemoteSettings() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        defaults.set("2", forKey: "contextualOnboardingMaxDays")
        defaults.set("3", forKey: "contextualOnboardingMaxAppOpens")
        defaults.set(String(now.addingTimeInterval(-8 * 86_400).timeIntervalSince1970), forKey: "contextualOnboardingStartDate")
        let limit = makeLimit(launchOptionsHandler: LaunchOptionsHandler(environment: [:], userDefaults: defaults, arguments: []))
        limit.maxDaysOverride = 10
        limit.maxAppOpensOverride = 20
        XCTAssertEqual(limit.maxDaysSinceInstall, 2)
        XCTAssertEqual(limit.maxAppOpens, 3)
        XCTAssertEqual(limit.startDate, now.addingTimeInterval(-8 * 86_400))
        XCTAssertEqual(limit.reachedLimit(), .days)
    }

    func testResetAndClearRemoveTimeLimitState() {
        let limit = makeLimit()
        limit.startDate = now.addingTimeInterval(-8 * 86_400)
        limit.appOpens = 100
        limit.endedByTimeLimit = true
        limit.maxDaysOverride = 1
        limit.reset()
        XCTAssertEqual(limit.startDate, now)
        XCTAssertEqual(limit.appOpens, 0)
        XCTAssertFalse(limit.endedByTimeLimit)
        XCTAssertEqual(limit.maxDaysOverride, 1)
        limit.clear()
        XCTAssertNil(limit.maxDaysOverride)
        XCTAssertNil(limit.maxAppOpensOverride)
        XCTAssertEqual(limit.appOpens, 0)
        XCTAssertFalse(limit.endedByTimeLimit)
    }

    func testInactiveOnboardingDoesNotCountOrEnd() {
        let settings = MockDaxDialogsSettings()
        settings.isDismissed = true
        let limit = makeLimit()
        limit.startDate = now.addingTimeInterval(-8 * 86_400)
        let reporter = TimeLimitReporter()
        let dialogs = makeDialogs(settings: settings, limit: limit, reporter: reporter)
        dialogs.recordForegroundOpen()
        XCTAssertNil(dialogs.nextHomeScreenMessageNew())
        XCTAssertEqual(limit.appOpens, 0)
        XCTAssertFalse(limit.endedByTimeLimit)
        XCTAssertTrue(reporter.reasons.isEmpty)
    }

    func testForegroundCountsWhileFlagIsOffAndNextDialogEndsAfterFlagTurnsOn() {
        flagger.enabledFeatureFlags = []
        let settings = MockDaxDialogsSettings()
        let limit = makeLimit()
        limit.maxAppOpensOverride = 1
        let reporter = TimeLimitReporter()
        let dialogs = makeDialogs(settings: settings, limit: limit, reporter: reporter)
        dialogs.recordForegroundOpen()
        dialogs.recordForegroundOpen()
        XCTAssertEqual(limit.appOpens, 2)
        XCTAssertTrue(dialogs.isEnabled)
        XCTAssertTrue(reporter.reasons.isEmpty)

        flagger.enabledFeatureFlags = [.contextualOnboardingTimeLimit]
        XCTAssertNil(dialogs.nextHomeScreenMessageNew())
        XCTAssertFalse(dialogs.isEnabled)
        XCTAssertEqual(reporter.reasons, [.appOpens])
    }

    func testOpenCountDoesNotOverflow() {
        let limit = makeLimit()
        limit.appOpens = Int.max
        limit.recordAppOpen()
        XCTAssertEqual(limit.appOpens, Int.max)
        XCTAssertEqual(limit.reachedLimit(), .appOpens)
    }

    func testTimeLimitDismissesOnceClearsDuckAICheckpointAndCannotBePrimedAgain() {
        let settings = MockDaxDialogsSettings()
        settings.isChatFirstPath = true
        let limit = makeLimit()
        limit.maxAppOpensOverride = 1
        let reporter = TimeLimitReporter()
        let checkpoint: any KeyedStoring<OnboardingStoringKeys> = InMemoryKeyValueStore().keyedStoring()
        checkpoint.resumeStep = .duckAIAnswerStep
        checkpoint.resumeDuckAIQueryPrompt = "test prompt"
        let dialogs = makeDialogs(settings: settings, limit: limit, reporter: reporter, checkpoint: checkpoint)
        var dismissals = [Bool]()
        let subscription = dialogs.isDismissedPublisher.sink {
            XCTAssertTrue(limit.endedByTimeLimit)
            dismissals.append($0)
        }

        dialogs.recordForegroundOpen()
        XCTAssertTrue(dialogs.isEnabled)
        dialogs.recordForegroundOpen()
        XCTAssertFalse(dialogs.isEnabled)
        XCTAssertTrue(settings.browsingFinalDialogShown)
        XCTAssertNil(checkpoint.resumeStep)
        XCTAssertNil(checkpoint.resumeDuckAIQueryPrompt)
        dialogs.recordForegroundOpen()
        dialogs.primeForUse()
        XCTAssertNil(dialogs.nextHomeScreenMessageNew())
        XCTAssertEqual(limit.appOpens, 2)
        XCTAssertEqual(dismissals, [true])
        XCTAssertEqual(reporter.reasons, [.appOpens])
        XCTAssertTrue(settings.isDismissed)
        withExtendedLifetime(subscription) {}
    }

    func testExpiredContextualCheckpointPreservesCompletedLinearOnboardingAfterClearing() {
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let limit = makeLimit()
        limit.startDate = now.addingTimeInterval(-8 * 86_400)
        let reporter = TimeLimitReporter()
        let checkpoint: any KeyedStoring<OnboardingStoringKeys> = InMemoryKeyValueStore().keyedStoring()
        checkpoint.resumeStep = .duckAIAnswerStep
        checkpoint.resumeDuckAIQueryPrompt = "saved contextual prompt"
        let dialogs = makeDialogs(settings: MockDaxDialogsSettings(), limit: limit,
                                  reporter: reporter, checkpoint: checkpoint,
                                  tutorialSettings: tutorialSettings)

        flagger.enabledFeatureFlags = []
        dialogs.checkTimeLimit()
        XCTAssertFalse(tutorialSettings.hasSeenOnboarding)
        XCTAssertEqual(checkpoint.resumeStep, .duckAIAnswerStep)
        XCTAssertEqual(checkpoint.resumeDuckAIQueryPrompt, "saved contextual prompt")

        flagger.enabledFeatureFlags = [.contextualOnboardingTimeLimit]
        limit.startDate = now
        dialogs.checkTimeLimit()
        XCTAssertFalse(tutorialSettings.hasSeenOnboarding)
        XCTAssertEqual(checkpoint.resumeStep, .duckAIAnswerStep)
        XCTAssertEqual(checkpoint.resumeDuckAIQueryPrompt, "saved contextual prompt")

        limit.startDate = now.addingTimeInterval(-8 * 86_400)
        dialogs.checkTimeLimit()
        dialogs.checkTimeLimit()

        XCTAssertFalse(dialogs.isEnabled)
        XCTAssertTrue(limit.endedByTimeLimit)
        XCTAssertTrue(tutorialSettings.hasSeenOnboarding)
        XCTAssertNil(checkpoint.resumeStep)
        XCTAssertNil(checkpoint.resumeDuckAIQueryPrompt)
        let startupDecision = StartupOnboardingDecision(onboardingStatus: .notOverridden,
                                                       tutorialSettings: tutorialSettings,
                                                       resumeStepStore: checkpoint)
        XCTAssertFalse(startupDecision.shouldShowOnboarding)
        XCTAssertEqual(reporter.reasons, [.days])
    }

    func testTimeLimitWaitsForLinearOnboardingAndPreservesItsCheckpoints() {
        for step in [OnboardingResumeStep.addressBarPositionSelection, .duckAIQuerySelection, .interludeDuckAI] {
            let limit = makeLimit()
            limit.reset()
            limit.startDate = now.addingTimeInterval(-7 * 86_400)
            let checkpoint: any KeyedStoring<OnboardingStoringKeys> = InMemoryKeyValueStore().keyedStoring()
            checkpoint.resumeStep = step
            checkpoint.resumeDuckAIQueryPrompt = "saved linear prompt"
            let reporter = TimeLimitReporter()
            let dialogs = makeDialogs(settings: MockDaxDialogsSettings(), limit: limit,
                                      reporter: reporter, checkpoint: checkpoint,
                                      tutorialSettings: MockTutorialSettings(hasSeenOnboarding: false))

            dialogs.recordForegroundOpen()

            XCTAssertTrue(dialogs.isEnabled)
            XCTAssertFalse(limit.endedByTimeLimit)
            XCTAssertEqual(limit.appOpens, 1)
            XCTAssertTrue(reporter.reasons.isEmpty)
            XCTAssertEqual(checkpoint.resumeStep, step)
            XCTAssertEqual(checkpoint.resumeDuckAIQueryPrompt, "saved linear prompt")
        }
    }

    func testTimeoutAfterLinearCompletionAppliesTheLaterSearchExperienceChoiceOnce() {
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let limit = makeLimit()
        limit.startDate = now.addingTimeInterval(-8 * 86_400)
        let reporter = TimeLimitReporter()
        let dialogs = makeDialogs(settings: MockDaxDialogsSettings(), limit: limit,
                                  reporter: reporter, tutorialSettings: tutorialSettings)
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatSearchInputUserSettingsEnabled: false)
        let choice = MockOnboardingSearchExperienceProvider()
        let handler = OnboardingSearchExperienceSelectionHandler(daxDialogs: dialogs,
                                                                 aiChatSettings: aiChatSettings,
                                                                 onboardingSearchExperienceProvider: choice)
        var dismissals = [Bool]()
        let subscription = dialogs.isDismissedPublisher.sink { dismissals.append($0) }

        dialogs.recordForegroundOpen()
        XCTAssertTrue(dialogs.isEnabled)
        XCTAssertTrue(dismissals.isEmpty)
        XCTAssertFalse(aiChatSettings.isAIChatSearchInputUserSettingsEnabled)

        choice.storeAIChatSearchInputDuringOnboardingChoice(enable: true)
        choice.didMakeChoiceDuringOnboarding = true
        dialogs.checkTimeLimit()
        XCTAssertTrue(dialogs.isEnabled)
        XCTAssertFalse(choice.didApplyOnboardingChoiceSettings)

        tutorialSettings.hasSeenOnboarding = true
        dialogs.checkTimeLimit()
        dialogs.checkTimeLimit()

        XCTAssertFalse(dialogs.isEnabled)
        XCTAssertTrue(limit.endedByTimeLimit)
        XCTAssertTrue(aiChatSettings.isAIChatSearchInputUserSettingsEnabled)
        XCTAssertTrue(choice.didApplyOnboardingChoiceSettings)
        XCTAssertEqual(limit.appOpens, 1)
        XCTAssertEqual(reporter.reasons, [.days])
        XCTAssertEqual(dismissals, [true])
        withExtendedLifetime((handler, subscription)) {}
    }

    func testHomeAndBrowsingEntryPointsCheckElapsedTimeWithoutCountingAnOpen() {
        for useHomeScreen in [true, false] {
            let limit = makeLimit()
            limit.clear()
            limit.startDate = now.addingTimeInterval(-7 * 86_400)
            let settings = MockDaxDialogsSettings()
            let reporter = TimeLimitReporter()
            let dialogs = makeDialogs(settings: settings, limit: limit, reporter: reporter)
            if useHomeScreen {
                XCTAssertNil(dialogs.nextHomeScreenMessageNew())
            } else {
                let status = ProtectionStatus(unprotectedTemporary: false, enabledFeatures: [], allowlisted: false, denylisted: false)
                let info = PrivacyInfo(url: URL(string: "https://duckduckgo.com?q=test")!, parentEntity: nil, protectionStatus: status)
                XCTAssertNil(dialogs.nextBrowsingMessageIfShouldShow(for: info))
            }
            XCTAssertTrue(settings.isDismissed)
            XCTAssertEqual(limit.appOpens, 0)
            XCTAssertEqual(reporter.reasons, [.days])
        }
    }

    private func makeLimit(launchOptionsHandler: LaunchOptionsHandler = LaunchOptionsHandler(environment: [:], arguments: [])) -> ContextualOnboardingTimeLimit {
        ContextualOnboardingTimeLimit(store: store,
                                     featureFlagger: flagger,
                                     privacyConfigurationManager: configurationManager,
                                     statisticsStore: statistics,
                                     launchOptionsHandler: launchOptionsHandler,
                                     dateProvider: { self.now })
    }

    private func makeDialogs(settings: MockDaxDialogsSettings,
                             limit: ContextualOnboardingTimeLimit,
                             reporter: TimeLimitReporter,
                             checkpoint: any KeyedStoring<OnboardingStoringKeys> = InMemoryKeyValueStore().keyedStoring(),
                             tutorialSettings: TutorialSettings = MockTutorialSettings(hasSeenOnboarding: true)) -> DaxDialogs {
        DaxDialogs(settings: settings,
                   entityProviding: MockEntityProvider(),
                   variantManager: MockVariantManager(),
                   launchOptionsHandler: LaunchOptionsHandler(environment: [:], arguments: []),
                   onboardingSubscriptionPromotionHelper: MockOnboardingSubscriptionPromotionHelper(),
                   timeLimit: limit,
                   timeLimitReporter: reporter,
                   onboardingResumeStepStore: checkpoint,
                   tutorialSettings: tutorialSettings)
    }

    private final class TimeLimitPrivacyConfiguration: MockPrivacyConfiguration {
        override func settings(for subfeature: any PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
            guard subfeature.parent == .iOSBrowserConfig,
                  subfeature.rawValue == "contextualOnboardingTimeLimit" else { return nil }
            return subfeatureSettings
        }
    }

    private final class TimeLimitReporter: OnboardingTimeLimitReporting {
        var reasons = [OnboardingSharedPixelEvent.TimeLimitReason]()

        func measureTimeLimitReached(_ reason: OnboardingSharedPixelEvent.TimeLimitReason) {
            reasons.append(reason)
        }
    }
}
