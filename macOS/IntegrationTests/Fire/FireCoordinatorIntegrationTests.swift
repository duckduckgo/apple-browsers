//
//  FireCoordinatorIntegrationTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AppKit
import History
import HistoryView
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class FireCoordinatorIntegrationTests: XCTestCase {

    private var dialogExpectedInput: DialogExpectedInput?
    private var lastDialogScopeDomains: Set<String> = []
    private var mockHistoryProvider: MockHistoryViewDataProvider!
    private var mockFireproofDomains: MockFireproofDomains!
    private var coordinator: FireCoordinator!
    private var window: MockWindow!
    private var fire: FireMock!

    // Options returned from the mocked Fire dialog's onConfirm
    private var dialogConfirmedOptions: FireDialogResult = .init(clearingOption: .allData,
                                                                 includeHistory: true,
                                                                 includeTabsAndWindows: false,
                                                                 includeCookiesAndSiteData: true,
                                                                 includeChatHistory: false,
                                                                 selectedCookieDomains: nil,
                                                                 selectedVisits: nil,
                                                                 isToday: false)

    override func setUp() {
        super.setUp()
        FireDialogViewModel.resetPersistedDefaults()
        mockHistoryProvider = MockHistoryViewDataProvider()
        mockHistoryProvider.configureWithTestData()
        XCTAssertFalse(mockHistoryProvider.allCookieDomains.isEmpty)

        mockFireproofDomains = MockFireproofDomains(domains: ["duckduckgo.com", "github.com", "nonvisited.com"])
        XCTAssertFalse(fireproofDomains.isEmpty)
        XCTAssertTrue(Set(fireproofDomains).intersects(allCookieDomains))
        XCTAssertNotEqual(Set(fireproofDomains).intersection(allCookieDomains).count, fireproofDomains.count)

        fire = FireMock()
        coordinator = makeCoordinator(with: fire)
        window = MockWindow()
    }

    override func tearDown() {
        super.tearDown()
        window = nil
        fire = nil
        coordinator = nil
        mockHistoryProvider = nil
        mockFireproofDomains = nil
    }

    // MARK: - History (All)

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     Entry: History (All)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=true; hist: visible, default=true; data: visible, default=true; chats: visible, default=false
     - fireproof: visible; history link: hidden
     - title: "Delete all history?"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visitsCountSource: 12
     User input:
     - scope: All (Unsupported); tabs: true; hist: true; data: true; selectedDomains: nil (all)
     Expectation:
     - burnAll
     */
    func testHistoryAll_AllData_WithTabsAndHistory_CallsBurnAll() async throws {
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.all)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false)
        let response = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.all)), in: window)
        if case .burn(let opts?) = response { XCTAssertTrue(opts.includeTabsAndWindows) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        let call = try XCTUnwrap(fire.burnAllCalls.onlyValue)
        XCTAssertEqual(call.isBurnOnExit, false)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     Entry: History (All)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=true; hist: visible, default=true; data: visible, default=true; chats: visible, default=false
     - fireproof: visible; history link: hidden
     - title: "Delete all history?"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visitsCountSource: 12
     User input:
     - scope: All (Unsupported); tabs: true; hist: true; data: true; selectedDomains: nil (all)
     Expectation:
     - burnAll
     */
    func testHistoryAll_AllData_WithTabsAndHistoryAndChats_CallsBurnAll() async throws {
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.all)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: true)
        let response = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.all)), in: window)
        if case .burn(let opts?) = response { XCTAssertTrue(opts.includeTabsAndWindows) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        let call = try XCTUnwrap(fire.burnAllCalls.onlyValue)
        XCTAssertEqual(call.isBurnOnExit, false)
    }

    /**
     Provider config:
     - domains: [a.com, b.com]
     - visits: today[a×2, b×1], yesterday[a×1], 2024-05-15[b×1]
     Entry: History (All)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=true; hist: visible, default=true; data: visible, default=true; chats: visible, default=false
     - fireproof: visible; history link: hidden
     - title: "Delete all history?"
     - selectedDomains: [a.com, b.com]
     User input:
     - scope: All (Unsupported); tabs: false; hist: false; data: false; selectedDomains: [a.com, b.com]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[a.com,b.com], close=false), includingHistory=false
     */
    func testHistoryAll_AllData_CookiesOff_NoHistory() async throws {
        // Test specifically for no history scenario - configure empty state
        mockHistoryProvider.configure(visits: [], cookieDomains: [])

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.all)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: nil,
            expectedFireproofed: [],
            expectedSelected: nil
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: false,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: false,
                                       includeChatHistory: false,
                                       isToday: false)

        let response = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.all)), in: window)
        if case .burn(let opts?) = response { XCTAssertFalse(opts.includeHistory); XCTAssertFalse(opts.includeTabsAndWindows) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, customURLToOpen, close) = call.entity {
            XCTAssertEqual(selectedDomains, [])
            XCTAssertNil(customURLToOpen)
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows") }
        XCTAssertFalse(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, x.com, example.com, test.com, date.com, close.me, c.com, z.com]
     - visits: today[a.com×2, b.com×1, cook.ie×1, x.com×2, close.me×1, z.com×1], yesterday[a.com×1, figma.com×2, x.com×1], twoDaysAgo[example.com×1, c.com×2], specificDate[date.com×2, b.com×1, test.com×1]
     Entry: History (All)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=true; hist: visible, default=true; data: visible, default=true; chats: visible, default=false
     - fireproof: visible; history link: hidden
     - title: "Delete all history?"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, x.com, example.com, test.com, date.com, close.me, c.com, z.com]
     User input:
     - scope: All (Unsupported); tabs: false; hist: true; data: true; selectedDomains: [example.com, test.com]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[example.com, test.com], close=false), includingHistory=true
     */
    func testHistoryAll_AllData_NoTabs_PassesDomainsToBurnEntity() async throws {
        // Uses default test data with multiple domains
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.all)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)
        let response = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.all)), in: window)
        if case .burn(let opts?) = response { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, customURLToOpen, close) = call.entity {
            XCTAssertEqual(selectedDomains, Set(allCookieDomains(except: fireproofDomains)))
            XCTAssertNil(customURLToOpen)
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertTrue(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (All)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=true
     - hist: visible, default=true
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: Window
     - tabs: true
     - hist: true
     - data: false
     - selectedDomains: nil (all)
     Expectation:
     - burnEntity(window, close=true), includingHistory=true
     */
    func testHistoryAll_CurrentWindow_CloseWindowsTrue() async throws {
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        // Window 1 has only a.com and b.com tabs (per comment lines 232-233)
        let window1Domains: Set = ["a.com", "b.com"]

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.all)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .currentWindow,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: false,
                                       includeChatHistory: false,
                                       selectedCookieDomains: window1Domains,  // Only domains from Window 1
                                       selectedVisits: nil,
                                       isToday: false)
        let responseCloseTrue = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.all)), in: window)
        if case .burn(let opts?) = responseCloseTrue { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: responseCloseTrue))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .window(windowController, selectedDomains, close) = call.entity {
            XCTAssertNotNil(windowController)
            XCTAssertEqual(selectedDomains, Set(window1Domains), "Should only burn domains from current window (Window 1), not all domains")
            XCTAssertTrue(close)
        } else { XCTFail("Expected window, got \(call.entity)") }
        XCTAssertEqual(call.includingHistory, true)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (All)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=true
     - hist: visible, default=true
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: Window
     - tabs: false
     - hist: true
     - data: false
     - selectedDomains: nil (all)
     Expectation:
     - burnEntity(window, close=false), includingHistory=true
     */
    func testHistoryAll_CurrentWindow_CloseWindowsFalse_HistoryCleared() async throws {
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        // Window 1 has only a.com and b.com tabs (per comment lines 298-299)
        let window1Domains: Set = ["a.com", "b.com"]

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.all)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .currentWindow,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: false,
                                       includeChatHistory: false,
                                       selectedCookieDomains: window1Domains,  // Only domains from Window 1
                                       selectedVisits: nil,
                                       isToday: false)
        let responseCloseFalse = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.all)), in: window)
        if case .burn(let opts?) = responseCloseFalse { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: responseCloseFalse))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .window(windowController, selectedDomains, close) = call.entity {
            XCTAssertNotNil(windowController)
            XCTAssertEqual(selectedDomains, Set(window1Domains), "Should only burn domains from current window (Window 1), not all domains")
            XCTAssertFalse(close)
        } else { XCTFail("Expected window, got \(call.entity)") }
        XCTAssertEqual(call.includingHistory, true)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (All)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=true; hist: visible, default=true; data: visible, default=true; chats: not visible, default=false
     - fireproof: visible; history link: hidden
     - title: "Delete all history?"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     User input:
     - scope: All (Unsupported)
     - tabs: false; hist: true; data: true
     - selectedVisits: [cook.ie on today] but isToday=false (simulating non-today burnVisits path)
     Expectation:
     - burnVisits(visits=[cook.ie], clearSiteData=true, closeWindows=false)
     */
    func testHistoryAll_SelectedVisits_WithCookiesClearsSiteData() async throws {
        let cookieVisits = await mockHistoryProvider.visits(matching: .domainFilter(["cook.ie"]))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .domainFilter(["cook.ie"])),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: false,
            customTitle: "Delete all history from\ncook.ie?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: ["cook.ie"],
            expectedFireproofed: [],  // Section hidden for domain filter
            expectedSelected: Set([0]),
            expectedHistoryVisits: cookieVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: cookieVisits,
                                       isToday: false)
        let responseVisitsCookies = await coordinator.presentFireDialog(mode: .historyView(query: .domainFilter(["cook.ie"])), in: window, scopeVisits: cookieVisits)
        if case .burn(let opts?) = responseVisitsCookies { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: responseVisitsCookies))") }
        let call = try XCTUnwrap(fire.burnVisitsCalls.onlyValue)
        let visitOnly = try XCTUnwrap(call.visits.onlyValue)
        XCTAssertEqual(visitOnly.historyEntry?.url.host, "cook.ie")
        XCTAssertEqual(call.clearSiteData, true)
    }

    /**
     Provider config:
     - domains: [onlyhistory.com]
     - visits: 2024-05-15[onlyhistory.com×1]
     Entry: History (All)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=false; hist: visible, default=true; data: visible, default=false; chats: not visible, default=false
     - fireproof: visible; history link: hidden
     - title: "Delete all history?"
     - selectedDomains: [onlyhistory.com]
     User input:
     - scope: All (Unsupported)
     - tabs: false; hist: true; data: false
     - selectedVisits: [onlyhistory.com on D]
     Expectation:
     - burnVisits(visits=[onlyhistory.com], isToday=false, clearSiteData=false, closeWindows=false)
     */
    func testHistoryAll_SelectedVisits_NoTabs_NoCookies_ParametersPassed() async throws {
        let testVisits = await mockHistoryProvider.visits(matching: .domainFilter(["test.com"]))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .domainFilter(["test.com"])),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: false,
            customTitle: "Delete all history from\ntest.com?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: ["test.com"],
            expectedFireproofed: [],
            expectedSelected: Set([0]),
            expectedHistoryVisits: testVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: false,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: testVisits,
                                       isToday: false)

        _ = await coordinator.presentFireDialog(mode: .historyView(query: .domainFilter(["test.com"])), in: window, scopeVisits: testVisits)

        let call = try XCTUnwrap(fire.burnVisitsCalls.onlyValue)
        let visitOnly = try XCTUnwrap(call.visits.onlyValue)
        XCTAssertEqual(visitOnly.historyEntry?.url.host, "test.com")
        XCTAssertEqual(call.isToday, false)
        XCTAssertEqual(call.closeWindows, false)
        XCTAssertEqual(call.clearSiteData, false)
    }

    // MARK: - History (Today)

    /**
     Provider config:
     - domains: [x.com]
     - visits: today[x.com×1]
     - Window/Tab State:
     - Window 1: Tab x.com (active) history: today[x.com×1]
     Entry: History (Today)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=true
     - hist: visible, default=true
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History From Today"
     - selectedDomains: [x.com]
     - visitsCountSource: 1 (x.com×1)
     User input:
     - scope: All (Unsupported)
     - tabs: true
     - hist: true
     - data: false
     - selectedVisits: [x.com on today]
     Expectation:
     - burnVisits(visits=[x.com], isToday=true, closeWindows=true, clearSiteData=false)
     */
    func testHistoryToday_SelectedVisitsPath_BurnVisitsRespectingFlags() async throws {
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.today))
        let visitedDomains = await mockHistoryProvider.cookieDomains(matching: .rangeFilter(.today))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.today)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history from today?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: visitedDomains.subtracting(fireproofDomains).sorted(),
            expectedFireproofed: ["duckduckgo.com"],  // Only duckduckgo.com visited today
            expectedSelected: Set(visitedDomains.subtracting(fireproofDomains).sorted().indices),
            expectedHistoryVisits: expectedVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: false,
                                       includeChatHistory: false,
                                       selectedCookieDomains: ["x.com"],
                                       selectedVisits: [],  // Empty to force burnEntity path
                                       isToday: true)
        let responseToday = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.today)), in: window)
        if case .burn(let opts?) = responseToday { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: responseToday))") }

        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        switch call.entity {
        case .allWindows(_, let selectedDomains, _, _):
            XCTAssertEqual(selectedDomains, Set(["x.com"]))
        default:
            XCTFail("Expected allWindows entity, got \(call.entity)")
        }
        XCTAssertEqual(call.includingHistory, true)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie]
     - visits: today[a×2, b×1, cook.ie×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (Today)
     Dialog config: scopeSelector hidden (All), tabs visible default=true, hist visible default=true, data visible default=true; chats: not visible, default=false
     User input: all selected, tabs=true, hist=false, data=true
     Expectation: burnEntity(allWindows, selectedDomains=all, close=true), includingHistory=false
     */
    func testHistoryToday_AllData_AllSelected_WithTabs_NoHistory() async throws {
        // Test specifically for no history scenario - configure empty state
        mockHistoryProvider.configure(visits: [], cookieDomains: [])

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.today)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: HistoryViewDeleteDialogModel.DeleteMode.today.title,
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: [],  // No history configured
            expectedFireproofed: [],  // No history configured
            expectedSelected: Set(),
            expectedHistoryVisits: []
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: false,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: true)

        let response = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.today)), in: window)
        if case .burn(let opts?) = response { XCTAssertTrue(opts.includeTabsAndWindows); XCTAssertFalse(opts.includeHistory) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, _, close) = call.entity {
            XCTAssertTrue(close)
            XCTAssertEqual(selectedDomains, lastDialogScopeDomains)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertFalse(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [a.com, b.com]
     - visits: today[a×2, b×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (Today)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: visible, default=true
     - hist: visible, default=true
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History From Today"
     - selectedDomains: [a.com, b.com]
     - visitsCountSource: 4 (a×2, b×1, cook.ie×1)
     User input:
     - scope: All (Unsupported)
     - tabs: false
     - hist: true
     - data: true
     - selectedDomains: [a.com, b.com]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[a.com,b.com], close=false), includingHistory=true
     */
    func testHistoryToday_Selected_MultiDomain_CookiesOn() async throws {
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.today))
        let visitedDomains = await mockHistoryProvider.cookieDomains(matching: .rangeFilter(.today))
        let selectableDomains = visitedDomains.subtracting(fireproofDomains).sorted()

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.today)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: HistoryViewDeleteDialogModel.DeleteMode.today.title,
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: visitedDomains.subtracting(fireproofDomains).sorted(),
            expectedFireproofed: visitedDomains.intersection(fireproofDomains).sorted(),
            expectedSelected: selectableDomains.indices,
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: [],  // Empty to force burnEntity path
                                       isToday: true)

        let response = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.today)), in: window)
        if case .burn(let opts?) = response { XCTAssertFalse(opts.includeTabsAndWindows); XCTAssertTrue(opts.includeHistory) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, _, close) = call.entity {
            XCTAssertEqual(selectedDomains, Set(selectableDomains))
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertTrue(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [close.me]
     - visits: today[close.me×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (Today)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History From Today"
     - selectedDomains: [close.me]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: true
     - data: false
     - selectedDomains: nil (all)
     Expectation:
     - burnVisits(visits=[close.me], isToday=true, closeWindows=true, clearSiteData=true)
     */
    func testHistoryToday_SelectedVisits_CloseWindowsTrue_Respected() async throws {
        // Test expects to delete only close.me visits from today
        let todayVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.today))
        let closeVisits = todayVisits.filter { $0.historyEntry?.url.host == "close.me" }
        let todayDomains = await mockHistoryProvider.cookieDomains(matching: .rangeFilter(.today))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.today)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history from today?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: todayDomains.subtracting(fireproofDomains).sorted(),
            expectedFireproofed: ["duckduckgo.com"],
            expectedSelected: Set(todayDomains.subtracting(fireproofDomains).sorted().indices),
            expectedHistoryVisits: todayVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: closeVisits,
                                       isToday: true)

        let responseMenuToday = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.today)), in: window)
        if case .burn(let opts?) = responseMenuToday { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: responseMenuToday))") }

        let call = try XCTUnwrap(fire.burnVisitsCalls.onlyValue)
        XCTAssertEqual(call.isToday, true)
        XCTAssertEqual(call.closeWindows, true)
        XCTAssertEqual(call.clearSiteData, true)
    }

    // MARK: - History (Yesterday)

    /**
     Provider config:
     - domains: [x.com, figma.com, example.com, test.com]
     - visits: today[x.com×2], yesterday[figma.com×1, x.com×1], twoDaysAgo[example.com×1], specificDate[test.com×1]
     Entry: History (Yesterday)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=false
     - chats: not visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History From Yesterday"
     - selectedDomains: [figma.com, x.com]
     - visitsCountSource: 2 (figma.com×1, x.com×1)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: true
     - data: false
     - selectedDomains: nil
     Expectation:
     - burnVisits(visits=[yesterday: figma.com×1, x.com×1], isToday=false, closeWindows=false, clearSiteData=false)
     - CRITICAL: No today or other date visits are burned
     */
    func testHistoryYesterday_Selected_NoTabs_CookiesOff() async throws {

        // Use default test data - yesterday has figma.com×1, x.com×1 visits
        // Find yesterday visits by checking which visits are from yesterday (not today, not older)
        let today = Date()
        let calendar = Calendar.current
        let expectedYesterdayVisits = mockHistoryProvider.allVisits.filter { visit in
            let isYesterday = calendar.isDate(visit.date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!)
            return isYesterday
        }

        // Debug: Ensure we have yesterday visits
        XCTAssertFalse(expectedYesterdayVisits.isEmpty, "Expected to find yesterday visits in test data")

        // Validate initial dialog configuration against MD
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.yesterday))
        let visitedDomains = await mockHistoryProvider.cookieDomains(matching: .rangeFilter(.yesterday))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .rangeFilter(.yesterday)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: true,
            customTitle: HistoryViewDeleteDialogModel.DeleteMode.yesterday.title,
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: visitedDomains.subtracting(fireproofDomains).sorted(),
            expectedFireproofed: ["github.com"],  // Only github.com visited yesterday
            expectedSelected: Set(visitedDomains.subtracting(fireproofDomains).sorted().indices),
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: false,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)

        let response = await coordinator.presentFireDialog(mode: .historyView(query: .rangeFilter(.yesterday)), in: window)
        if case .burn(let opts?) = response { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: response))") }

        // Validate visits burning for yesterday scope - should only burn yesterday visits
        let call = try XCTUnwrap(fire.burnVisitsCalls.onlyValue)
        XCTAssertEqual(call.isToday, false)
        XCTAssertEqual(call.closeWindows, false)
        XCTAssertEqual(call.clearSiteData, false)

        // Validate that only yesterday visits are burned (figma.com×1, x.com×1)
        XCTAssertEqual(Set(call.visits), Set(expectedYesterdayVisits), "Should only burn yesterday visits")

        // Ensure no today or other date visits are in the burned set (cross-date contamination check)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        XCTAssertTrue(call.visits.allSatisfy { visit in
            calendar.isDate(visit.date, inSameDayAs: yesterday)
        }, "Only yesterday visits should be burned")
    }

    // MARK: - History (Date)

    /**
     Provider config:
     - domains: [date.com, b.com]
     - visits: 2024-05-15[date×2, b×1]
     Entry: History (Date)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete History for 2024-05-15"
     - selectedDomains: [date.com, b.com]
     - visitsCountSource: 3 (date×2, b×1)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: true
     - data: true
     - selectedDomains: nil (all)
     Expectation:
     - burnEntity(allWindows, selectedDomains=all, close=false), includingHistory=true
     */
    func testHistoryDate_AllData_AllSelected() async throws {
        let date = ISO8601DateFormatter().date(from: "2024-05-15T12:00:00Z") ?? Date(timeIntervalSince1970: 1715774400)
        let expectedVisits = await mockHistoryProvider.visits(matching: .dateFilter(date))
        let expectedDomains = await mockHistoryProvider.cookieDomains(matching: .dateFilter(date))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .dateFilter(date)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: true,
            customTitle: HistoryViewDeleteDialogModel.DeleteMode.date(date).title,
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: expectedDomains.sorted(),
            expectedFireproofed: [],  // No fireproofed domains on this specific date
            expectedSelected: Set(expectedDomains.sorted().indices),
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: [],  // Empty to force burnEntity path, not burnVisits
                                       isToday: false)

        let response = await coordinator.presentFireDialog(mode: .historyView(query: .dateFilter(date)), in: window)
        if case .burn(let opts?) = response { XCTAssertTrue(opts.includeHistory); XCTAssertFalse(opts.includeTabsAndWindows) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, _, _, close) = call.entity {
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertTrue(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [date.com, b.com]
     - visits: 2024-05-15[date×2, b×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (Date)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete History for 2024-05-15"
     - selectedDomains: [date.com, b.com]
     - visitsCountSource: 3 (date×2, b×1)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: true
     - data: true
     - selectedDomains: [date.com, b.com]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[date.com,b.com], close=false), includingHistory=true
     */
    func testHistoryDate_Selected_MultiDomain() async throws {
        let date = ISO8601DateFormatter().date(from: "2024-05-15T12:00:00Z") ?? Date(timeIntervalSince1970: 1715774400)
        let expectedVisits = await mockHistoryProvider.visits(matching: .dateFilter(date))
        let expectedDomains = await mockHistoryProvider.cookieDomains(matching: .dateFilter(date))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .dateFilter(date)),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: true,
            customTitle: HistoryViewDeleteDialogModel.DeleteMode.date(date).title,
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: expectedDomains.sorted(),
            expectedFireproofed: [],  // No fireproofed domains on this specific date
            expectedSelected: Set(expectedDomains.sorted().indices),
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: [],  // Empty to force burnEntity path
                                       isToday: false)

        _ = await coordinator.presentFireDialog(mode: .historyView(query: .dateFilter(date)), in: window)
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, _, close) = call.entity {
            XCTAssertEqual(selectedDomains, Set(expectedDomains))
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertTrue(call.includingHistory)
    }

    // MARK: - History (Sites)

    /**
     Provider config:
     - domains: [figma.com]
     - visits: yesterday[figma×2]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (Sites → single site)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: hidden
     - history link: hidden
     - title: "Delete History for figma.com"
     - selectedDomains: [figma.com]
     - visitsCountSource: 2 (figma×2)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: false
     - data: true
     - selectedDomains: [figma.com]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[figma.com], close=false), includingHistory=false
     */
    func testHistorySite_SingleSite_VariantA() async throws {

        let figmaVisits = await mockHistoryProvider.visits(matching: .domainFilter(["figma.com"]))
        let figmaDomains = await mockHistoryProvider.cookieDomains(matching: .domainFilter(["figma.com"]))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .domainFilter(["figma.com"])),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: false,
            customTitle: "Delete all history from\nfigma.com?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: figmaDomains.sorted(),
            expectedFireproofed: [],  // Section hidden for domain filter
            expectedSelected: Set(figmaDomains.sorted().indices),
            expectedHistoryVisits: figmaVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: false,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)
        _ = await coordinator.presentFireDialog(mode: .historyView(query: .domainFilter(["figma.com"])), in: window, scopeVisits: figmaVisits)
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, _, close) = call.entity {
            XCTAssertEqual(selectedDomains, ["figma.com"])
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertFalse(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [example.com]
     - visits: today[example.com×2]
     - Window/Tab State:
     - Window 1: Tab example.com (active) history: today[example.com×2]
     Entry: History (Sites → single site)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: hidden
     - history link: hidden
     - title: "Delete History for example.com"
     - selectedDomains: [example.com]
     - visitsCountSource: 2 (example.com×2)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: true
     - data: false
     - selectedDomains: [example.com]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[example.com], close=false), includingHistory=true
     */
    func testHistorySite_SingleSite_VariantB() async throws {

        let exampleVisits = await mockHistoryProvider.visits(matching: .domainFilter(["example.com"]))
        let exampleDomains = await mockHistoryProvider.cookieDomains(matching: .domainFilter(["example.com"]))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .domainFilter(["example.com"])),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: false,
            customTitle: "Delete all history from\nexample.com?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: exampleDomains.sorted(),
            expectedFireproofed: [],  // Section hidden for domain filter
            expectedSelected: Set(exampleDomains.sorted().indices),
            expectedHistoryVisits: exampleVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: false,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: [],  // Empty to force burnEntity path
                                       isToday: false)

        _ = await coordinator.presentFireDialog(mode: .historyView(query: .domainFilter(["example.com"])), in: window)
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, _, close) = call.entity {
            XCTAssertEqual(selectedDomains, Set(exampleDomains))
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertTrue(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [a.com]
     - visits: today[a.com×2]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]
     Entry: History (Sites → single site)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: hidden
     - history link: hidden
     - title: "Delete History for a.com"
     - selectedDomains: [a.com]
     - visitsCountSource: 2 (a×2)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: true
     - data: true
     - selectedDomains: [a.com]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[a.com], close=false), includingHistory=true
     */
    func testHistorySite_SingleSite_VariantC() async throws {

        let aVisits = await mockHistoryProvider.visits(matching: .domainFilter(["a.com"]))
        let aDomains = await mockHistoryProvider.cookieDomains(matching: .domainFilter(["a.com"]))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .domainFilter(["a.com"])),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: false,
            customTitle: "Delete all history from\na.com?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: aDomains.sorted(),
            expectedFireproofed: [],  // Section hidden for domain filter
            expectedSelected: Set(aDomains.sorted().indices),
            expectedHistoryVisits: aVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: [],  // Empty to force burnEntity path
                                       isToday: false)
        _ = await coordinator.presentFireDialog(mode: .historyView(query: .domainFilter(["a.com"])), in: window, scopeVisits: aVisits)
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, _, close) = call.entity {
            XCTAssertEqual(selectedDomains, Set(aDomains))
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertTrue(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [a.com, b.com]
     - visits: today[a×2, b×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (Sites → multi site)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: hidden, default=nil
     - hist: visible, default=false
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: hidden
     - history link: hidden
     - title: "Delete History"
     - selectedDomains: [a.com, b.com]
     - visitsCountSource: 5 (a×2, b×1, c×2)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: true
     - data: false
     - selectedDomains: [a.com, b.com]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[a.com,b.com], close=false), includingHistory=true
     */
    func testHistorySites_MultiSite_VariantA() async throws {
        let abVisits = await mockHistoryProvider.visits(matching: .domainFilter(["a.com", "b.com"]))
        let abDomains = Set(abVisits.compactMap { $0.historyEntry?.url.host })

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .domainFilter(["a.com", "b.com"])),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: false,
            customTitle: "Delete history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: abDomains.sorted(),
            expectedFireproofed: [],  // Section hidden for domain filter
            expectedSelected: Set(abDomains.sorted().indices),
            expectedHistoryVisits: abVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: false,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: [],  // Empty to force burnEntity path
                                       isToday: false)

        _ = await coordinator.presentFireDialog(mode: .historyView(query: .domainFilter(["a.com", "b.com"])), in: window, scopeVisits: abVisits)
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, _, close) = call.entity {
            XCTAssertEqual(selectedDomains, Set(["a.com", "b.com"]))
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertTrue(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [a.com, b.com]
     - visits: today[a×2, b×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: History (Sites → multi site)
     Dialog config:
     - scopeSelector: hidden, selected: All
     - tabs: hidden, default=nil
     - hist: visible, default=false
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: hidden
     - history link: hidden
     - title: "Delete History"
     - selectedDomains: [a.com, b.com]
     - visitsCountSource: 3 (a×2, b×1)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: false
     - data: true
     - selectedDomains: [a.com, b.com]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[a.com,b.com], close=false), includingHistory=false
     */
    func testHistorySites_MultiSite_VariantB() async throws {

        // Test for multi-site domain filter
        let expectedVisits = await mockHistoryProvider.visits(matching: .domainFilter(["a.com", "b.com"]))
        let visitedDomains = await mockHistoryProvider.cookieDomains(matching: .domainFilter(["a.com", "b.com"]))

        dialogExpectedInput = DialogExpectedInput(
            mode: .historyView(query: .domainFilter(["a.com", "b.com"])),
            showSegmentedControl: false,
            showCloseWindowsAndTabsToggle: false,
            showFireproofSection: false,
            customTitle: "Delete history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: false,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: visitedDomains.sorted(),
            expectedFireproofed: [],  // Section hidden for domain filter
            expectedSelected: Set(visitedDomains.sorted().indices),
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: false,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: ["a.com", "b.com"],
                                       selectedVisits: nil,
                                       isToday: false)

        _ = await coordinator.presentFireDialog(mode: .historyView(query: .domainFilter(["a.com", "b.com"])), in: window)
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, _, close) = call.entity {
            XCTAssertEqual(selectedDomains, Set(["a.com", "b.com"]))
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows") }
        XCTAssertFalse(call.includingHistory)
    }

    // MARK: - Fire Button

    /**
     Provider config:
     - domains: [a.com]
     - visits: today[a×2]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]
     Entry: Fire Button
     Dialog config:
     - scopeSelector: visible, selected=Tab
     - tabs: hidden, default=nil
     - hist: visible, default=false
     - data: visible, default=true
     - chats: not visible, default=false
     - fireproof: visible
     - history link: visible
     - title: nil
     - selectedDomains: [a.com]
     - visitsCountSource: 2 (a×2)
     User input:
     - scope: Tab
     - tabs: false (Unsupported)
     - hist: false
     - data: true
     - selectedDomains: [a.com]
     Expectation:
     - burnEntity(tab, selectedDomains=[a.com], close=false), includingHistory=false
     */
    func testFireButton_CurrentTabScope_PassesWindowAndHistoryFlags() async throws {
        // Current tab (a.com) should only clear a.com domain (per comment lines 1288, 1295)
        let currentTabDomains: Set = ["a.com"]

        dialogExpectedInput = DialogExpectedInput(
            mode: .fireButton,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete Browsing Data",
            showIndividualSitesLink: false,
            expectedClearingOption: .currentTab,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: [],  // MockWindow has no tabs configured
            expectedFireproofed: [],
            expectedSelected: Set()
        )
        dialogConfirmedOptions = .init(clearingOption: .currentTab,
                                       includeHistory: false,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: currentTabDomains,  // Only domain from current tab
                                       selectedVisits: nil,
                                       isToday: false)
        let response = await coordinator.presentFireDialog(mode: .fireButton, in: window)
        if case .burn(let opts?) = response { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .tab(tabViewModel, selectedDomains, parent, close) = call.entity {
            XCTAssertNotNil(tabViewModel)
            XCTAssertEqual(selectedDomains, Set(currentTabDomains), "Should only burn domain from current tab (a.com), not all or empty")
            XCTAssertNotNil(parent)
            XCTAssertFalse(close)
        } else { XCTFail("Expected tab entity, got \(call.entity)") }
        XCTAssertFalse(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [a.com, b.com]
     - visits: today[a×2, b×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]
     Entry: Fire Button
     Dialog config:
     - scopeSelector: visible, selected=Tab
     - tabs: hidden, default=true
     - hist: visible, default=true
     - data: visible, default=true
     - chats: visible, default=false
     - fireproof: visible
     - history link: visible
     - title: nil
     - selectedDomains: [a.com, b.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All
     - tabs: false (Unsupported)
     - hist: true
     - data: true
     - selectedDomains: nil (all)
     Expectation:
     - burnAll
     */
    func testFireButton_AllData_TabsAndHistory() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .fireButton,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete Browsing Data",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)

        let response = await coordinator.presentFireDialog(mode: .fireButton, in: window)
        if case .burn(let opts?) = response { XCTAssertTrue(opts.includeHistory); XCTAssertTrue(opts.includeTabsAndWindows) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        _ = try XCTUnwrap(fire.burnAllCalls.onlyValue)
    }

    /**
     Provider config:
     - domains: [a.com, b.com]
     - visits: today[a×2, b×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]
     Entry: Fire Button
     Dialog config:
     - scopeSelector: visible, selected=Tab
     - tabs: hidden, default=true
     - hist: visible, default=true
     - data: visible, default=true
     - chats: visible, default=false
     - fireproof: visible
     - history link: visible
     - title: nil
     - selectedDomains: [a.com, b.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All
     - tabs: false (Unsupported)
     - hist: true
     - data: true
     - chats: true
     - selectedDomains: nil (all)
     Expectation:
     - burnAll
     */
    func testFireButton_AllData_TabsAndHistoryAndChats() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .fireButton,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete Browsing Data",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: true,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)

        let response = await coordinator.presentFireDialog(mode: .fireButton, in: window)
        if case .burn(let opts?) = response { XCTAssertTrue(opts.includeHistory); XCTAssertTrue(opts.includeTabsAndWindows) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        _ = try XCTUnwrap(fire.burnAllCalls.onlyValue)
    }

    /**
     Provider config:
     - domains: [cook.ie]
     - visits: today[cook.ie×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]
     Entry: Fire Button
     Dialog config:
     - scopeSelector: visible, selected=All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=true
     - chats: visible, default=false
     - fireproof: visible
     - history link: visible
     - title: nil
     - selectedDomains: [cook.ie]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All
     - tabs: false (Unsupported)
     - hist: false
     - data: true
     - selectedDomains: [cook.ie]
     Expectation:
     - burnEntity(allWindows, selectedDomains=[cook.ie], close=false), includingHistory=false
     */
    func testFireButton_AllData_NoTabs_NoHistory_CookieOnly() async throws {
        // Test specifically for no history scenario - configure empty state
        FireDialogViewModel.lastSelectedClearingOption = .allData
        mockHistoryProvider.configure(visits: [], cookieDomains: [])

        dialogExpectedInput = DialogExpectedInput(
            mode: .fireButton,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete Browsing Data",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: [],
            expectedFireproofed: [],  // No history configured
            expectedSelected: Set()
        )
        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: false,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: ["cook.ie"],
                                       selectedVisits: nil,
                                       isToday: false)
        let responseCookieOnly = await coordinator.presentFireDialog(mode: .fireButton, in: window)
        if case .burn(let opts?) = responseCookieOnly { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: responseCookieOnly))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, customURLToOpen, close) = call.entity {
            XCTAssertEqual(selectedDomains, ["cook.ie"])
            XCTAssertNil(customURLToOpen)
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertFalse(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [cook.ie]
     - visits: today[cook.ie×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]
     Entry: Fire Button
     Dialog config:
     - scopeSelector: visible, selected=All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=true
     - chats: visible, default=false
     - fireproof: visible
     - history link: visible
     - title: nil
     - selectedDomains: [cook.ie]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All
     - tabs: false (Unsupported)
     - hist: false
     - data: true
     - selectedDomains: []
     Expectation:
     - burnEntity(allWindows, selectedDomains=[cook.ie], close=false), includingHistory=false
     */
    func testFireButton_AllData_NoTabs_NoHistory_NoCookies_ChatsOnly() async throws {
        // Test specifically for no history scenario - configure empty state
        FireDialogViewModel.lastSelectedClearingOption = .allData
        mockHistoryProvider.configure(visits: [], cookieDomains: [])

        dialogExpectedInput = DialogExpectedInput(
            mode: .fireButton,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete Browsing Data",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: [],
            expectedFireproofed: [],  // No history configured
            expectedSelected: Set()
        )
        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: false,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: false,
                                       includeChatHistory: true,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)
        let responseChatsOnly = await coordinator.presentFireDialog(mode: .fireButton, in: window)
        if case .burn(let opts?) = responseChatsOnly { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: responseChatsOnly))") }
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, customURLToOpen, close) = call.entity {
            XCTAssertEqual(selectedDomains, [])
            XCTAssertNil(customURLToOpen)
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertFalse(call.includingHistory)
    }

    /**
     Provider config:
     - domains: [z.com]
     - visits: today[z×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]
     Entry: Fire Button
     Dialog config:
     - scopeSelector: visible, selected=All
     - tabs: hidden, default=nil
     - hist: visible, default=true
     - data: visible, default=true
     - chats: visible, default=false
     - fireproof: visible
     - history link: visible
     - title: nil
     - selectedDomains: [z.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All
     - tabs: false (Unsupported)
     - hist: true
     - data: true
     - selectedDomains: [z.com] (via onConfirm)
     Expectation:
     - presenter receives window; coordinator propagates to burn path
     */
    func testFireButton_PresenterReceivesWindowAndOnConfirmPropagatesResult() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        var capturedWindow: NSWindow?
        let fire = FireMock()
        let coordinator = makeCoordinator(with: fire) { window, completion in
            capturedWindow = window
        }

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)

        let window = MockWindow()
        let response = await coordinator.presentFireDialog(mode: .fireButton, in: window)
        if case .burn(let opts?) = response { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: response))") }
        XCTAssertNotNil(capturedWindow)
        _ = try XCTUnwrap(fire.burnAllCalls.onlyValue)
    }

    /**
     Provider config:
     - domains: [a.com, b.com]
     - visits: today[a×2, b×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]
     Entry: Fire Button
     Dialog config:
     - scopeSelector: visible, selected=All
     - tabs: hidden, default=nil
     - hist: visible, default=false
     - data: visible, default=true
     - chats: visible, default=false
     - fireproof: visible
     - history link: visible
     - title: nil
     - selectedDomains: [a.com, b.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All
     - tabs: false (Unsupported)
     - hist: false
     - data: true
     - selectedDomains: nil (all)
     Expectation:
     - coordinator merges VM selection domains into burnEntity(allWindows)
     */
    func testFireButton_AllData_NoDomainsProvided_MergesFromViewModelSelection() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .fireButton,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete Browsing Data",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: false,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)

        // Don't pass scopeVisits - let coordinator fetch all visits automatically for fireButton mode
        let responseVMSelect = await coordinator.presentFireDialog(mode: .fireButton, in: window)
        if case .burn(let opts?) = responseVMSelect { XCTAssertNotNil(opts) } else { XCTFail("Expected burn response, got \(String(describing: responseVMSelect))") }

        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(mainWindowControllers, selectedDomains, customURLToOpen, close) = call.entity {
            XCTAssertEqual(mainWindowControllers.count, 0)  // MockWindow has no windows
            XCTAssertEqual(selectedDomains, Set(allCookieDomains(except: fireproofDomains)))
            XCTAssertNil(customURLToOpen)
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows, got \(call.entity)") }
        XCTAssertFalse(call.includingHistory, "History should NOT be cleared when includeHistory is false")
    }

    // MARK: - Main Menu

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: Main Menu (All)
     Dialog config:
     - scopeSelector: visible, selected: All
     - tabs: visible, default=true
     - hist: visible, default=true
     - data: visible, default=false
     - chats: visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All (Unsupported)
     - tabs: true
     - hist: true
     - data: false
     - selectedDomains: nil (all)
     Expectation:
     - burnAll
     */
    func testMainMenuAll_AllData_WithTabsAndHistory() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .mainMenuAll,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)

        _ = await coordinator.presentFireDialog(mode: .mainMenuAll, in: window)
        _ = try XCTUnwrap(fire.burnAllCalls.onlyValue)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: Main Menu (All)
     Dialog config:
     - scopeSelector: visible, selected: All
     - tabs: visible, default=true
     - hist: visible, default=true
     - data: visible, default=false
     - chats: visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All (Unsupported)
     - tabs: true
     - hist: true
     - data: false
     - chats: true
     - selectedDomains: nil (all)
     Expectation:
     - burnAll
     */
    func testMainMenuAll_AllData_WithTabsAndHistoryAndChats() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .mainMenuAll,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: true,
                                       includeTabsAndWindows: true,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: true,
                                       selectedCookieDomains: nil,
                                       selectedVisits: nil,
                                       isToday: false)

        _ = await coordinator.presentFireDialog(mode: .mainMenuAll, in: window)
        _ = try XCTUnwrap(fire.burnAllCalls.onlyValue)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     - Window/Tab State:
     - Window 1 only: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     Entry: Main Menu (All)
     Dialog config:
     - scopeSelector: visible, selected: All
     - tabs: visible, default=true
     - hist: visible, default=true
     - data: visible, default=false
     - chats: visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All (Unsupported)
     - tabs: true
     - hist: true
     - data: false
     - selectedDomains: nil (all)
     Expectation:
     - burnAll
     */
    func testMainMenuAll_AllData_WithTabsAndHistory_SingleWindow() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .mainMenuAll,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData, includeHistory: true, includeTabsAndWindows: true, includeCookiesAndSiteData: true, includeChatHistory: false, selectedCookieDomains: nil, selectedVisits: nil, isToday: false)
        _ = await coordinator.presentFireDialog(mode: .mainMenuAll, in: window)
        _ = try XCTUnwrap(fire.burnAllCalls.onlyValue)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: Main Menu (All)
     Dialog config:
     - scopeSelector: visible, selected: All
     - tabs: visible, default=true
     - hist: visible, default=true
     - data: visible, default=false
     - chats: visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All (Unsupported)
     - tabs: true
     - hist: true
     - data: false
     - selectedDomains: nil (all)
     Expectation:
     - burnAll
     */
    func testMainMenuAll_AllData_WithTabsAndHistory_MultipleWindows() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .mainMenuAll,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData, includeHistory: true, includeTabsAndWindows: true, includeCookiesAndSiteData: true, includeChatHistory: false, selectedCookieDomains: nil, selectedVisits: nil, isToday: false)
        _ = await coordinator.presentFireDialog(mode: .mainMenuAll, in: window)
        _ = try XCTUnwrap(fire.burnAllCalls.onlyValue)
    }

    /**
     Provider config:
     - domains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visits: today[a×2, b×1, cook.ie×1], yesterday[a×1, figma×2], 2024-05-15[date×2, b×1], today-2[c×2]
     - Window/Tab State: none (0 windows)
     Entry: Main Menu (All)
     Dialog config:
     - scopeSelector: visible, selected: All
     - tabs: visible, default=true
     - hist: visible, default=true
     - data: visible, default=false
     - chats: visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History"
     - selectedDomains: [a.com, b.com, cook.ie, figma.com, date.com, c.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All (Unsupported)
     - tabs: true
     - hist: true
     - data: false
     - selectedDomains: nil (all)
     Expectation:
     - burnAll
     */
    func testMainMenuAll_AllData_NoWindows() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .mainMenuAll,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )
        dialogConfirmedOptions = .init(clearingOption: .allData, includeHistory: true, includeTabsAndWindows: true, includeCookiesAndSiteData: true, includeChatHistory: false, selectedCookieDomains: nil, selectedVisits: nil, isToday: false)
        _ = await coordinator.presentFireDialog(mode: .mainMenuAll, in: window)
        _ = try XCTUnwrap(fire.burnAllCalls.onlyValue)
    }

    /**
     Provider config:
     - domains: [a.com, b.com]
     - visits: today[a×2, b×1], yesterday[a×1], 2024-05-15[b×1]
     - Window/Tab State:
     - Window 1: Tab a.com (active) history: today[a×2], yesterday[a×1]; Tab b.com history: today[b×1], 2024-05-15[b×1]
     - Window 2: Tab figma.com (active) history: yesterday[figma×2]; Tab cook.ie history: today[cook.ie×1]
     Entry: Main Menu (All)
     Dialog config:
     - scopeSelector: visible, selected: All
     - tabs: hidden, default=true
     - hist: visible, default=true
     - data: visible, default=true
     - chats: visible, default=false
     - fireproof: visible
     - history link: hidden
     - title: "Delete All History"
     - selectedDomains: [a.com, b.com]
     - visitsCountSource: 12 (a×3, b×2, cook.ie×1, figma×2, date×2, c×2)
     User input:
     - scope: All (Unsupported)
     - tabs: false (Unsupported)
     - hist: false
     - data: true
     - selectedDomains: nil (all)
     Expectation:
     - burnEntity(allWindows, selectedDomains=[], close=false), includingHistory=false
     */
    func testMainMenuAll_AllData_NoTabs_CookiesOnly() async throws {
        FireDialogViewModel.lastSelectedClearingOption = .allData
        let expectedVisits = await mockHistoryProvider.visits(matching: .rangeFilter(.all))

        dialogExpectedInput = DialogExpectedInput(
            mode: .mainMenuAll,
            showSegmentedControl: true,
            showCloseWindowsAndTabsToggle: true,
            showFireproofSection: true,
            customTitle: "Delete all history?",
            showIndividualSitesLink: false,
            expectedClearingOption: .allData,
            expectedIncludeTabsAndWindows: true,
            expectedIncludeHistory: true,
            expectedIncludeCookiesAndSiteData: true,
            expectedIncludeChatHistory: false,
            expectedSelectable: allCookieDomains(except: fireproofDomains),
            expectedFireproofed: visitedFireproofDomains,
            expectedSelected: allCookieDomains(except: fireproofDomains).indices,
            expectedHistoryVisits: expectedVisits
        )

        dialogConfirmedOptions = .init(clearingOption: .allData,
                                       includeHistory: false,
                                       includeTabsAndWindows: false,
                                       includeCookiesAndSiteData: true,
                                       includeChatHistory: false,
                                       selectedCookieDomains: ["a.com", "b.com"],
                                       selectedVisits: nil,
                                       isToday: false)

        _ = await coordinator.presentFireDialog(mode: .mainMenuAll, in: window)
        let call = try XCTUnwrap(fire.burnEntityCalls.onlyValue)
        if case let .allWindows(_, selectedDomains, _, close) = call.entity {
            XCTAssertEqual(selectedDomains, ["a.com", "b.com"])
            XCTAssertFalse(close)
        } else { XCTFail("Expected allWindows") }
        XCTAssertFalse(call.includingHistory)
    }

    // MARK: - Helpers

    private func makeEntry(_ urlString: String) -> HistoryEntry {
        let url = URL(string: urlString)!
        return HistoryEntry(identifier: UUID(),
                            url: url,
                            title: nil,
                            failedToLoad: false,
                            numberOfTotalVisits: 0,
                            lastVisit: Date(),
                            visits: Set<Visit>(),
                            numberOfTrackersBlocked: 0,
                            blockedTrackingEntities: [],
                            trackersFound: false)
    }

    private func makeCoordinator(
        with fire: FireProtocol,
        customPresenterAction: ((NSWindow?, @escaping () -> Void) -> Void)? = nil
    ) -> FireCoordinator {
        let vm = FireViewModel(fire: fire)
        return FireCoordinator(
            tld: Application.appDelegate.tld,
            featureFlagger: Application.appDelegate.featureFlagger,
            historyCoordinating: Application.appDelegate.historyCoordinator,
            visualizeFireAnimationDecider: nil,
            onboardingContextualDialogsManager: nil,
            fireproofDomains: mockFireproofDomains,
            faviconManagement: FaviconManagerMock(),
            windowControllersManager: Application.appDelegate.windowControllersManager,
            pixelFiring: nil,
            historyProvider: mockHistoryProvider,
            fireViewModel: vm,
            tabViewModelGetter: { window in
                TabCollectionViewModel(isPopup: false)
            },
            fireDialogViewFactory: { config in
                return TestPresenter { window, completion in
                    // Execute custom action if provided (e.g., capture window)
                    customPresenterAction?(window, completion ?? {})

                    if let expected = self.dialogExpectedInput {
                        XCTAssertEqual(config.viewModel.mode, expected.mode, "mode", file: expected.file, line: expected.line + 1)
                        XCTAssertEqual(config.viewModel.mode.shouldShowSegmentedControl, expected.showSegmentedControl, "showSegmentedControl", file: expected.file, line: expected.line + 2)
                        XCTAssertEqual(config.viewModel.mode.shouldShowCloseTabsToggle, expected.showCloseWindowsAndTabsToggle, "showCloseWindowsAndTabsToggle", file: expected.file, line: expected.line + 3)
                        XCTAssertEqual(config.viewModel.mode.shouldShowFireproofSection, expected.showFireproofSection, "showFireproofSection", file: expected.file, line: expected.line + 4)
                        XCTAssertEqual(config.viewModel.mode.dialogTitle, expected.customTitle, "customTitle", file: expected.file, line: expected.line + 5)
                        XCTAssertEqual(config.showIndividualSitesLink, expected.showIndividualSitesLink, "showIndividualSitesLink", file: expected.file, line: expected.line + 6)
                        XCTAssertEqual(config.viewModel.clearingOption, expected.expectedClearingOption, "clearingOption", file: expected.file, line: expected.line + 7)
                        XCTAssertEqual(config.viewModel.includeTabsAndWindows, expected.expectedIncludeTabsAndWindows, "includeTabsAndWindows", file: expected.file, line: expected.line + 8)
                        XCTAssertEqual(config.viewModel.includeHistory, expected.expectedIncludeHistory, "includeHistory", file: expected.file, line: expected.line + 9)
                        XCTAssertEqual(config.viewModel.includeCookiesAndSiteData, expected.expectedIncludeCookiesAndSiteData, "includeCookiesAndSiteData", file: expected.file, line: expected.line + 10)
                        // Validate ViewModel data from provider
                        let actualSelectable = config.viewModel.selectable.map { $0.domain }.sorted()
                        XCTAssertEqual(actualSelectable, expected.expectedSelectable?.sorted() ?? [], "selectable domains", file: expected.file, line: expected.line + 11)
                        let actualFireproofed = config.viewModel.fireproofed.map { $0.domain }.sorted()
                        XCTAssertEqual(actualFireproofed, expected.expectedFireproofed?.sorted() ?? [], "fireproofed domains", file: expected.file, line: expected.line + 12)
                        XCTAssertEqual(config.viewModel.selected, expected.expectedSelected ?? [], "selected indices", file: expected.file, line: expected.line + 13)
                        XCTAssertEqual(config.viewModel.historyVisits ?? [], expected.expectedHistoryVisits ?? [], "historyVisits", file: expected.file, line: expected.line + 14)
                    }

                    var dialogConfirmedOptions = self.dialogConfirmedOptions
                    if dialogConfirmedOptions.selectedVisits == nil {
                        dialogConfirmedOptions.selectedVisits = config.viewModel.historyVisits
                    }
                    if dialogConfirmedOptions.selectedCookieDomains == nil {
                        dialogConfirmedOptions.selectedCookieDomains = config.viewModel.selectedCookieDomainsForScope
                    }
                    config.onConfirm(.burn(options: dialogConfirmedOptions))
                    completion?()
                }
            }
        )
    }

    var allCookieDomains: [String] {
        mockHistoryProvider.allCookieDomains
    }

    var fireproofDomains: [String] {
        mockFireproofDomains.fireproofDomains
    }

    func allCookieDomains(except: any Sequence<String>) -> [String] {
        let excludedDomains = Set(except)
        return allCookieDomains.filter { !excludedDomains.contains($0) }
    }

    var visitedFireproofDomains: [String] {
        let allCookieDomains = Set(allCookieDomains)
        return mockFireproofDomains.fireproofDomains.filter { allCookieDomains.contains($0) }
    }

}

