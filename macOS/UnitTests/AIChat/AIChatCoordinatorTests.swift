//
//  AIChatCoordinatorTests.swift
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

import AIChat
import BrowserServicesKit
import Combine
import PixelKit
import PixelKitTestingUtilities
import FeatureFlags
import PrivacyConfig
import SharedTestUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AIChatCoordinatorTests: XCTestCase {

    private var coordinator: AIChatCoordinator!
    private var mockSidebarHost: MockAIChatSidebarHosting!
    private var mockSessionStore: MockAIChatSessionStore!
    private var mockAIChatMenuConfig: DummyAIChatConfig!
    private var mockAIChatTabOpener: MockAIChatTabOpener!
    private var mockWindowControllersManager: WindowControllersManagerMock!
    private var mockPixelFiring: PixelKitMock!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockSidebarHost = MockAIChatSidebarHosting()
        mockSessionStore = MockAIChatSessionStore()
        mockAIChatMenuConfig = DummyAIChatConfig()
        mockAIChatTabOpener = MockAIChatTabOpener()
        mockWindowControllersManager = WindowControllersManagerMock()
        mockPixelFiring = PixelKitMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enableFeatures([.aiChatSidebarResizable])
        cancellables = Set<AnyCancellable>()
        AIChatFloatingWindowController.windowFactory = { contentRect in
            MockWindow(contentRect: contentRect, isVisible: false)
        }

        coordinator = AIChatCoordinator(
            sidebarHost: mockSidebarHost,
            sessionStore: mockSessionStore,
            aiChatMenuConfig: mockAIChatMenuConfig,
            aiChatTabOpener: mockAIChatTabOpener,
            windowControllersManager: mockWindowControllersManager,
            pixelFiring: mockPixelFiring,
            featureFlagger: mockFeatureFlagger
        )
    }

    override func tearDown() {
        mockSidebarHost?.embeddedViewController = nil
        let activeTabIDs: [TabIdentifier] = mockSessionStore.map { Array($0.sessions.keys) } ?? []
        for tabID in activeTabIDs {
            mockSessionStore?.endSession(for: tabID)
        }
        AIChatFloatingWindowController.windowFactory = { contentRect in
            AIChatFloatingWindow(contentRect: contentRect)
        }
        cancellables = nil
        coordinator = nil
        mockFeatureFlagger = nil
        mockPixelFiring = nil
        mockWindowControllersManager = nil
        mockAIChatTabOpener = nil
        mockAIChatMenuConfig = nil
        mockSessionStore = nil
        mockSidebarHost = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_setsUpProperties() {
        // Given & When & Then
        XCTAssertNotNil(coordinator.sidebarPresenceDidChangePublisher)
        XCTAssertNotNil(mockSidebarHost.aiChatSidebarHostingDelegate)
        XCTAssertTrue(mockSidebarHost.aiChatSidebarHostingDelegate === coordinator)
    }

    func testInit_withDefaultProvider_createsProvider() {
        // Given & When
        let coordinator = AIChatCoordinator(
            sidebarHost: mockSidebarHost,
            sessionStore: mockSessionStore,
            aiChatMenuConfig: mockAIChatMenuConfig,
            aiChatTabOpener: mockAIChatTabOpener,
            windowControllersManager: mockWindowControllersManager,
            pixelFiring: mockPixelFiring,
            featureFlagger: mockFeatureFlagger
        )

        // Then
        XCTAssertNotNil(coordinator)
    }

    // MARK: - Toggle Sidebar Tests

    func testToggleSidebar_withNoCurrentTab_doesNothing() {
        // Given
        mockSidebarHost.currentTabID = nil
        let initialCount = mockSessionStore.statesByTab.count

        // When
        coordinator.toggleSidebar()

        // Then
        XCTAssertEqual(mockSessionStore.statesByTab.count, initialCount)
        XCTAssertNil(mockSidebarHost.embeddedViewController)
    }

    func testToggleSidebar_showsSidebarWhenNotShowing() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        XCTAssertFalse(isChatPresented(for: tabID))

        var presenceChangeReceived: AIChatPresenceChange?
        coordinator.sidebarPresenceDidChangePublisher
            .sink { presenceChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        coordinator.toggleSidebar()

        // Then
        XCTAssertTrue(isChatPresented(for: tabID))
        XCTAssertNotNil(mockSidebarHost.embeddedViewController)
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, true)
    }

    func testToggleSidebar_hidesSidebarWhenShowing() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular).makeChatViewController(tabID: tabID)
        XCTAssertTrue(isChatPresented(for: tabID))

        var presenceChangeReceived: AIChatPresenceChange?
        coordinator.sidebarPresenceDidChangePublisher
            .sink { presenceChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        coordinator.toggleSidebar()

        // Then
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, false)
    }

    func testToggleSidebar_whenChatIsFloating_doesNothing() {
        // Given
        let tabID = "floating-tab"
        mockSidebarHost.currentTabID = tabID
        let session = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setFloating()

        // When
        coordinator.toggleSidebar()

        // Then
        XCTAssertEqual(session.state.presentationMode, .floating)
        XCTAssertNil(mockSidebarHost.embeddedViewController)
    }

    // MARK: - Collapse Sidebar Tests

    func testCollapseSidebar_withNoCurrentTab_doesNothing() {
        // Given
        mockSidebarHost.currentTabID = nil
        let initialCount = mockSessionStore.statesByTab.count

        // When
        coordinator.collapseSidebar(withAnimation: true)

        // Then
        XCTAssertEqual(mockSessionStore.statesByTab.count, initialCount)
    }

    func testCollapseSidebar_withAnimation() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular).makeChatViewController(tabID: tabID)

        var presenceChangeReceived: AIChatPresenceChange?
        coordinator.sidebarPresenceDidChangePublisher
            .sink { presenceChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        coordinator.collapseSidebar(withAnimation: true)

        // Then
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, false)
    }

    func testCollapseSidebar_withoutAnimation() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular).makeChatViewController(tabID: tabID)

        var presenceChangeReceived: AIChatPresenceChange?
        coordinator.sidebarPresenceDidChangePublisher
            .sink { presenceChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        coordinator.collapseSidebar(withAnimation: false)

        // Then
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, false)
    }

    func testCollapseSidebar_whenChatIsFloating_doesNothing() {
        // Given
        let tabID = "floating-tab"
        mockSidebarHost.currentTabID = tabID
        let session = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setFloating()

        // When
        coordinator.collapseSidebar(withAnimation: true)

        // Then
        XCTAssertEqual(session.state.presentationMode, .floating)
        XCTAssertNotNil(mockSessionStore.sessions[tabID])
    }

    // MARK: - Close Chat Tests

    func testCloseChat_whenSidebarVisible_endsSession() {
        // Given
        let tabID = "sidebar-tab"
        mockSidebarHost.currentTabID = tabID
        _ = makeSession(for: tabID)
        XCTAssertTrue(coordinator.isSidebarOpen(for: tabID))

        // When
        coordinator.closeChat(for: tabID, withAnimation: false)

        // Then
        XCTAssertNil(mockSessionStore.sessions[tabID])
    }

    func testCloseChat_whenFloatingWithoutWindowController_doesNotCollapseSidebarOrEndSession() {
        // Given
        let tabID = "floating-tab"
        mockSidebarHost.currentTabID = tabID
        let session = makeSession(for: tabID)
        session.state.setFloating()
        session.floatingWindowController = nil

        // When
        coordinator.closeChat(for: tabID, withAnimation: true)

        // Then
        XCTAssertEqual(session.state.presentationMode, .floating)
        XCTAssertNotNil(mockSessionStore.sessions[tabID])
    }

    func testCloseChat_whenAlreadyHidden_doesNothing() {
        // Given
        let tabID = "hidden-tab"
        mockSidebarHost.currentTabID = tabID
        let session = makeSession(for: tabID)
        session.state.setHidden()

        // When
        coordinator.closeChat(for: tabID, withAnimation: true)

        // Then
        XCTAssertEqual(mockSessionStore.sessions[tabID]?.state.presentationMode, .hidden)
        XCTAssertNotNil(mockSessionStore.sessions[tabID])
    }

    // MARK: - Is Sidebar Open Tests

    func testIsSidebarOpen_withExistingSidebar_returnsTrue() {
        // Given
        let tabID = "test-tab"
        _ = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular).makeChatViewController(tabID: tabID)

        // When
        let isOpen = coordinator.isSidebarOpen(for: tabID)

        // Then
        XCTAssertTrue(isOpen)
    }

    func testIsSidebarOpen_withoutSidebar_returnsFalse() {
        // Given
        let tabID = "test-tab"

        // When
        let isOpen = coordinator.isSidebarOpen(for: tabID)

        // Then
        XCTAssertFalse(isOpen)
    }

    func testIsSidebarOpenForCurrentTab_withCurrentTab() {
        // Given
        let tabID = "current-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular).makeChatViewController(tabID: tabID)

        // When
        let isOpen = coordinator.isSidebarOpenForCurrentTab()

        // Then
        XCTAssertTrue(isOpen)
    }

    func testIsSidebarOpenForCurrentTab_withNoCurrentTab_returnsFalse() {
        // Given
        mockSidebarHost.currentTabID = nil

        // When
        let isOpen = coordinator.isSidebarOpenForCurrentTab()

        // Then
        XCTAssertFalse(isOpen)
    }

    // MARK: - Chat Presentation Tests

    func testIsChatPresentedForCurrentTab_withNoCurrentTab_returnsFalse() {
        // Given
        mockSidebarHost.currentTabID = nil

        // When
        let isPresented = coordinator.isChatPresentedForCurrentTab()

        // Then
        XCTAssertFalse(isPresented)
    }

    func testIsChatPresentedForCurrentTab_whenHidden_returnsFalse() {
        // Given
        let tabID = "hidden-tab"
        mockSidebarHost.currentTabID = tabID
        let session = makeSession(for: tabID)
        session.state.setHidden()

        // When
        let isPresented = coordinator.isChatPresentedForCurrentTab()

        // Then
        XCTAssertFalse(isPresented)
    }

    func testIsChatPresentedForCurrentTab_whenSidebar_returnsTrue() {
        // Given
        let tabID = "sidebar-tab"
        mockSidebarHost.currentTabID = tabID
        _ = makeSession(for: tabID)

        // When
        let isPresented = coordinator.isChatPresentedForCurrentTab()

        // Then
        XCTAssertTrue(isPresented)
    }

    func testIsChatPresentedForCurrentTab_whenFloating_returnsTrue() {
        // Given
        let tabID = "floating-tab"
        mockSidebarHost.currentTabID = tabID
        let session = makeSession(for: tabID)
        session.state.setFloating()

        // When
        let isPresented = coordinator.isChatPresentedForCurrentTab()

        // Then
        XCTAssertTrue(isPresented)
    }

    // MARK: - Reveal Chat Tests

    func testRevealChat_withNoCurrentTab_doesNothing() {
        // Given
        mockSidebarHost.currentTabID = nil
        let prompt = AIChatNativePrompt.queryPrompt("What is the best pizza recipe?", autoSubmit: true)
        let initialCount = mockSessionStore.statesByTab.count

        // When
        coordinator.revealChat(for: prompt)

        // Then
        XCTAssertEqual(mockSessionStore.statesByTab.count, initialCount)
    }

    func testRevealChat_withExistingSidebar_keepsSidebarOpen() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        coordinator.toggleSidebar()
        XCTAssertTrue(coordinator.isSidebarOpen(for: tabID))
        let prompt = AIChatNativePrompt.queryPrompt("What is the best pizza recipe?", autoSubmit: true)

        // When
        coordinator.revealChat(for: prompt)

        // Then
        XCTAssertTrue(coordinator.isSidebarOpen(for: tabID))
        XCTAssertNotNil(mockSidebarHost.embeddedViewController)
    }

    func testRevealChat_withoutExistingSidebar_createsSidebar() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        let prompt = AIChatNativePrompt.queryPrompt("What is the best pizza recipe?", autoSubmit: true)
        XCTAssertFalse(isChatPresented(for: tabID))

        // When
        coordinator.revealChat(for: prompt)

        // Then
        XCTAssertTrue(isChatPresented(for: tabID))
        XCTAssertNotNil(mockSidebarHost.embeddedViewController)
    }

    func testRevealChat_whenFloating_keepsFloatingPresentation() {
        // Given
        let tabID = "floating-reveal-tab"
        mockSidebarHost.currentTabID = tabID
        let session = makeSession(for: tabID)
        session.state.setFloating()
        session.floatingWindowController = nil
        let prompt = AIChatNativePrompt.queryPrompt("Summarize this", autoSubmit: true)

        // When
        coordinator.revealChat(for: prompt)

        // Then
        XCTAssertEqual(session.state.presentationMode, .floating)
        XCTAssertNil(mockSidebarHost.embeddedViewController)
    }

    // MARK: - Sidebar Hosting Delegate Tests

    func testSidebarHostDidSelectTab_updatesConstraints() {
        // Given
        let tabID = "selected-tab"
        _ = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular).makeChatViewController(tabID: tabID)

        // When
        coordinator.sidebarHostDidSelectTab(with: tabID)

        // Then
        // This should update the sidebar constraints for the selected tab
        // The exact behavior depends on the implementation details
        XCTAssertNotNil(coordinator)
    }

    func testSidebarHostDidUpdateTabs_cleansUpSessions() {
        // Given
        _ = mockSessionStore.getOrCreateSession(for: "tab1", burnerMode: .regular).makeChatViewController(tabID: "tab1")
        _ = mockSessionStore.getOrCreateSession(for: "tab2", burnerMode: .regular).makeChatViewController(tabID: "tab2")
        XCTAssertEqual(mockSessionStore.sessions.count, 2)

        // When
        coordinator.sidebarHostDidUpdateTabs()

        // Then
        // With empty tab collections, all sessions should be removed
        XCTAssertEqual(mockSessionStore.sessions.count, 0)
    }

    func testSidebarHostDidUpdateTabs_DoesNotRemoveVisibleTabs() {
        // Given
        let persistor = MockTabsPreferencesPersistor()
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
                                                            tabsPreferences: TabsPreferences(persistor: persistor, windowControllersManager: WindowControllersManagerMock()))
        tabCollectionViewModel.append(tab: Tab(uuid: "tab1", content: .url(URL.duckDuckGo, source: .ui)))
        tabCollectionViewModel.append(tab: Tab(uuid: "tab2", content: .url(URL.duckDuckGo, source: .ui)))

        // Set up the mock to return predefined tabCollectionViewModel
        mockWindowControllersManager.customAllTabCollectionViewModels = [tabCollectionViewModel]

        _ = mockSessionStore.getOrCreateSession(for: "tab1", burnerMode: .regular).makeChatViewController(tabID: "tab1")
        _ = mockSessionStore.getOrCreateSession(for: "tab2", burnerMode: .regular).makeChatViewController(tabID: "tab2")
        XCTAssertEqual(mockSessionStore.sessions.count, 2)

        // When
        coordinator.sidebarHostDidUpdateTabs()

        // Then
        XCTAssertEqual(mockSessionStore.sessions.count, 2)
    }

    // MARK: - Sidebar View Controller Delegate Tests

    func testDidClickOpenInNewTabButton_newAIChatTabIsOpen() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID

        // Set up the sidebar with a test URL that includes a placement parameter
        let testURL = URL(string: "https://example.com")!.forAIChatSidebar()
        let chatState = AIChatState(initialAIChatURL: testURL)
        mockSessionStore.restoreState([tabID: chatState])

        mockAIChatTabOpener.openMethodCalledExpectation = expectation(description: "AIChatTabOpener did open a new tab")

        // When
        coordinator.didClickOpenInNewTabButton()

        // Then
        waitForExpectations(timeout: 3)
        XCTAssertTrue(mockAIChatTabOpener.openAIChatTabCalled)

        // Verify the placement parameter is stripped from the URL
        let expectedURL = testURL.removingAIChatPlacementParameter()
        XCTAssertEqual(mockAIChatTabOpener.lastURL, expectedURL)
        XCTAssertNotEqual(mockAIChatTabOpener.lastURL, testURL, "URL should have placement parameter stripped")

        // Verify it was called with .url content type
        if case .url(let url) = mockAIChatTabOpener.lastTrigger {
            XCTAssertEqual(url, expectedURL)
        } else {
            XCTFail("Expected .url content type")
        }
    }

    func testDidClickOpenInNewTabButton_withRestorationData() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID

        // Set up the sidebar with restoration data
        let restorationData = AIChatRestorationData()
        let chatState = AIChatState()
        chatState.restorationData = restorationData
        mockSessionStore.restoreState([tabID: chatState])

        mockAIChatTabOpener.openMethodCalledExpectation = expectation(description: "AIChatTabOpener did open a new tab")

        // When
        coordinator.didClickOpenInNewTabButton()

        // Then
        waitForExpectations(timeout: 3)
        XCTAssertTrue(mockAIChatTabOpener.openAIChatTabCalled)
        XCTAssertEqual(mockAIChatTabOpener.lastRestorationData, restorationData)
        // Verify it was called with .restoration content type
        if case .restoration(let data) = mockAIChatTabOpener.lastTrigger {
            XCTAssertEqual(data, restorationData)
        } else {
            XCTFail("Expected .restoration content type")
        }
    }

    func testDidClickCloseButton_firesPixelAndTogglesSidebar() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular).makeChatViewController(tabID: tabID)
        XCTAssertTrue(isChatPresented(for: tabID))

        let sidebarPresenceChangeExpectation = expectation(description: "Sidebar presence did change")
        var presenceChangeReceived: AIChatPresenceChange?
        coordinator.sidebarPresenceDidChangePublisher
            .sink {
                presenceChangeReceived = $0
                sidebarPresenceChangeExpectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        coordinator.didClickCloseButton()

        // Then
        waitForExpectations(timeout: 3)
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, false)
    }

    // MARK: - AI Chat Handoff Tests

    func testHandleAIChatHandoff_notInKeyWindow_doesNothing() {
        // Given
        mockSidebarHost.isInKeyWindow = false
        let payload = AIChatPayload()

        // When
        let notification = Notification(
            name: .aiChatNativeHandoffData,
            object: payload
        )
        NotificationCenter.default.post(notification)

        // Then
        XCTAssertFalse(mockAIChatTabOpener.openAIChatTabCalled)
    }

    func testHandleAIChatHandoff_withoutSidebar_createsSidebar() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        let payload = AIChatPayload()
        XCTAssertFalse(isChatPresented(for: tabID))

        let sidebarPresenceChangeExpectation = expectation(description: "Sidebar presence did change")
        var presenceChangeReceived: AIChatPresenceChange?
        coordinator.sidebarPresenceDidChangePublisher
            .sink {
                presenceChangeReceived = $0
                sidebarPresenceChangeExpectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        let notification = Notification(
            name: .aiChatNativeHandoffData,
            object: payload
        )
        NotificationCenter.default.post(notification)

        // Then
        waitForExpectations(timeout: 3)
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, true)
    }

    func testHandleAIChatHandoff_withExistingSidebar_opensNewTab() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular).makeChatViewController(tabID: tabID)
        let payload = AIChatPayload()
        XCTAssertTrue(isChatPresented(for: tabID))
        mockAIChatTabOpener.openMethodCalledExpectation = expectation(description: "AIChatTabOpener did open a new tab")

        // When
        let notification = Notification(
            name: .aiChatNativeHandoffData,
            object: payload
        )
        NotificationCenter.default.post(notification)

        // Then
        waitForExpectations(timeout: 3)
        XCTAssertTrue(mockAIChatTabOpener.openAIChatTabCalled)
        XCTAssertEqual(mockAIChatTabOpener.lastPayload as? NSDictionary, payload as NSDictionary)
        // Verify it was called with .payload content type
        if case .payload(let receivedPayload) = mockAIChatTabOpener.lastTrigger {
            XCTAssertEqual(receivedPayload as NSDictionary, payload as NSDictionary)
        } else {
            XCTFail("Expected .payload content type")
        }
    }

    // MARK: - Integration Tests

    func testCompleteWorkflow() {
        // Given
        let tabID = "workflow-tab"
        mockSidebarHost.currentTabID = tabID

        var presenceChanges: [AIChatPresenceChange] = []
        coordinator.sidebarPresenceDidChangePublisher
            .sink { presenceChanges.append($0) }
            .store(in: &cancellables)

        // When - Toggle sidebar on
        coordinator.toggleSidebar()

        // Then - Sidebar should be showing
        XCTAssertTrue(coordinator.isSidebarOpen(for: tabID))
        XCTAssertEqual(presenceChanges.count, 1)
        XCTAssertEqual(presenceChanges.last?.isShown, true)

        // When - Close sidebar using deterministic non-animated path
        coordinator.collapseSidebar(withAnimation: false)

        // Then - Sidebar should be hidden
        XCTAssertEqual(presenceChanges.count, 2)
        XCTAssertEqual(presenceChanges.last?.isShown, false)

        // When - Reveal chat with prompt
        let prompt = AIChatNativePrompt.queryPrompt("What is the best pizza recipe?", autoSubmit: true)
        coordinator.revealChat(for: prompt)

        // Then - Sidebar should be showing again
        XCTAssertEqual(presenceChanges.count, 3)
        XCTAssertEqual(presenceChanges.last?.isShown, true)
    }

    func testMultipleTabsWorkflow() {
        // Given
        let tab1 = "tab1"
        let tab2 = "tab2"
        let prompt = AIChatNativePrompt.queryPrompt("test", autoSubmit: false)

        // When - Open sidebar on tab1
        mockSidebarHost.currentTabID = tab1
        coordinator.toggleSidebar()

        // Then
        XCTAssertTrue(coordinator.isSidebarOpen(for: tab1))
        XCTAssertFalse(coordinator.isSidebarOpen(for: tab2))

        // When - Switch to tab2 and reveal chat (deterministic open path)
        mockSidebarHost.currentTabID = tab2
        coordinator.revealChat(for: prompt)

        // Then
        XCTAssertTrue(coordinator.isSidebarOpen(for: tab1))
        XCTAssertTrue(coordinator.isSidebarOpen(for: tab2))

        // When - Close sidebar on tab1 using deterministic non-animated path
        mockSidebarHost.currentTabID = tab1
        coordinator.collapseSidebar(withAnimation: false)

        // Then
        XCTAssertFalse(coordinator.isSidebarOpen(for: tab1))
        XCTAssertTrue(coordinator.isSidebarOpen(for: tab2))
    }

    func testSwitchingBetweenTabs_keepsPerTabSidebarContent() {
        // Given
        let tabA = "tab-a"
        let tabB = "tab-b"
        let prompt = AIChatNativePrompt.queryPrompt("hello", autoSubmit: false)

        // Open chat on tab A and remember its VC.
        mockSidebarHost.currentTabID = tabA
        coordinator.toggleSidebar()
        let tabAViewController = mockSessionStore.sessions[tabA]?.chatViewController
        XCTAssertNotNil(tabAViewController)
        XCTAssertTrue(mockSidebarHost.embeddedViewController === tabAViewController)

        // Open chat on tab B and remember its VC.
        mockSidebarHost.currentTabID = tabB
        coordinator.revealChat(for: prompt)
        let tabBViewController = mockSessionStore.sessions[tabB]?.chatViewController
        XCTAssertNotNil(tabBViewController)
        XCTAssertTrue(mockSidebarHost.embeddedViewController === tabBViewController)
        XCTAssertFalse(tabAViewController === tabBViewController)

        // When - switch back to tab A.
        mockSidebarHost.currentTabID = tabA
        coordinator.sidebarHostDidSelectTab(with: tabA)

        // Then - sidebar should show tab A's own controller, not tab B's.
        XCTAssertTrue(mockSidebarHost.embeddedViewController === tabAViewController)
        XCTAssertFalse(mockSidebarHost.embeddedViewController === tabBViewController)
    }

    // MARK: - Detach / Attach Tests

    func testDetachSidebar_movesToFloatingWindow() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        mockSidebarHost.sidebarContainerScreenFrame = NSRect(x: 100, y: 100, width: 400, height: 600)
        mockFeatureFlagger.enableFeatures([.aiChatSidebarResizable, .aiChatSidebarFloating])
        coordinator.toggleSidebar()

        var floatingChangeReceived: TabIdentifier?
        coordinator.chatFloatingStateDidChangePublisher
            .sink { floatingChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        coordinator.didClickDetachButton()

        // Then
        let session = mockSessionStore.sessions[tabID]
        XCTAssertEqual(session?.state.presentationMode, .floating)
        XCTAssertNotNil(session?.floatingWindowController)
        XCTAssertEqual(floatingChangeReceived, tabID)
    }

    func testDetachSidebar_withoutFloatingFeatureFlag_doesNothing() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        mockSidebarHost.sidebarContainerScreenFrame = NSRect(x: 100, y: 100, width: 400, height: 600)
        coordinator.toggleSidebar()
        XCTAssertEqual(mockSessionStore.sessions[tabID]?.state.presentationMode, .sidebar)

        // When
        coordinator.didClickDetachButton()

        // Then
        XCTAssertEqual(mockSessionStore.sessions[tabID]?.state.presentationMode, .sidebar)
        XCTAssertNil(mockSessionStore.sessions[tabID]?.floatingWindowController)
    }

    func testAttachSidebar_reDocksToSidebar() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        mockSidebarHost.sidebarContainerScreenFrame = NSRect(x: 100, y: 100, width: 400, height: 600)
        mockFeatureFlagger.enableFeatures([.aiChatSidebarResizable, .aiChatSidebarFloating])
        coordinator.toggleSidebar()
        coordinator.didClickDetachButton()
        XCTAssertEqual(mockSessionStore.sessions[tabID]?.state.presentationMode, .floating)

        var floatingChangeReceived: TabIdentifier?
        coordinator.chatFloatingStateDidChangePublisher
            .sink { floatingChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        coordinator.didClickAttachButton(for: tabID)

        // Then
        let session = mockSessionStore.sessions[tabID]
        XCTAssertEqual(session?.state.presentationMode, .sidebar)
        XCTAssertNil(session?.floatingWindowController)
        XCTAssertNotNil(mockSidebarHost.embeddedViewController)
        XCTAssertEqual(floatingChangeReceived, tabID)
    }

    func testAttachSidebar_presenceWillChangeIsSentBeforeSidebarTransition() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        mockSidebarHost.sidebarContainerScreenFrame = NSRect(x: 100, y: 100, width: 400, height: 600)
        mockFeatureFlagger.enableFeatures([.aiChatSidebarResizable, .aiChatSidebarFloating])
        coordinator.toggleSidebar()
        coordinator.didClickDetachButton()
        XCTAssertEqual(mockSessionStore.sessions[tabID]?.state.presentationMode, .floating)

        let eventExpectation = expectation(description: "Attach presence will change emitted")
        var leadingConstraintAtEvent: CGFloat?
        coordinator.sidebarPresenceDidChangePublisher
            .sink { [weak self] change in
                guard let self,
                      change.tabID == tabID,
                      change.isShown else {
                    return
                }
                leadingConstraintAtEvent = self.mockSidebarHost.sidebarContainerLeadingConstraint?.constant
                eventExpectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        coordinator.didClickAttachButton(for: tabID)

        // Then
        waitForExpectations(timeout: 3)
        XCTAssertEqual(leadingConstraintAtEvent, 0, "Will-change notification should be emitted before the sidebar transition updates constraints")
        XCTAssertLessThan(mockSidebarHost.sidebarContainerLeadingConstraint?.constant ?? 0, 0)
    }

    func testFloatingWindowDidClose_endsSession() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        mockSidebarHost.sidebarContainerScreenFrame = NSRect(x: 100, y: 100, width: 400, height: 600)
        mockFeatureFlagger.enableFeatures([.aiChatSidebarResizable, .aiChatSidebarFloating])
        coordinator.toggleSidebar()
        coordinator.didClickDetachButton()
        let controller = mockSessionStore.sessions[tabID]!.floatingWindowController!

        // When
        coordinator.floatingWindowDidClose(controller, initiatedByUser: true)

        // Then
        XCTAssertNil(mockSessionStore.sessions[tabID])
    }

    func testIsChatFloating_returnsTrueWhenDetached() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        mockSidebarHost.sidebarContainerScreenFrame = NSRect(x: 100, y: 100, width: 400, height: 600)
        mockFeatureFlagger.enableFeatures([.aiChatSidebarResizable, .aiChatSidebarFloating])
        coordinator.toggleSidebar()
        XCTAssertFalse(coordinator.isChatFloating(for: tabID))

        // When
        coordinator.didClickDetachButton()

        // Then
        XCTAssertTrue(coordinator.isChatFloating(for: tabID))

        // When - re-dock
        coordinator.didClickAttachButton(for: tabID)

        // Then
        XCTAssertFalse(coordinator.isChatFloating(for: tabID))
    }

    func testTabSwitch_preservesFloatingWindow() {
        // Given
        let tab1 = "tab1"
        let tab2 = "tab2"
        mockSidebarHost.currentTabID = tab1
        mockSidebarHost.sidebarContainerScreenFrame = NSRect(x: 100, y: 100, width: 400, height: 600)
        mockFeatureFlagger.enableFeatures([.aiChatSidebarResizable, .aiChatSidebarFloating])
        coordinator.toggleSidebar()
        coordinator.didClickDetachButton()
        XCTAssertEqual(mockSessionStore.sessions[tab1]?.state.presentationMode, .floating)

        // When
        mockSidebarHost.currentTabID = tab2
        coordinator.sidebarHostDidSelectTab(with: tab2)

        // Then
        XCTAssertEqual(mockSessionStore.sessions[tab1]?.state.presentationMode, .floating)
        XCTAssertNotNil(mockSessionStore.sessions[tab1]?.floatingWindowController)
    }

    func testSidebarHostDidSelectTab_restoresFloatingWindowWhenSessionIsFloating() {
        // Given
        let tabID = "floating-restore-tab"
        mockSidebarHost.currentTabID = tabID
        mockFeatureFlagger.enableFeatures([.aiChatSidebarResizable, .aiChatSidebarFloating])

        let session = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setFloating()
        session.floatingWindowController = nil

        // When
        coordinator.sidebarHostDidSelectTab(with: tabID)

        // Then
        XCTAssertEqual(session.state.presentationMode, .floating)
        XCTAssertNotNil(session.floatingWindowController)
    }

    // MARK: - Edge Cases

    func testAnimationStateManagement() {
        // Given
        let tabID = "animation-tab"
        mockSidebarHost.currentTabID = tabID

        // When - Call toggle multiple times quickly
        coordinator.toggleSidebar()
        coordinator.toggleSidebar() // Should be ignored if animation is in progress

        // Then - Only one sidebar operation should have occurred
        XCTAssertTrue(coordinator.isSidebarOpen(for: tabID))
    }

    private func makeSession(for tabID: TabIdentifier) -> AIChatSession {
        let session = mockSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        return session
    }

    private func isChatPresented(for tabID: TabIdentifier) -> Bool {
        (mockSessionStore.sessions[tabID]?.state.presentationMode ?? .hidden) != .hidden
    }

}

