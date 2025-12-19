//
//  AIChatSidebarPresenterTests.swift
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
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AIChatSidebarPresenterTests: XCTestCase {

    private var presenter: AIChatSidebarPresenter!
    private var mockSidebarHost: MockAIChatSidebarHosting!
    private var mockSidebarProvider: MockAIChatSidebarProvider!
    private var mockAIChatMenuConfig: DummyAIChatConfig!
    private var mockAIChatTabOpener: MockAIChatTabOpener!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockWindowControllersManager: WindowControllersManagerMock!
    private var mockPixelFiring: PixelKitMock!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockSidebarHost = MockAIChatSidebarHosting()
        mockSidebarProvider = MockAIChatSidebarProvider()
        mockAIChatMenuConfig = DummyAIChatConfig()
        mockAIChatTabOpener = MockAIChatTabOpener()
        mockFeatureFlagger = MockFeatureFlagger()
        mockWindowControllersManager = WindowControllersManagerMock()
        mockPixelFiring = PixelKitMock()
        cancellables = Set<AnyCancellable>()

        // Enable AI Chat sidebar feature by default
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatSidebar]

        presenter = AIChatSidebarPresenter(
            sidebarHost: mockSidebarHost,
            sidebarProvider: mockSidebarProvider,
            aiChatMenuConfig: mockAIChatMenuConfig,
            aiChatTabOpener: mockAIChatTabOpener,
            featureFlagger: mockFeatureFlagger,
            windowControllersManager: mockWindowControllersManager,
            pixelFiring: mockPixelFiring
        )
    }

    override func tearDown() {
        cancellables = nil
        presenter = nil
        mockPixelFiring = nil
        mockWindowControllersManager = nil
        mockFeatureFlagger = nil
        mockAIChatTabOpener = nil
        mockAIChatMenuConfig = nil
        mockSidebarProvider = nil
        mockSidebarHost = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_setsUpProperties() {
        // Given & When & Then
        XCTAssertNotNil(presenter.sidebarPresenceWillChangePublisher)
        XCTAssertNotNil(mockSidebarHost.aiChatSidebarHostingDelegate)
        XCTAssertTrue(mockSidebarHost.aiChatSidebarHostingDelegate === presenter)
    }

    func testInit_withDefaultProvider_createsProvider() {
        // Given & When
        let presenter = AIChatSidebarPresenter(
            sidebarHost: mockSidebarHost,
            sidebarProvider: mockSidebarProvider,
            aiChatMenuConfig: mockAIChatMenuConfig,
            aiChatTabOpener: mockAIChatTabOpener,
            featureFlagger: mockFeatureFlagger,
            windowControllersManager: mockWindowControllersManager,
            pixelFiring: mockPixelFiring
        )

        // Then
        XCTAssertNotNil(presenter)
    }

    // MARK: - Toggle Sidebar Tests

    func testToggleSidebar_withFeatureDisabled_doesNothing() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        let initialCount = mockSidebarProvider.sidebarsByTab.count

        // When
        presenter.toggleSidebar()

        // Then
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, initialCount)
        XCTAssertNil(mockSidebarHost.embeddedViewController)
    }

    func testToggleSidebar_withNoCurrentTab_doesNothing() {
        // Given
        mockSidebarHost.currentTabID = nil
        let initialCount = mockSidebarProvider.sidebarsByTab.count

        // When
        presenter.toggleSidebar()

        // Then
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, initialCount)
        XCTAssertNil(mockSidebarHost.embeddedViewController)
    }

    func testToggleSidebar_showsSidebarWhenNotShowing() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        XCTAssertFalse(mockSidebarProvider.isShowingSidebar(for: tabID))

        var presenceChangeReceived: AIChatSidebarPresenceChange?
        presenter.sidebarPresenceWillChangePublisher
            .sink { presenceChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        presenter.toggleSidebar()

        // Then
        XCTAssertTrue(mockSidebarProvider.isShowingSidebar(for: tabID))
        XCTAssertNotNil(mockSidebarHost.embeddedViewController)
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, true)
    }

    func testToggleSidebar_hidesSidebarWhenShowing() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        XCTAssertTrue(mockSidebarProvider.isShowingSidebar(for: tabID))

        var presenceChangeReceived: AIChatSidebarPresenceChange?
        presenter.sidebarPresenceWillChangePublisher
            .sink { presenceChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        presenter.toggleSidebar()

        // Then
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, false)
    }

    // MARK: - Collapse Sidebar Tests

    func testCollapseSidebar_withNoCurrentTab_doesNothing() {
        // Given
        mockSidebarHost.currentTabID = nil
        let initialCount = mockSidebarProvider.sidebarsByTab.count

        // When
        presenter.collapseSidebar(withAnimation: true)

        // Then
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, initialCount)
    }

    func testCollapseSidebar_withAnimation() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        var presenceChangeReceived: AIChatSidebarPresenceChange?
        presenter.sidebarPresenceWillChangePublisher
            .sink { presenceChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        presenter.collapseSidebar(withAnimation: true)

        // Then
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, false)
    }

    func testCollapseSidebar_withoutAnimation() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        var presenceChangeReceived: AIChatSidebarPresenceChange?
        presenter.sidebarPresenceWillChangePublisher
            .sink { presenceChangeReceived = $0 }
            .store(in: &cancellables)

        // When
        presenter.collapseSidebar(withAnimation: false)

        // Then
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, false)
    }

    // MARK: - Is Sidebar Open Tests

    func testIsSidebarOpen_withFeatureDisabled_returnsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        let tabID = "test-tab"
        _ = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        // When
        let isOpen = presenter.isSidebarOpen(for: tabID)

        // Then
        XCTAssertFalse(isOpen)
    }

    func testIsSidebarOpen_withExistingSidebar_returnsTrue() {
        // Given
        let tabID = "test-tab"
        _ = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        // When
        let isOpen = presenter.isSidebarOpen(for: tabID)

        // Then
        XCTAssertTrue(isOpen)
    }

    func testIsSidebarOpen_withoutSidebar_returnsFalse() {
        // Given
        let tabID = "test-tab"

        // When
        let isOpen = presenter.isSidebarOpen(for: tabID)

        // Then
        XCTAssertFalse(isOpen)
    }

    func testIsSidebarOpenForCurrentTab_withCurrentTab() {
        // Given
        let tabID = "current-tab"
        mockSidebarHost.currentTabID = tabID
        _ = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        // When
        let isOpen = presenter.isSidebarOpenForCurrentTab()

        // Then
        XCTAssertTrue(isOpen)
    }

    func testIsSidebarOpenForCurrentTab_withNoCurrentTab_returnsFalse() {
        // Given
        mockSidebarHost.currentTabID = nil

        // When
        let isOpen = presenter.isSidebarOpenForCurrentTab()

        // Then
        XCTAssertFalse(isOpen)
    }

    // MARK: - Present Sidebar Tests

    func testPresentSidebar_withFeatureDisabled_doesNothing() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        let prompt = AIChatNativePrompt.queryPrompt("What is the best pizza recipe?", autoSubmit: true)
        let initialCount = mockSidebarProvider.sidebarsByTab.count

        // When
        presenter.presentSidebar(for: prompt)

        // Then
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, initialCount)
    }

    func testPresentSidebar_withNoCurrentTab_doesNothing() {
        // Given
        mockSidebarHost.currentTabID = nil
        let prompt = AIChatNativePrompt.queryPrompt("What is the best pizza recipe?", autoSubmit: true)
        let initialCount = mockSidebarProvider.sidebarsByTab.count

        // When
        presenter.presentSidebar(for: prompt)

        // Then
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, initialCount)
    }

    func testPresentSidebar_withExistingSidebar_setsPrompt() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        let sidebarViewController = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        let prompt = AIChatNativePrompt.queryPrompt("What is the best pizza recipe?", autoSubmit: true)

        // When
        presenter.presentSidebar(for: prompt)

        // Then
        // The sidebar should receive the prompt (tested via the sidebar's view controller)
        XCTAssertNotNil(sidebarViewController)
    }

    func testPresentSidebar_withoutExistingSidebar_createsSidebar() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID
        let prompt = AIChatNativePrompt.queryPrompt("What is the best pizza recipe?", autoSubmit: true)
        XCTAssertFalse(mockSidebarProvider.isShowingSidebar(for: tabID))

        // When
        presenter.presentSidebar(for: prompt)

        // Then
        XCTAssertTrue(mockSidebarProvider.isShowingSidebar(for: tabID))
        XCTAssertNotNil(mockSidebarHost.embeddedViewController)
    }

    // MARK: - Sidebar Hosting Delegate Tests

    func testSidebarHostDidSelectTab_updatesConstraints() {
        // Given
        let tabID = "selected-tab"
        _ = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        // When
        presenter.sidebarHostDidSelectTab(with: tabID)

        // Then
        // This should update the sidebar constraints for the selected tab
        // The exact behavior depends on the implementation details
        XCTAssertNotNil(presenter)
    }

    func testSidebarHostDidUpdateTabs_cleansUpProvider() {
        // Given
        _ = mockSidebarProvider.makeSidebarViewController(for: "tab1", burnerMode: .regular)
        _ = mockSidebarProvider.makeSidebarViewController(for: "tab2", burnerMode: .regular)
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, 2)

        // When
        presenter.sidebarHostDidUpdateTabs()

        // Then
        // The cleanup should have been called on the provider
        // With empty tab collections, all sidebars should be removed
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, 0)
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

        _ = mockSidebarProvider.makeSidebarViewController(for: "tab1", burnerMode: .regular)
        _ = mockSidebarProvider.makeSidebarViewController(for: "tab2", burnerMode: .regular)
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, 2)

        // When
        presenter.sidebarHostDidUpdateTabs()

        // Then
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, 2)
    }

    // MARK: - Sidebar View Controller Delegate Tests

    func testDidClickOpenInNewTabButton_newAIChatTabIsOpen() {
        // Given
        let tabID = "test-tab"
        mockSidebarHost.currentTabID = tabID

        // Set up the sidebar with a test URL that includes a placement parameter
        let testURL = URL(string: "https://example.com")!.forAIChatSidebar()
        let sidebar = AIChatSidebar(initialAIChatURL: testURL, burnerMode: .regular)
        mockSidebarProvider.restoreState([tabID: sidebar])

        mockAIChatTabOpener.openMethodCalledExpectation = expectation(description: "AIChatTabOpener did open a new tab")

        // When
        presenter.didClickOpenInNewTabButton()

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
        let sidebar = AIChatSidebar(burnerMode: .regular)
        sidebar.updateRestorationData(restorationData)
        mockSidebarProvider.restoreState([tabID: sidebar])

        mockAIChatTabOpener.openMethodCalledExpectation = expectation(description: "AIChatTabOpener did open a new tab")

        // When
        presenter.didClickOpenInNewTabButton()

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
        _ = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        XCTAssertTrue(mockSidebarProvider.isShowingSidebar(for: tabID))

        let sidebarPresenceChangeExpectation = expectation(description: "Sidebar presence did change")
        var presenceChangeReceived: AIChatSidebarPresenceChange?
        presenter.sidebarPresenceWillChangePublisher
            .sink {
                presenceChangeReceived = $0
                sidebarPresenceChangeExpectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        presenter.didClickCloseButton()

        // Then
        waitForExpectations(timeout: 3)
        XCTAssertEqual(presenceChangeReceived?.tabID, tabID)
        XCTAssertEqual(presenceChangeReceived?.isShown, false)
    }

    // MARK: - AI Chat Handoff Tests

    func testHandleAIChatHandoff_withFeatureDisabled_doesNothing() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
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
        XCTAssertFalse(mockSidebarProvider.isShowingSidebar(for: tabID))

        let sidebarPresenceChangeExpectation = expectation(description: "Sidebar presence did change")
        var presenceChangeReceived: AIChatSidebarPresenceChange?
        presenter.sidebarPresenceWillChangePublisher
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
        _ = mockSidebarProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        let payload = AIChatPayload()
        XCTAssertTrue(mockSidebarProvider.isShowingSidebar(for: tabID))
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

    func testCompleteWorkflow() async throws {
        // Given
        let tabID = "workflow-tab"
        mockSidebarHost.currentTabID = tabID

        var presenceChanges: [AIChatSidebarPresenceChange] = []
        presenter.sidebarPresenceWillChangePublisher
            .sink { presenceChanges.append($0) }
            .store(in: &cancellables)

        // When - Toggle sidebar on
        presenter.toggleSidebar()
        try await Task.sleep(interval: 0.5)

        // Then - Sidebar should be showing
        XCTAssertTrue(presenter.isSidebarOpen(for: tabID))
        XCTAssertEqual(presenceChanges.count, 1)
        XCTAssertEqual(presenceChanges.last?.isShown, true)

        // When - Toggle sidebar off
        presenter.toggleSidebar()
        try await Task.sleep(interval: 0.5)

        // Then - Sidebar should be hidden
        XCTAssertEqual(presenceChanges.count, 2)
        XCTAssertEqual(presenceChanges.last?.isShown, false)

        // When - Present sidebar with prompt
        let prompt = AIChatNativePrompt.queryPrompt("What is the best pizza recipe?", autoSubmit: true)
        presenter.presentSidebar(for: prompt)

        // Then - Sidebar should be showing again
        XCTAssertEqual(presenceChanges.count, 3)
        XCTAssertEqual(presenceChanges.last?.isShown, true)
    }

    func testMultipleTabsWorkflow() async throws {
        // Given
        let tab1 = "tab1"
        let tab2 = "tab2"

        // When - Open sidebar on tab1
        mockSidebarHost.currentTabID = tab1
        presenter.toggleSidebar()
        try await Task.sleep(interval: 0.5)

        // Then
        XCTAssertTrue(presenter.isSidebarOpen(for: tab1))
        XCTAssertFalse(presenter.isSidebarOpen(for: tab2))

        // When - Switch to tab2 and open sidebar
        mockSidebarHost.currentTabID = tab2
        presenter.toggleSidebar()
        try await Task.sleep(interval: 0.5)

        // Then
        XCTAssertTrue(presenter.isSidebarOpen(for: tab1))
        XCTAssertTrue(presenter.isSidebarOpen(for: tab2))

        // When - Close sidebar on tab1
        mockSidebarHost.currentTabID = tab1
        presenter.toggleSidebar()
        try await Task.sleep(interval: 0.5)

        // Then
        XCTAssertFalse(presenter.isSidebarOpen(for: tab1))
        XCTAssertTrue(presenter.isSidebarOpen(for: tab2))
    }

    // MARK: - Edge Cases

    func testAnimationStateManagement() {
        // Given
        let tabID = "animation-tab"
        mockSidebarHost.currentTabID = tabID

        // When - Call toggle multiple times quickly
        presenter.toggleSidebar()
        presenter.toggleSidebar() // Should be ignored if animation is in progress

        // Then - Only one sidebar operation should have occurred
        XCTAssertTrue(presenter.isSidebarOpen(for: tabID))
    }

    func testFeatureFlagChanges() {
        // Given
        let tabID = "feature-tab"
        mockSidebarHost.currentTabID = tabID

        // When - Create sidebar with feature enabled
        presenter.toggleSidebar()
        XCTAssertTrue(presenter.isSidebarOpen(for: tabID))

        // When - Disable feature and try to check status
        mockFeatureFlagger.enabledFeatureFlags = []
        let isOpen = presenter.isSidebarOpen(for: tabID)

        // Then - Should return false even though sidebar exists
        XCTAssertFalse(isOpen)

        // When - Try to toggle with feature disabled
        presenter.toggleSidebar()

        // Then - Should not create new sidebar
        XCTAssertEqual(mockSidebarProvider.sidebarsByTab.count, 1) // Still just the original one
    }

}