private final class TestPresenter: FireDialogViewPresenting {
    private let handler: (NSWindow?, (() -> Void)?) -> Void
    init(handler: @escaping (NSWindow?, (() -> Void)?) -> Void) { self.handler = handler }
    func present(in window: NSWindow, completion: (() -> Void)?) { handler(window, completion) }
}

// Expected dialog configuration to validate against when presenter is invoked
private struct DialogExpectedInput {
    let file: StaticString
    let line: UInt

    var mode: FireDialogViewModel.Mode
    var showSegmentedControl: Bool
    var showCloseWindowsAndTabsToggle: Bool
    var showFireproofSection: Bool
    var customTitle: String?
    var showIndividualSitesLink: Bool
    var expectedClearingOption: FireDialogViewModel.ClearingOption
    var expectedIncludeTabsAndWindows: Bool
    var expectedIncludeHistory: Bool
    var expectedIncludeCookiesAndSiteData: Bool
    var expectedIncludeChatHistory: Bool

    // ViewModel data validation
    var expectedSelectable: [String]?
    var expectedFireproofed: [String]?
    var expectedSelected: Set<Int>?
    var expectedHistoryVisits: [Visit]?
    init(mode: FireDialogViewModel.Mode, showSegmentedControl: Bool, showCloseWindowsAndTabsToggle: Bool, showFireproofSection: Bool, customTitle: String?, showIndividualSitesLink: Bool, expectedClearingOption: FireDialogViewModel.ClearingOption, expectedIncludeTabsAndWindows: Bool, expectedIncludeHistory: Bool, expectedIncludeCookiesAndSiteData: Bool, expectedIncludeChatHistory: Bool, expectedSelectable: [String]?, expectedFireproofed: [String]?, expectedSelected: (any Sequence<Int>)?, expectedHistoryVisits: [Visit]? = nil, file: StaticString = #file, line: UInt = #line) {
        self.mode = mode
        self.showSegmentedControl = showSegmentedControl
        self.showCloseWindowsAndTabsToggle = showCloseWindowsAndTabsToggle
        self.showFireproofSection = showFireproofSection
        self.customTitle = customTitle
        self.showIndividualSitesLink = showIndividualSitesLink
        self.expectedClearingOption = expectedClearingOption
        self.expectedIncludeTabsAndWindows = expectedIncludeTabsAndWindows
        self.expectedIncludeHistory = expectedIncludeHistory
        self.expectedIncludeCookiesAndSiteData = expectedIncludeCookiesAndSiteData
        self.expectedIncludeChatHistory = expectedIncludeChatHistory
        self.expectedSelectable = expectedSelectable
        self.expectedFireproofed = expectedFireproofed
        self.expectedSelected = expectedSelected?.reduce(into: Set<Int>()) { $0.insert($1) }
        self.expectedHistoryVisits = expectedHistoryVisits
        self.file = file
        self.line = line
    }
}

// MARK: - Test helpers

private extension Array {
    var onlyValue: Element? { count == 1 ? first : nil }
}
private extension FireDialogResult {
    init(clearingOption: FireDialogViewModel.ClearingOption, includeHistory: Bool, includeTabsAndWindows: Bool, includeCookiesAndSiteData: Bool, includeChatHistory: Bool, isToday: Bool) {
        self.init(clearingOption: clearingOption, includeHistory: includeHistory, includeTabsAndWindows: includeTabsAndWindows, includeCookiesAndSiteData: includeCookiesAndSiteData, includeChatHistory: includeChatHistory, selectedCookieDomains: nil, selectedVisits: nil, isToday: isToday)
    }
}
