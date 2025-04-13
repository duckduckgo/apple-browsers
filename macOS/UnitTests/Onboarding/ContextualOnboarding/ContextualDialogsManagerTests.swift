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
import PrivacyDashboard
@testable import DuckDuckGo_Privacy_Browser

class ContextualDialogsManagerTests: XCTestCase {
    var manager: ContextualDialogsManager!
    var trackerProvider: MockTrackerMessageProvider!
    var stateStorage: MockContextualDialogStateStoring!
    let expectation = XCTestExpectation()

    override func setUp() {
        super.setUp()
        stateStorage = MockContextualDialogStateStoring()
        trackerProvider = MockTrackerMessageProvider(expectation: expectation)
        manager = ContextualDialogsManager(trackerMessageProvider: trackerProvider, stateStorage: stateStorage)
        trackerProvider.trackerType = .blockedTrackers(entityNames: ["Tracker1"])
    }

    override func tearDown() {
        manager = nil
        trackerProvider = nil
        stateStorage = nil
        super.tearDown()
    }

    func testDefaultStateIsOnboardingCompleted() {
        XCTAssertEqual(manager.state, .onboardingCompleted)
    }

    // MARK: - NewTab Combinations

    @MainActor
    func testNewTabInitialShowsTryASearch() {
        manager.state = .notStarted
        let tab = Tab(content: .newtab)

        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)