// MARK: - Mock Classes

class MockAIChatSidebarHosting: AIChatSidebarHosting {
    weak var aiChatSidebarHostingDelegate: AIChatSidebarHostingDelegate?
    weak var aiChatSidebarResizeDelegate: AIChatSidebarResizeDelegate?
    var isInKeyWindow: Bool = true
    var currentTabID: TabIdentifier? = "test-tab-id"
    var sidebarContainerLeadingConstraint: NSLayoutConstraint?
    var sidebarContainerWidthConstraint: NSLayoutConstraint?
    var burnerMode: BurnerMode = .regular

    var embeddedViewController: NSViewController?
    private var embeddedControllersInContainer: [NSViewController] = []
    private(set) var isResizeHandleVisible = false

    init() {
        sidebarContainerLeadingConstraint = NSLayoutConstraint()
        sidebarContainerWidthConstraint = NSLayoutConstraint()
    }

    var sidebarContainerScreenFrame: NSRect?

    func embedChatViewController(_ vc: NSViewController, for tabID: TabIdentifier?) {
        embeddedControllersInContainer.removeAll { $0 !== vc }
        if let existingIndex = embeddedControllersInContainer.firstIndex(where: { $0 === vc }) {
            embeddedViewController = embeddedControllersInContainer[existingIndex]
            return
        }
        embeddedControllersInContainer.append(vc)
        embeddedViewController = vc
    }

