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
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Combine
@testable import DuckDuckGo

final class AIChatContextualSheetCoordinatorTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDelegate: AIChatContextualSheetCoordinatorDelegate {
        var didRequestToLoadURLs: [URL] = []
        var didRequestExpandURLs: [URL] = []
        var openSettingsCallCount = 0
        var openSyncSettingsCallCount = 0
        var attachPageCallCount = 0

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

        func aiChatContextualSheetCoordinatorDidRequestAttachPage(_ coordinator: AIChatContextualSheetCoordinator) {
            attachPageCallCount += 1
        }

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didUpdateContextualChatURL url: URL?) {
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
    private var contentBlockingSubject: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockSettings = MockAIChatSettingsProvider()
        contentBlockingSubject = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
        sut = AIChatContextualSheetCoordinator(
            voiceSearchHelper: MockVoiceSearchHelper(),
            aiChatSettings: mockSettings,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: contentBlockingSubject.eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: MockFeatureFlagger()
        )
        mockDelegate = MockDelegate()
        mockPresentingVC = MockPresentingViewController()
        sut.delegate = mockDelegate
    }

    override func tearDown() {
        sut = nil
        mockDelegate = nil
        mockPresentingVC = nil
        mockSettings = nil
        contentBlockingSubject = nil
        super.tearDown()
    }

    // MARK: - presentSheet Tests

    func testPresentSheetCreatesNewSheetWhenNoneExists() {
        // Given
        XCTAssertNil(sut.sheetViewController)

        // When
        sut.presentSheet(from: mockPresentingVC)

        // Then
        XCTAssertNotNil(sut.sheetViewController)
        XCTAssertTrue(mockPresentingVC.presentedVC is AIChatContextualSheetViewController)
        XCTAssertEqual(mockPresentingVC.presentAnimated, true)
    }

    func testPresentSheetReusesExistingSheet() {
        // Given
        sut.presentSheet(from: mockPresentingVC)
        let firstSheet = sut.sheetViewController

        // When
        sut.presentSheet(from: mockPresentingVC)
        let secondSheet = sut.sheetViewController

        // Then
        XCTAssertTrue(firstSheet === secondSheet)
    }

    func testPresentSheetSetsItselfAsSheetDelegate() {
        // When
        sut.presentSheet(from: mockPresentingVC)

        // Then
        XCTAssertNotNil(sut.sheetViewController?.delegate)
    }

    // MARK: - clearActiveChat Tests

    func testClearActiveChatRemovesSheet() {
        // Given
        sut.presentSheet(from: mockPresentingVC)
        XCTAssertNotNil(sut.sheetViewController)

        // When
        sut.clearActiveChat()

        // Then
        XCTAssertNil(sut.sheetViewController)
    }

    func testClearActiveChatThenPresentCreatesNewSheet() {
        // Given
        sut.presentSheet(from: mockPresentingVC)
        let firstSheet = sut.sheetViewController
        sut.clearActiveChat()

        // When
        sut.presentSheet(from: mockPresentingVC)
        let secondSheet = sut.sheetViewController

        // Then
        XCTAssertFalse(firstSheet === secondSheet)
    }

    // MARK: - Delegate Forwarding Tests

    func testDelegateReceivesLoadURLRequest() {
        // Given
        sut.presentSheet(from: mockPresentingVC)
        let testURL = URL(string: "https://example.com")!

        // When
        sut.aiChatContextualSheetViewController(sut.sheetViewController!, didRequestToLoad: testURL)

        // Then
        XCTAssertEqual(mockDelegate.didRequestToLoadURLs, [testURL])
    }

    func testDelegateReceivesExpandRequestWithURL() {
        // Given
        sut.presentSheet(from: mockPresentingVC)
        let expandURL = URL(string: "https://duck.ai/chat/abc123")!

        // When
        sut.aiChatContextualSheetViewController(sut.sheetViewController!, didRequestExpandWithURL: expandURL)

        // Then
        XCTAssertEqual(mockDelegate.didRequestExpandURLs, [expandURL])
    }

    func testExpandRequestClearsActiveChat() {
        // Given
        sut.presentSheet(from: mockPresentingVC)
        XCTAssertNotNil(sut.sheetViewController)
        let expandURL = URL(string: "https://duck.ai/chat/abc123")!

        // When
        sut.aiChatContextualSheetViewController(sut.sheetViewController!, didRequestExpandWithURL: expandURL)

        // Then
        XCTAssertNil(sut.sheetViewController)
    }
}