        XCTAssertEqual(dialog, .tryASearch)
    }

    @MainActor
    func testOnNewTabPageShowsTryASearch() {
        manager.state = .notStarted
        let tab = Tab(content: .newtab)
        let keys = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31]
        for key in keys {
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .tryASearch)
        }
    }

    @MainActor
    func testOnNewTabPageShowsTryASite() {
        manager.state = .ongoing
        let tab = Tab(content: .newtab)
        let keys = [2, 4, 18, 20]
        for key in keys {
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .tryASite)
        }
    }

    @MainActor
    func testOnNewTabPageShowsHighFive() {
        manager.state = .ongoing
        let tab = Tab(content: .newtab)
        let keys = [26, 28, 30, 32]
        for key in keys {
            manager.state = .ongoing
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .highFive)
        }
    }

    @MainActor
    func testOnNewTabPageShowsNothing() {
        let tab = Tab(content: .newtab)
        let keys = [6, 8, 10, 12, 14, 16, 22, 24, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64]
        for key in keys {
            manager.state = .ongoing
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertNil(dialog, "\(key)")
        }
    }

    // MARK: - On Site Visit Combinations

    @MainActor
    func testOnSiteVisitShowsTryASearch() {
        manager.state = .notStarted
        let tab = Tab(content: .newtab)
        tab.url = URL.duckDuckGo
        let keys = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31]
        for key in keys {
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .tryASearch, "\(key)")
        }
    }

    @MainActor
    func testOnSiteVisitShowsHighFive() {
        manager.state = .notStarted
        let tab = Tab(content: .newtab)
        tab.url = URL.duckDuckGo
        stateStorage.blockedTrackerSeen = true

        let keys = [26, 28, 30, 32]
        for key in keys {
            manager.state = .ongoing
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .highFive, "\(key)")
        }
    }

    @MainActor
    func testOnSiteVisitShowsTryFireButton() {
        manager.state = .ongoing
        let tab = Tab(content: .newtab)
        tab.url = URL.duckDuckGo
        stateStorage.blockedTrackerSeen = true

        let keys = [10, 12, 14, 16]
        for key in keys {
            manager.state = .ongoing
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .tryFireButton, "\(key)")
        }
    }

    @MainActor
    func testOnSiteVisitShowsTrackersFollowUp() {
        manager.state = .ongoing
        let tab = Tab(content: .newtab)
        tab.url = URL.duckDuckGo

        let keys = [2, 4, 6, 8]
        for key in keys {
            stateStorage.blockedTrackerSeen = false
            manager.state = .ongoing
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .trackers(message: trackerProvider.message, shouldFollowUp: true), "\(key)")
        }
    }

    @MainActor
    func testOnSiteVisitShowsTrackersNoFollowUp() {
        manager.state = .ongoing
        let tab = Tab(content: .newtab)
        tab.url = URL.duckDuckGo

        let keys = [18, 20, 22, 24]
        for key in keys {
            stateStorage.blockedTrackerSeen = false
            manager.state = .ongoing
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .trackers(message: trackerProvider.message, shouldFollowUp: false), "\(key)")
        }
    }

    @MainActor
    func testOnSiteVisitIfItHasSeenTrackersBlockedItDoesNotShowItAgain() {
        manager.state = .ongoing
        let tab = Tab(content: .newtab)
        tab.url = URL.duckDuckGo
        stateStorage.blockedTrackerSeen = false

        // First Site Visit
        stateStorage.contextualDialogsSeen = combinationDictionary[2]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        XCTAssertEqual(dialog, .trackers(message: trackerProvider.message, shouldFollowUp: true))

        // Second Site Visit
        let dialog2 = manager.dialogTypeForTab(tab, privacyInfo: nil)
        XCTAssertNotEqual(dialog2, .trackers(message: trackerProvider.message, shouldFollowUp: true))
    }

    @MainActor
    func testOnSiteVisitIfItHasNotSeenTrackersBlockedItShowsDoesNotShowOtherTrackerDialogWithNoTeckersBlocked() {
        manager.state = .ongoing
        let tab = Tab(content: .newtab)
        tab.url = URL.duckDuckGo
        stateStorage.blockedTrackerSeen = false

        // First Site Visit
        trackerProvider.trackerType = .majorTracker
        stateStorage.contextualDialogsSeen = combinationDictionary[2]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        XCTAssertEqual(dialog, .trackers(message: trackerProvider.message, shouldFollowUp: true))

        // Second Site Visit
        let dialog2 = manager.dialogTypeForTab(tab, privacyInfo: nil)
        XCTAssertNotEqual(dialog2, .trackers(message: trackerProvider.message, shouldFollowUp: true))
    }

    @MainActor
    func testOnSiteVisitIfItHasNotSeenTrackersBlockedItShowsTrackerDialogAgainIfTrackersBlocked() {
        manager.state = .ongoing
        let tab = Tab(content: .newtab)
        tab.url = URL.duckDuckGo
        stateStorage.blockedTrackerSeen = false

        // First Site Visit
        trackerProvider.trackerType = .majorTracker
        stateStorage.contextualDialogsSeen = combinationDictionary[2]!
        let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
        XCTAssertEqual(dialog, .trackers(message: trackerProvider.message, shouldFollowUp: true))

        // Second Site Visit
        trackerProvider.trackerType = .blockedTrackers(entityNames: ["Tracker1"])
        let dialog2 = manager.dialogTypeForTab(tab, privacyInfo: nil)
        XCTAssertEqual(dialog2, .trackers(message: trackerProvider.message, shouldFollowUp: true))
    }

    @MainActor
    func testOnSiteVisitShowsNothing() {
        let tab = Tab(content: .newtab)
        tab.url = URL.duckDuckGo
        let keys = [33, 35, 37, 39, 41, 43, 45, 47, 49, 51, 53, 55, 57, 59, 61, 63, 64]
        for key in keys {
            manager.state = .ongoing
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertNil(dialog, "\(key)")
        }
    }

    // MARK: - On Search Combinations

    @MainActor
    func testOnSearchShowsSearchDoneShouldFollowUp() {
        manager.state = .notStarted
        let tab = Tab(content: .newtab)
        tab.url = URL.makeSearchUrl(from: "query something")
        let keys = [2, 18]
        for key in keys {
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .searchDone(shouldFollowUp: true))
        }
    }

    @MainActor
    func testOnSearchShowsSearchDoneShouldNotFollowUp() {
        manager.state = .notStarted
        let tab = Tab(content: .newtab)
        tab.url = URL.makeSearchUrl(from: "query something")
        let keys = [6, 10, 14, 22, 26, 30]
        for key in keys {
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .searchDone(shouldFollowUp: false), "\(key)")
        }
    }

    @MainActor
    func testOnSearchShowsTryFireButton() {
        manager.state = .notStarted
        let tab = Tab(content: .newtab)
        tab.url = URL.makeSearchUrl(from: "query something")
        let keys = [12, 16]
        for key in keys {
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .tryFireButton, "\(key)")
        }
    }

    @MainActor
    func testOnSearchShowsHighFive() {
        let tab = Tab(content: .newtab)
        tab.url = URL.makeSearchUrl(from: "query something")
        let keys = [28, 32]
        for key in keys {
            manager.state = .ongoing
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertEqual(dialog, .highFive, "\(key)")
        }
    }

    @MainActor
    func testOnSearchWhenTryASearchNotSeenShowsNothing() {
        let tab = Tab(content: .newtab)
        tab.url = URL.makeSearchUrl(from: "query something")
        let keys = [1, 3, 4, 5, 7, 8, 9, 11, 13, 15, 17, 19, 20, 21, 23, 24, 25, 27, 29, 31, 33, 35, 37, 39, 41, 43, 45, 47, 49, 51, 53, 55, 57, 59, 61, 63, 64]
        for key in keys {
            manager.state = .ongoing
            stateStorage.contextualDialogsSeen = combinationDictionary[key]!
            let dialog = manager.dialogTypeForTab(tab, privacyInfo: nil)
            XCTAssertNil(dialog, "\(key)")
        }
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

    let expectation: XCTestExpectation
    var message: NSAttributedString
    var trackerType: OnboardingTrackersType?

    init(expectation: XCTestExpectation, message: NSAttributedString = NSAttributedString(string: "Trackers Detected"), trackerType: OnboardingTrackersType? = .blockedTrackers(entityNames: ["entity1", "entity2"])) {
        self.expectation = expectation
        self.message = message
        self.trackerType = trackerType
    }

    func trackerMessage(privacyInfo: PrivacyInfo?) -> NSAttributedString? {
        // Simulate fetching the tracker message
        expectation.fulfill()
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
