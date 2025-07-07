//
//  ContextualDialogsManagerTests.swift
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
import Testing
import PrivacyDashboard
@testable import DuckDuckGo_Privacy_Browser

class ContextualDialogsManagerTests {
    var manager: ContextualDialogsManager!
    var trackerProvider: MockTrackerMessageProvider!
    var stateStorage: MockContextualDialogStateStoring!
    let expectation = XCTestExpectation()

    init() {
        stateStorage = MockContextualDialogStateStoring()
        trackerProvider = MockTrackerMessageProvider(expectation: expectation)
        manager = ContextualDialogsManager(trackerMessageProvider: trackerProvider, stateStorage: stateStorage)
        trackerProvider.trackerType = .blockedTrackers(entityNames: ["Tracker1"])
    }

    @Test("Default state for contextual onboarding is completed")
    func testDefaultStateIsOnboardingCompleted() {
        XCTAssertEqual(manager.state, .onboardingCompleted)
    }

    // MARK: - NewTab

    @Test("The first time New Tab is shown will show tryASearch dialog")
    func testNewTabInitialShowsTryASearch() async {
        manager.state = .notStarted
        let tab = await Tab(content: .newtab)

        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)

        XCTAssertEqual(dialog, .tryASearch)
    }

    @Test("New Tab Page show TryASearch dialog when expected", arguments: [1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31])
    func testOnNewTabPageShowsTryASearch2(contextualDialogsSeenKey: Int) async throws {
        manager.state = .notStarted
        let tab = await Tab(content: .newtab)
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .tryASearch)
    }

    @Test("New Tab Page show TryASite dialog when expected", arguments: [2, 4, 18, 20])
    func testOnNewTabPageShowsTryASite(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .newtab)
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .tryASite)
    }

    @Test("New Tab Page show HighFive dialog when expected", arguments: [26, 28, 30, 32])
    func testOnNewTabPageShowsHighFive(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .newtab)
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .highFive)
    }

    @Test("New Tab Page show no dialog when expected", arguments: [6, 8, 10, 12, 14, 16, 22, 24, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64])
    func testOnNewTabPageShowsNothing(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .newtab)
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == nil)
    }

    // MARK: - On Site Visit

    @Test("Site Visit shows tryASearch dialog when expected", arguments: [1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31])
    func testOnSiteVisitShowsTryASearch(contextualDialogsSeenKey: Int) async {
        manager.state = .notStarted
        let tab = await Tab(content: .url(URL.duckDuckGo, credential: nil, source: .ui))
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .tryASearch)
    }

    @Test("Site Visit shows highFive dialog when expected", arguments: [26, 28, 30, 32])
    func testOnSiteVisitShowsHighFive(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.duckDuckGo, credential: nil, source: .ui))
        stateStorage.blockedTrackerSeen = true
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .highFive)
    }

    @Test("Site Visit shows tryFireButton dialog when expected", arguments: [10, 12, 14, 16])
    func testOnSiteVisitShowsTryFireButton(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.duckDuckGo, credential: nil, source: .ui))
        stateStorage.blockedTrackerSeen = true
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .tryFireButton)
    }

    @Test("Site Visit shows Trackers dialog (follow up on) when expected", arguments: [2, 4, 6, 8])
    func testOnSiteVisitShowsTrackersFollowUp(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.duckDuckGo, credential: nil, source: .ui))
        stateStorage.blockedTrackerSeen = false
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .trackers(message: trackerProvider.message, shouldFollowUp: true))
    }

    @Test("Site Visit shows Trackers dialog (follow up off) when expected", arguments: [18, 20, 22, 24])
    func testOnSiteVisitShowsTrackersNoFollowUp(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.duckDuckGo, credential: nil, source: .ui))
        stateStorage.blockedTrackerSeen = false
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .trackers(message: trackerProvider.message, shouldFollowUp: false))
    }

    @Test("Site Visit does not show tracker dialog (with blocked trackers) twice")
    func testOnSiteVisitIfItHasSeenTrackersBlockedItDoesNotShowItAgain() async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.duckDuckGo, credential: nil, source: .ui))
        stateStorage.blockedTrackerSeen = false

        // First Site Visit
        stateStorage.contextualDialogsSeen = combinationDictionary[2]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .trackers(message: trackerProvider.message, shouldFollowUp: true))

        // Second Site Visit
        let dialog2 = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog2 != .trackers(message: trackerProvider.message, shouldFollowUp: true))
    }

    @Test("Site Visit does not show tracker dialog (with no blocked trackers) twice")
    func testOnSiteVisitIfItHasNotSeenTrackersBlockedItDoesNotShowOtherTrackerDialogWithNoTeckersBlocked() async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.duckDuckGo, credential: nil, source: .ui))
        stateStorage.blockedTrackerSeen = false

        // First Site Visit
        trackerProvider.trackerType = .majorTracker
        stateStorage.contextualDialogsSeen = combinationDictionary[2]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .trackers(message: trackerProvider.message, shouldFollowUp: true))

        // Second Site Visit
        let dialog2 = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog2 != .trackers(message: trackerProvider.message, shouldFollowUp: true))
    }

    @Test("Site Visit shows tracker dialog (with blocked trackers) even if previously has shown a different tracker dialog")
    func testOnSiteVisitIfItHasNotSeenTrackersBlockedItShowsTrackerDialogAgainIfTrackersBlocked() async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.duckDuckGo, credential: nil, source: .ui))
        stateStorage.blockedTrackerSeen = false

        // First Site Visit
        trackerProvider.trackerType = .majorTracker
        stateStorage.contextualDialogsSeen = combinationDictionary[2]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .trackers(message: trackerProvider.message, shouldFollowUp: true))

        // Second Site Visit
        trackerProvider.trackerType = .blockedTrackers(entityNames: ["Tracker1"])
        let dialog2 = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog2 == .trackers(message: trackerProvider.message, shouldFollowUp: true))
    }

    @Test("Site Visit shows no dialog when expected", arguments: [33, 35, 37, 39, 41, 43, 45, 47, 49, 51, 53, 55, 57, 59, 61, 63, 64])
    func testOnSiteVisitShowsNothing(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.duckDuckGo, credential: nil, source: .ui))
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == nil)
    }

    // MARK: - On Search Combinations

    @Test("Search shows searchDone dialog (follow up on) when expected", arguments: [2, 18])
    func testOnSearchShowsSearchDoneShouldFollowUp(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.makeSearchUrl(from: "query something")!, credential: nil, source: .ui))
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .searchDone(shouldFollowUp: true))
    }

    @Test("Search shows searchDone dialog (follow up off) when expected", arguments: [6, 10, 14, 22, 26, 30])
    func testOnSearchShowsSearchDoneShouldNotFollowUp(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.makeSearchUrl(from: "query something")!, credential: nil, source: .ui))
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .searchDone(shouldFollowUp: false))
    }

    @Test("Search shows highFive dialog when expected", arguments: [28, 32])
    func testOnSearchShowsHighFive(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.makeSearchUrl(from: "query something")!, credential: nil, source: .ui))
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == .highFive)
    }

    @Test("Search shows no dialog when expected", arguments: [1, 3, 4, 5, 7, 8, 9, 11, 12, 13, 15, 16, 17, 19, 20, 21, 23, 24, 25, 27, 29, 31, 33, 35, 37, 39, 41, 43, 45, 47, 49, 51, 53, 55, 57, 59, 61, 63, 64])
    func testOnSearchWhenTryASearchNotSeenShowsNothing(contextualDialogsSeenKey: Int) async {
        manager.state = .ongoing
        let tab = await Tab(content: .url(URL.makeSearchUrl(from: "query something")!, credential: nil, source: .ui))
        stateStorage.contextualDialogsSeen = combinationDictionary[contextualDialogsSeenKey]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        #expect(dialog == nil)
    }

    let combinationDictionary: [Int: [String]] = [
        1: [], // TryASearch
        2: ["tryASearch"], // NT -> TryASite // Search -> SearchDone followUp // Site -> Trackers
        3: ["searchDone"], // TryASearch
        4: ["tryASearch", "searchDone"], // NT -> TryASite // Search -> Nothing // Site -> Trackers
        5: ["tryASite"], // TryASearch
        6: ["tryASearch", "tryASite"], // NT -> Nothing // Search -> SearchDone followUp false // Site -> Trackers
        7: ["searchDone", "tryASite"], // TryASearch
        8: ["tryASearch", "searchDone", "tryASite"], // NT -> Nothing // Search -> Nothing // Site -> Trackers
        9: ["trackers"], // TryASearch
        10: ["tryASearch", "trackers"], // NT -> Nothing // Search -> Nothing followUp false // Site -> TryFireButton
        11: ["searchDone", "trackers"], // TryASearch
        12: ["tryASearch", "searchDone", "trackers"], // NT -> Nothing // Search -> TryFireButton // Site -> TryFireButton
        13: ["tryASite", "trackers"], // TryASearch
        14: ["tryASearch", "tryASite", "trackers"], // NT -> Nothing // Search -> SearchDone followUp false // Site -> TryFireButton
        15: ["searchDone", "tryASite", "trackers"], // TryASearch
        16: ["tryASearch", "searchDone", "tryASite", "trackers"], // NT -> Nothing // Search -> TryFireButton // Site -> TryFireButton
        17: ["tryFireButton"], // TryASearch
        18: ["tryASearch", "tryFireButton"], // NT -> TryASite // Search -> SearchDone followUp true // Site -> Trackers No follow up
        19: ["searchDone", "tryFireButton"], // TryASearch
        20: ["tryASearch", "searchDone", "tryFireButton"], // NT -> Nothing // Search -> Nothing // Site -> Trackers No follow up
        21: ["tryASite", "tryFireButton"], // TryASearch
        22: ["tryASearch", "tryASite", "tryFireButton"], // NT -> Nothing // Search -> SearchDone followUp false // Site -> Trackers No follow up
        23: ["searchDone", "tryASite", "tryFireButton"], // TryASearch
        24: ["tryASearch", "searchDone", "tryASite", "tryFireButton"], // NT -> Nothing // Search -> Nothing // Site -> Trackers No follow up
        25: ["trackers", "tryFireButton"], // TryASearch
        26: ["tryASearch", "trackers", "tryFireButton"], // NT -> HighFive // Search -> Search Done followUp false // Site -> High Five
        27: ["searchDone", "trackers", "tryFireButton"], // TryASearch
        28: ["tryASearch", "searchDone", "trackers", "tryFireButton"], // NT -> HighFive // Search -> HighFive // Site -> High Five
        29: ["tryASite", "trackers", "tryFireButton"], // TryASearch
        30: ["tryASearch", "tryASite", "trackers", "tryFireButton"], // NT -> HighFive // Search -> Search Done followUp false // Site -> High Five
        31: ["searchDone", "tryASite", "trackers", "tryFireButton"], // TryASearch
        32: ["tryASearch", "searchDone", "tryASite", "trackers", "tryFireButton"], // NT -> HighFive // Search -> HighFive // Site -> High Five
        33: ["highFive"], // TryASearch // HighFive
        34: ["tryASearch", "highFive"], // HighFive
        35: ["searchDone", "highFive"], // TryASearch // HighFive
        36: ["tryASearch", "searchDone", "highFive"], // HighFive
        37: ["tryASite", "highFive"], // TryASearch // HighFive
        38: ["tryASearch", "tryASite", "highFive"], // HighFive
        39: ["searchDone", "tryASite", "highFive"], // TryASearch // HighFive
        40: ["tryASearch", "searchDone", "tryASite", "highFive"], // HighFive
        41: ["trackers", "highFive"], // TryASearch // HighFive
        42: ["tryASearch", "trackers", "highFive"], // HighFive
        43: ["searchDone", "trackers", "highFive"], // TryASearch // HighFive
        44: ["tryASearch", "searchDone", "trackers", "highFive"], // HighFive
        45: ["tryASite", "trackers", "highFive"], // TryASearch // HighFive
        46: ["tryASearch", "tryASite", "trackers", "highFive"], // HighFive
        47: ["searchDone", "tryASite", "trackers", "highFive"], // TryASearch // HighFive
        48: ["tryASearch", "searchDone", "tryASite", "trackers", "highFive"], // HighFive
        49: ["tryFireButton", "highFive"], // TryASearch // HighFive
        50: ["tryASearch", "tryFireButton", "highFive"], // HighFive
        51: ["searchDone", "tryFireButton", "highFive"], // TryASearch // HighFive
        52: ["tryASearch", "searchDone", "tryFireButton", "highFive"], // HighFive
        53: ["tryASite", "tryFireButton", "highFive"], // TryASearch // HighFive
        54: ["tryASearch", "tryASite", "tryFireButton", "highFive"], // HighFive
        55: ["searchDone", "tryASite", "tryFireButton", "highFive"], // TryASearch // HighFive
        56: ["tryASearch", "searchDone", "tryASite", "tryFireButton", "highFive"], // HighFive
        57: ["trackers", "tryFireButton", "highFive"], // TryASearch // HighFive
        58: ["tryASearch", "trackers", "tryFireButton", "highFive"], // HighFive
        59: ["searchDone", "trackers", "tryFireButton", "highFive"], // TryASearch // HighFive
        60: ["tryASearch", "searchDone", "trackers", "tryFireButton", "highFive"], // TryASearch // HighFive
        61: ["tryASite", "trackers", "tryFireButton", "highFive"], // TryASearch // HighFive
        62: ["tryASearch", "tryASite", "trackers", "tryFireButton", "highFive"], // HighFive
        63: ["searchDone", "tryASite", "trackers", "tryFireButton", "highFive"], // TryASearch // HighFive
        64: ["tryASearch", "searchDone", "tryASite", "trackers", "tryFireButton", "highFive"] // HighFive
    ]
}

class MockTrackerMessageProvider: TrackerMessageProviding {

    let expectation: XCTestExpectation?
    var message: NSAttributedString
    var trackerType: OnboardingTrackersType?

    init(expectation: XCTestExpectation? = nil, message: NSAttributedString = NSAttributedString(string: "Trackers Detected"), trackerType: OnboardingTrackersType? = .blockedTrackers(entityNames: ["entity1", "entity2"])) {
        self.expectation = expectation
        self.message = message
        self.trackerType = trackerType
    }

    func trackerMessage(privacyInfo: PrivacyInfo?) -> NSAttributedString? {
        // Simulate fetching the tracker message
        expectation?.fulfill()
        return message
    }

    func trackersType(privacyInfo: PrivacyInfo?) -> OnboardingTrackersType? {
        // Simulate fetching the tracker type
        return trackerType
    }
}

class MockContextualDialogStateStoring: ContextualOnboardingStateStoring {
    var fireButtonUsedOnce: Bool = false

    var blockedTrackerSeen: Bool = false

    var contextualDialogsSeen: [String] = []

    var stateString: String = ""
}
