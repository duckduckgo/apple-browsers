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
import ContentBlocking
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
                                     variantManager: mockVariantManager)
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
                                    launchOptionsHandler: launchOptionsHandler)
        XCTAssertTrue(onboarding.isEnabled)

        let launchOptionsHandlerDisabled = LaunchOptionsHandler(environment: ["ONBOARDING": "false"])
        let onboardingDisabled = DaxDialogs(settings: settings,
                                            entityProviding: MockEntityProvider(),
                                            launchOptionsHandler: launchOptionsHandlerDisabled)
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
                                        variantManager: mockVariantManager)
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
        
        let onboarding = DaxDialogs(settings: settings, entityProviding: entityProvider)
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
        XCTAssertFalse(result.highlightAddressBar)
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
        XCTAssertFalse(result.highlightAddressBar)
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
            let sut = DaxDialogs(settings: settings, entityProviding: entityProvider)
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
        XCTAssertEqual(result2?.type, .fire)
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
        XCTAssertEqual(result2?.type, .fire)
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
        XCTAssertEqual(result2?.type, .fire)
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
        let sut = DaxDialogs(settings: settings, entityProviding: entityProvider)

        // WHEN
        let result = sut.isEnabled

        // THEN
        XCTAssertTrue(result)
    }

    // MARK: - States

    func testWhenUserIsInTreatmentCohortAndHasNotSeenPromotion_OnNextHomeScreenMessageNew_ReturnsPrivacyProPromotion() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = true
        settings.privacyProPromotionDialogShown = false
        let mockExperiment = MockOnboardingPrivacyProPromoExperimenting(cohort: .treatment)
        let sut = makeSUT(settings: settings, onboardingPrivacyProPromoExperiment: mockExperiment)

        // WHEN
        let result = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertEqual(result, .privacyProPromotion)
    }

    func testWhenUserIsInControlCohort_OnNextHomeScreenMessageNew_DoesNotReturnPrivacyProPromotion() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = true
        settings.privacyProPromotionDialogShown = false
        let mockExperiment = MockOnboardingPrivacyProPromoExperimenting(cohort: .control)
        let sut = makeSUT(settings: settings, onboardingPrivacyProPromoExperiment: mockExperiment)

        // WHEN
        let result = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertNotEqual(result, .privacyProPromotion)
    }

    func testWhenUserHasSeenPromotion_OnNextHomeScreenMessageNew_DoesNotReturnPrivacyProPromotion() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = true
        settings.privacyProPromotionDialogShown = true
        let mockExperiment = MockOnboardingPrivacyProPromoExperimenting(cohort: .treatment)
        let sut = makeSUT(settings: settings, onboardingPrivacyProPromoExperiment: mockExperiment)

        // WHEN
        let result = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertNotEqual(result, .privacyProPromotion)
    }

    func testWhenFinalDialogNotSeen_OnNextHomeScreenMessageNew_DoesNotReturnPrivacyProPromotion() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = false
        settings.privacyProPromotionDialogShown = false
        let mockExperiment = MockOnboardingPrivacyProPromoExperimenting(cohort: .treatment)
        let sut = makeSUT(settings: settings, onboardingPrivacyProPromoExperiment: mockExperiment)

        // WHEN
        let result = sut.nextHomeScreenMessageNew()

        // THEN
        XCTAssertNotEqual(result, .privacyProPromotion)
    }

    func testWhenPrivacyProPromotionDialogSeenIsSet_ThenSettingsValueIsUpdated() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)
        XCTAssertFalse(settings.privacyProPromotionDialogShown)

        // WHEN
        sut.privacyProPromotionDialogSeen = true

        // THEN
        XCTAssertTrue(settings.privacyProPromotionDialogShown)
    }

    func testWhenPrivacyProPromotionDialogSeenIsGet_ThenSettingsValueIsReturned() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.privacyProPromotionDialogShown = true
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.privacyProPromotionDialogSeen

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenCurrentHomeSpecIsPrivacyProPromotion_ThenIsShowingPrivacyProPromotionIsTrue() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        settings.browsingFinalDialogShown = true
        settings.privacyProPromotionDialogShown = false
        let mockExperiment = MockOnboardingPrivacyProPromoExperimenting(cohort: .treatment)
        let sut = makeSUT(settings: settings, onboardingPrivacyProPromoExperiment: mockExperiment)

        // WHEN
        _ = sut.nextHomeScreenMessageNew()
        let result = sut.isShowingPrivacyProPromotion

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenCurrentHomeSpecIsNotPrivacyProPromotion_ThenIsShowingPrivacyProPromotionIsFalse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        let result = sut.isShowingPrivacyProPromotion

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenCurrentHomeSpecIsFinal_ThenIsShowingPrivacyProPromotionIsFalse() {
        // GIVEN
        let settings = MockDaxDialogsSettings()
        let sut = makeSUT(settings: settings)

        // WHEN
        _ = sut.nextHomeScreenMessageNew()
        let result = sut.isShowingPrivacyProPromotion

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

    private func makeSUT(settings: DaxDialogsSettings, onboardingPrivacyProPromoExperiment: OnboardingPrivacyProPromoExperimenting = MockOnboardingPrivacyProPromoExperimenting(cohort: .control)) -> DaxDialogs {
        DaxDialogs(settings: settings,
                   entityProviding: entityProvider,
                   variantManager: MockVariantManager(),
                   onboardingPrivacyProPromoExperiment: onboardingPrivacyProPromoExperiment)
    }
}

class MockOnboardingPrivacyProPromoExperimenting: OnboardingPrivacyProPromoExperimenting {
    private let cohort: PrivacyProOnboardingCTAMarch25Cohort?
    private(set) var fireSubscriptionStartedMonthlyPixelCalled = false
    private(set) var fireSubscriptionStartedYearlyPixelCalled = false

    init(cohort: PrivacyProOnboardingCTAMarch25Cohort?) {
        self.cohort = cohort
    }

    func getCohortIfEnabled() -> PrivacyProOnboardingCTAMarch25Cohort? {
        return cohort
    }

    func redirectURLComponents() -> URLComponents? {
        return nil
    }

    func fireImpressionPixel() {
    }

    func fireTapPixel() {
    }

    func fireDismissPixel() {
    }

    func fireSubscriptionStartedMonthlyPixel() {
        fireSubscriptionStartedMonthlyPixelCalled = true
    }

    func fireSubscriptionStartedYearlyPixel() {
        fireSubscriptionStartedYearlyPixelCalled = true
    }
}
