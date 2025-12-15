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
@testable import DuckDuckGo

final class AIChatContextualSheetCoordinatorTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDelegate: AIChatContextualSheetCoordinatorDelegate {
        var didRequestToLoadURLs: [URL] = []
        var didRequestExpandCount = 0

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestToLoad url: URL) {
            didRequestToLoadURLs.append(url)
        }

        func aiChatContextualSheetCoordinatorDidRequestExpand(_ coordinator: AIChatContextualSheetCoordinator) {
            didRequestExpandCount += 1
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

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        sut = AIChatContextualSheetCoordinator(voiceSearchHelper: MockVoiceSearchHelper())
        mockDelegate = MockDelegate()
        mockPresentingVC = MockPresentingViewController()
        sut.delegate = mockDelegate
    }

    override func tearDown() {
        sut = nil
        mockDelegate = nil
        mockPresentingVC = nil
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

    func testDelegateReceivesExpandRequest() {
        // Given
        sut.presentSheet(from: mockPresentingVC)

        // When
        sut.aiChatContextualSheetViewControllerDidRequestExpand(sut.sheetViewController!)

        // Then
        XCTAssertEqual(mockDelegate.didRequestExpandCount, 1)
    }

    func testExpandRequestClearsActiveChat() {
        // Given
        sut.presentSheet(from: mockPresentingVC)
        XCTAssertNotNil(sut.sheetViewController)

        // When
        sut.aiChatContextualSheetViewControllerDidRequestExpand(sut.sheetViewController!)

        // Then
        XCTAssertNil(sut.sheetViewController)
    }
}
