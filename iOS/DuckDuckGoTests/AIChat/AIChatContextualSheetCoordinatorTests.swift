//
//  AIChatContextualSheetCoordinatorTests.swift
//  DuckDuckGo
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

import XCTest
import AIChat
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Combine
import WebKit
@testable import DuckDuckGo

final class AIChatContextualSheetCoordinatorTests: XCTestCase {

    // MARK: - Mocks

    private final class MockPageContextHandler: AIChatPageContextHandling {
        var latestContext: AIChatPageContextData?
        var latestFavicon: UIImage?
        var hasContext: Bool { latestContext != nil }
        var triggerContextCollectionCallCount = 0
        var clearCallCount = 0

        private let contextSubject = CurrentValueSubject<AIChatPageContextData?, Never>(nil)
        var contextPublisher: AnyPublisher<AIChatPageContextData?, Never> {
            contextSubject.eraseToAnyPublisher()
        }

        func triggerContextCollection() async {
            triggerContextCollectionCallCount += 1
        }

        func clear() {
            clearCallCount += 1
            latestContext = nil
            latestFavicon = nil
            contextSubject.send(nil)
        }

        func setContext(_ context: AIChatPageContextData?) {
            latestContext = context
            contextSubject.send(context)
        }
    }

    private final class MockDelegate: AIChatContextualSheetCoordinatorDelegate {
        var didRequestToLoadURLs: [URL] = []
        var didRequestExpandURLs: [URL] = []
        var openSettingsCallCount = 0
        var openSyncSettingsCallCount = 0

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestToLoad url: URL) {
            didRequestToLoadURLs.append(url)
        }

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestExpandWithURL url: URL) {
            didRequestExpandURLs.append(url)
        }

        func aiChatContextualSheetCoordinatorDidRequestOpenSettings(_ coordinator: AIChatContextualSheetCoordinator) {
            openSettingsCallCount += 1
        }

        func aiChatContextualSheetCoordinatorDidRequestOpenSyncSettings(_ coordinator: AIChatContextualSheetCoordinator) {
            openSyncSettingsCallCount += 1
        }

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didUpdateContextualChatURL url: URL?) {
        }
        
        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestOpenDownloadWithFileName fileName: String) {
        }
    }

    private final class MockPresentingViewController: UIViewController {
        var presentedVC: UIViewController?
        var presentAnimated: Bool?

        override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
            presentedVC = viewControllerToPresent
            presentAnimated = flag
            completion?()
        }
    }

    // MARK: - Properties

    private var sut: AIChatContextualSheetCoordinator!
    private var mockDelegate: MockDelegate!
    private var mockPresentingVC: MockPresentingViewController!
    private var mockSettings: MockAIChatSettingsProvider!
    private var mockPageContextHandler: MockPageContextHandler!
    private var contentBlockingSubject: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>!

    // MARK: - Setup

    @MainActor
    override func setUp() {
        super.setUp()
        mockSettings = MockAIChatSettingsProvider()
        mockPageContextHandler = MockPageContextHandler()
        contentBlockingSubject = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
        sut = AIChatContextualSheetCoordinator(
            voiceSearchHelper: MockVoiceSearchHelper(),
            aiChatSettings: mockSettings,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: contentBlockingSubject.eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: MockFeatureFlagger(),
            pageContextHandler: mockPageContextHandler
        )
        mockDelegate = MockDelegate()
        mockPresentingVC = MockPresentingViewController()
        sut.delegate = mockDelegate
    }

    @MainActor
    override func tearDown() {
        sut = nil
        mockDelegate = nil
        mockPresentingVC = nil
        mockSettings = nil
        mockPageContextHandler = nil
        contentBlockingSubject = nil
        super.tearDown()
    }

    // MARK: - presentSheet Tests

    @MainActor
    func testPresentSheetCreatesNewSheetWhenNoneExists() async {
        // Given
        XCTAssertNil(sut.sheetViewController)

        // When
        await sut.presentSheet(from: mockPresentingVC)

        // Then
        XCTAssertNotNil(sut.sheetViewController)
        XCTAssertTrue(mockPresentingVC.presentedVC is AIChatContextualSheetViewController)
        XCTAssertEqual(mockPresentingVC.presentAnimated, true)
    }

    @MainActor
    func testPresentSheetReusesExistingSheet() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        let firstSheet = sut.sheetViewController

        // When
        await sut.presentSheet(from: mockPresentingVC)
        let secondSheet = sut.sheetViewController

        // Then
        XCTAssertTrue(firstSheet === secondSheet)
    }

    @MainActor
    func testPresentSheetSetsItselfAsSheetDelegate() async {
        // When
        await sut.presentSheet(from: mockPresentingVC)

        // Then
        XCTAssertNotNil(sut.sheetViewController?.delegate)
    }

    // MARK: - clearActiveChat Tests

    @MainActor
    func testClearActiveChatRemovesSheet() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        XCTAssertNotNil(sut.sheetViewController)

        // When
        sut.clearActiveChat()

        // Then
        XCTAssertNil(sut.sheetViewController)
    }

    @MainActor
    func testClearActiveChatThenPresentCreatesNewSheet() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        let firstSheet = sut.sheetViewController
        sut.clearActiveChat()

        // When
        await sut.presentSheet(from: mockPresentingVC)
        let secondSheet = sut.sheetViewController

        // Then
        XCTAssertFalse(firstSheet === secondSheet)
    }

    // MARK: - Delegate Forwarding Tests

    @MainActor
    func testDelegateReceivesLoadURLRequest() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        let testURL = URL(string: "https://example.com")!

        // When
        sut.aiChatContextualSheetViewController(sut.sheetViewController!, didRequestToLoad: testURL)

        // Then
        XCTAssertEqual(mockDelegate.didRequestToLoadURLs, [testURL])
    }

    @MainActor
    func testDelegateReceivesExpandRequestWithURL() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        let expandURL = URL(string: "https://duck.ai/chat/abc123")!

        // When
        sut.aiChatContextualSheetViewController(sut.sheetViewController!, didRequestExpandWithURL: expandURL)

        // Then
        XCTAssertEqual(mockDelegate.didRequestExpandURLs, [expandURL])
    }

    @MainActor
    func testExpandRequestClearsActiveChat() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        XCTAssertNotNil(sut.sheetViewController)
        let expandURL = URL(string: "https://duck.ai/chat/abc123")!

        // When
        sut.aiChatContextualSheetViewController(sut.sheetViewController!, didRequestExpandWithURL: expandURL)

        // Then
        XCTAssertNil(sut.sheetViewController)
    }

    // MARK: - hasActiveChat Tests

    @MainActor
    func testHasActiveChatIsFalseInitially() {
        XCTAssertFalse(sut.hasActiveChat)
    }

    @MainActor
    func testHasActiveChatIsFalseAfterPresentingSheet() async {
        // Presenting sheet alone doesn't create webViewController
        await sut.presentSheet(from: mockPresentingVC)
        XCTAssertFalse(sut.hasActiveChat)
    }

    // MARK: - Snapshot Tests

    @MainActor
    func testCurrentSnapshotIsNilWhenNoContext() {
        XCTAssertNil(sut.currentSnapshot)
    }

    @MainActor
    func testCurrentSnapshotReturnsContextWhenAvailable() {
        mockPageContextHandler.setContext(makeTestContext())

        XCTAssertNotNil(sut.currentSnapshot)
        XCTAssertEqual(sut.currentSnapshot?.context.title, "Test Page")
    }

    // MARK: - Page Context Handling Tests

    @MainActor
    func testClearActiveChatClearsPageContext() async {
        await sut.presentSheet(from: mockPresentingVC)

        sut.clearActiveChat()

        XCTAssertEqual(mockPageContextHandler.clearCallCount, 1)
    }

    @MainActor
    func testClearPageContextUpdatesViewModel() async {
        mockPageContextHandler.setContext(makeTestContext())
        await sut.presentSheet(from: mockPresentingVC)

        sut.clearPageContext()

        XCTAssertEqual(mockPageContextHandler.clearCallCount, 1)
    }

    @MainActor
    func testNotifyPageChangedTriggersCollectionWhenAutoAttachEnabled() async {
        mockSettings.isAutomaticContextAttachmentEnabled = true
        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        await sut.notifyPageChanged()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    @MainActor
    func testNotifyPageChangedDoesNotTriggerCollectionWhenAutoAttachDisabled() async {
        mockSettings.isAutomaticContextAttachmentEnabled = false
        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        await sut.notifyPageChanged()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)
    }

    @MainActor
    func testNotifyPageChangedDoesNotTriggerCollectionWithoutActiveSheet() async {
        mockSettings.isAutomaticContextAttachmentEnabled = true

        await sut.notifyPageChanged()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)
    }

    // MARK: - Helpers

    private func makeTestContext(url: String = "https://example.com") -> AIChatPageContextData {
        AIChatPageContextData(
            title: "Test Page",
            favicon: [],
            url: url,
            content: "Test content",
            truncated: false,
            fullContentLength: 12
        )
    }
}