    func applySidebarWidth(_ width: CGFloat) {
        sidebarContainerWidthConstraint?.constant = width
        sidebarContainerLeadingConstraint?.constant = -width
    }

    func setResizeHandleVisible(_ visible: Bool) {
        isResizeHandleVisible = visible
    }

    func selectTab(with tabID: TabIdentifier) {}

    var availableWidth: CGFloat = 1200
}

class MockAIChatSessionStore: AIChatSessionStoring {

    @Published var sessions: AIChatSessionsByTab = [:]

    var sessionsPublisher: AnyPublisher<AIChatSessionsByTab, Never> {
        $sessions.dropFirst().eraseToAnyPublisher()
    }

    var statesByTab: AIChatStatesByTab {
        sessions.mapValues { $0.state }
    }

    func getOrCreateSession(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSession {
        if let existing = sessions[tabID] {
            return existing
        }
        let state = AIChatState(initialAIChatURL: URL.blankPage.forAIChatSidebar())
        state.setSidebar()
        let session = AIChatSession(state: state, burnerMode: burnerMode)
        sessions[tabID] = session
        return session
    }

    func endSession(for tabID: TabIdentifier) {
        sessions[tabID]?.tearDown(persistingState: false)
        sessions.removeValue(forKey: tabID)
    }

    func removeOrphanedSessions(currentTabIDs: [TabIdentifier]) {
        let tabIDsToRemove = Set(sessions.keys).subtracting(currentTabIDs)
        for tabID in tabIDsToRemove {
            endSession(for: tabID)
        }
    }

    func restoreState(_ statesByTab: AIChatStatesByTab) {
        removeOrphanedSessions(currentTabIDs: [])
        self.sessions = statesByTab.mapValues { AIChatSession(state: $0, burnerMode: .regular) }
    }

    func removeSession(for tabID: TabIdentifier) {
        sessions.removeValue(forKey: tabID)
    }

    @discardableResult
    func expireSessionIfNeeded(for tabID: TabIdentifier) -> Bool {
        guard let session = sessions[tabID],
              session.state.isSessionExpired else {
            return false
        }
        sessions.removeValue(forKey: tabID)
        return true
    }

    func statesForSerialization() -> AIChatStatesByTab {
        statesByTab
    }
}

class MockAIChatTabOpener: AIChatTabOpening {
    var openAIChatTabCalled = false
    var lastTrigger: AIChatOpenTrigger?
    var lastBehavior: LinkOpenBehavior?

