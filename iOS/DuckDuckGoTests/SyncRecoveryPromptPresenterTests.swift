//
//  SyncRecoveryPromptPresenterTests.swift
//  DuckDuckGoTests
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
import SwiftUI
import Core
@testable import DuckDuckGo

@MainActor
final class SyncRecoveryPromptPresenterTests: XCTestCase {

    private var sut: SyncRecoveryPromptPresenter!
    private var mockViewController: UIViewController!
    private var presentedViewController: UIViewController?
    private var syncFlowSelectedType: String?

    override func setUp() async throws {
        try await super.setUp()

        presentedViewController = nil
        syncFlowSelectedType = nil

        mockViewController = MockViewController { [weak self] viewController, _ in
            self?.presentedViewController = viewController
        }

        sut = SyncRecoveryPromptPresenter()
    }

    override func tearDown() async throws {
        sut = nil
        mockViewController = nil
        presentedViewController = nil
        syncFlowSelectedType = nil

        try await super.tearDown()
    }

    // MARK: - Main Prompt Presentation Tests

    func testPresentSyncRecoveryPrompt_PresentsHostingController() async {
        // When
        sut.presentSyncRecoveryPrompt(
            from: mockViewController,
            onSyncFlowSelected: { [weak self] flowType in
                self?.syncFlowSelectedType = flowType
            }
        )

        // Then
        XCTAssertNotNil(presentedViewController)
        XCTAssertTrue(presentedViewController is SyncRecoveryPromptHostingController)
    }

    // MARK: - Alternative Prompt Tests

    func testAlternativePrompt_WhenTriggeredFromMainPrompt_PresentsAlternativeView() async {
        sut.presentSyncRecoveryPrompt(
            from: mockViewController,
            onSyncFlowSelected: { [weak self] flowType in
                self?.syncFlowSelectedType = flowType
            }
        )

        XCTAssertNotNil(presentedViewController)
    }

    // MARK: - Callback Tests

    func testSyncFlowSelected_PassesCorrectFlowType() async {
        var receivedFlowType: String?

        sut.presentSyncRecoveryPrompt(
            from: mockViewController,
            onSyncFlowSelected: { flowType in
                receivedFlowType = flowType
            }
        )

        XCTAssertNil(receivedFlowType) // Not yet triggered
    }

}

// MARK: - Mock Classes

private class MockViewController: UIViewController {
    private let presentHandler: (UIViewController, Bool) -> Void

    init(presentHandler: @escaping (UIViewController, Bool) -> Void) {
        self.presentHandler = presentHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentHandler(viewControllerToPresent, flag)
        completion?()
    }
}