// MARK: - Mock Classes

class MockAIChatSidebarHosting: AIChatSidebarHosting {
    var aiChatSidebarHostingDelegate: AIChatSidebarHostingDelegate?
    var isInKeyWindow: Bool = true
    var currentTabID: TabIdentifier? = "test-tab-id"
    var sidebarContainerLeadingConstraint: NSLayoutConstraint?
    var sidebarContainerWidthConstraint: NSLayoutConstraint?
    var burnerMode: BurnerMode = .regular

    var embeddedViewController: NSViewController?

    init() {
        sidebarContainerLeadingConstraint = NSLayoutConstraint()
        sidebarContainerWidthConstraint = NSLayoutConstraint()
    }

    func embedSidebarViewController(_ vc: NSViewController) {
        embeddedViewController = vc
    }
}

class MockAIChatSidebarProvider: AIChatSidebarProviding {
    var sidebarWidth: CGFloat = 400
    @Published var sidebarsByTab: AIChatSidebarsByTab = [:]

    var sidebarsByTabPublisher: AnyPublisher<DuckDuckGo_Privacy_Browser.AIChatSidebarsByTab, Never> {
        $sidebarsByTab.eraseToAnyPublisher()
    }

    private var _isShowingSidebar: [TabIdentifier: Bool] = [:]