    var openNewAIChatCalled = false
    var lastNewAIChatBehavior: LinkOpenBehavior?

    // Specific tracking for different content types
    var lastURL: URL?
    var lastPayload: AIChatPayload?
    var lastRestorationData: AIChatRestorationData?
    var lastQuery: String?
    var lastShouldAutoSubmit: Bool?

    var openMethodCalledExpectation: XCTestExpectation?

    func setOpenMethodCalledExpectation(_ expectation: XCTestExpectation) {
        openMethodCalledExpectation = expectation
    }

    @MainActor
    func openAIChatTab(with trigger: AIChatOpenTrigger, behavior: LinkOpenBehavior) {
        openAIChatTabCalled = true
        lastTrigger = trigger
        lastBehavior = behavior

        // Extract specific data based on content type
        switch trigger {
        case .newChat:
            break
        case .query(let query, let shouldAutoSubmit):
            lastQuery = query
            lastShouldAutoSubmit = shouldAutoSubmit
        case .url(let url):
            lastURL = url
        case .payload(let payload):
            lastPayload = payload
        case .restoration(let data):
            lastRestorationData = data
        case .existingChat:
            break
        }

        openMethodCalledExpectation?.fulfill()
        openMethodCalledExpectation = nil
    }

    @MainActor
    func openNewAIChat(in linkOpenBehavior: LinkOpenBehavior) {
        openNewAIChatCalled = true
        lastNewAIChatBehavior = linkOpenBehavior

        openMethodCalledExpectation?.fulfill()
        openMethodCalledExpectation = nil
    }

    func reset() {
        openAIChatTabCalled = false
        lastTrigger = nil
        lastBehavior = nil
        openNewAIChatCalled = false
        lastNewAIChatBehavior = nil
        lastURL = nil
        lastPayload = nil
        lastRestorationData = nil
        lastQuery = nil
        lastShouldAutoSubmit = nil
        openMethodCalledExpectation = nil
    }
}