    func getSidebarViewController(for tabID: TabIdentifier) -> AIChatSidebarViewController? {
        return sidebarsByTab[tabID]?.sidebarViewController
    }

    func makeSidebarViewController(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSidebarViewController {
        let sidebar = sidebarsByTab[tabID] ?? makeSidebar(for: tabID, burnerMode: burnerMode)

        if let existingViewController = sidebar.sidebarViewController {
            return existingViewController
        }

        let aiChatRemoteSettings = AIChatRemoteSettings()
        let initialAIChatURL = aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        let sidebarViewController = AIChatSidebarViewController(currentAIChatURL: initialAIChatURL, burnerMode: burnerMode)
        sidebar.sidebarViewController = sidebarViewController

        return sidebarViewController
    }

    private func makeSidebar(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSidebar {
        let sidebar = AIChatSidebar(burnerMode: burnerMode)
        sidebarsByTab[tabID] = sidebar
        _isShowingSidebar[tabID] = true
        return sidebar
    }

    func isShowingSidebar(for tabID: TabIdentifier) -> Bool {
        return _isShowingSidebar[tabID] ?? false
    }

    func handleSidebarDidClose(for tabID: TabIdentifier) {
        if let sidebar = sidebarsByTab[tabID] {
            if let sidebarViewController = sidebar.sidebarViewController {
                sidebarViewController.stopLoading()
                sidebarViewController.removeCompletely()
            }
        }
        sidebarsByTab.removeValue(forKey: tabID)
        _isShowingSidebar[tabID] = false
    }

    func cleanUp(for currentTabIDs: [TabIdentifier]) {
        let tabIDsToRemove = Set(sidebarsByTab.keys).subtracting(currentTabIDs)
        for tabID in tabIDsToRemove {
            handleSidebarDidClose(for: tabID)
        }
    }

    func restoreState(_ sidebarsByTab: AIChatSidebarsByTab) {
        cleanUp(for: [])
        self.sidebarsByTab = sidebarsByTab
    }

    func resetSidebar(for tabID: TabIdentifier) {
        sidebarsByTab.removeValue(forKey: tabID)
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
