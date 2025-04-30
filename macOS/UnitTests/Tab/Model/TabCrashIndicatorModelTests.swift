//
//  TabCrashIndicatorModelTests.swift
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

import Combine
import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class TabCrashIndicatorModelTests: XCTestCase {

    var model: TabCrashIndicatorModel!
    var crashPublisher: PassthroughSubject<TabCrashType, Never>!
    var isShowingIndicatorEvents: [Bool] = []
    var cancellables: Set<AnyCancellable> = []

    var firePixelCallCount: Int = 0
    var firePixelHandler: (PixelKitEvent) -> Void = { _ in }

    override func setUp() async throws {
        crashPublisher = PassthroughSubject()
        isShowingIndicatorEvents = []
        cancellables = []

        model = TabCrashIndicatorModel(
            maxPresentationDuration: .milliseconds(200),
            firePixel: { [unowned self] event in
                firePixelCallCount += 1
                firePixelHandler(event)
            }
        )
        model.setUp(with: crashPublisher.eraseToAnyPublisher())

        model.$isShowingIndicator.dropFirst()
            .sink { [weak self] isShowingIndicator in
                self?.isShowingIndicatorEvents.append(isShowingIndicator)
            }
            .store(in: &cancellables)
    }

    func testInitialValues() {
        XCTAssertFalse(model.isShowingIndicator)
        XCTAssertFalse(model.isShowingPopover)
    }

    func testThatSingleCrashShowsIndicator() {
        crashPublisher.send(.single)
        XCTAssertEqual(isShowingIndicatorEvents, [true])
    }

    func testThatCrashLoopHidesIndicator() {
        crashPublisher.send(.single)
        crashPublisher.send(.crashLoop)
        XCTAssertEqual(isShowingIndicatorEvents, [true, false])
    }

    func testWhenPopoverIsShownThenCrashLoopHidesIndicator() {
        crashPublisher.send(.single)
        model.isShowingPopover = true
        crashPublisher.send(.crashLoop)

        XCTAssertEqual(isShowingIndicatorEvents, [true, false])
    }

    func testThatMultipleCrashesOnlyEmitOneShowEvent() {
        crashPublisher.send(.single)
        crashPublisher.send(.single)
        crashPublisher.send(.single)
        crashPublisher.send(.single)
        crashPublisher.send(.crashLoop)
        crashPublisher.send(.crashLoop)
        crashPublisher.send(.crashLoop)
        crashPublisher.send(.single)
        crashPublisher.send(.single)
        crashPublisher.send(.single)
        crashPublisher.send(.single)
        XCTAssertEqual(isShowingIndicatorEvents, [true, false, true])
    }

    func testThatHidingPopoverHidesIndicator() {
        crashPublisher.send(.single)
        model.isShowingPopover = true
        model.isShowingPopover = false
        XCTAssertEqual(isShowingIndicatorEvents, [true, false])
    }

    func testThatIndicatorIsHiddenAfterTimeout() async throws {
        crashPublisher.send(.single)

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(isShowingIndicatorEvents, [true, false])
    }

    func testWhenPopoverIsShownThenIndicatorIsNotHiddenAfterTimeout() async throws {
        crashPublisher.send(.single)
        model.isShowingPopover = true

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(isShowingIndicatorEvents, [true])
    }

    func testWhenPopoverIsShownThenPixelIsFired() {
        let expectation = expectation(description: "pixel fired")
        expectation.expectedFulfillmentCount = 3

        firePixelHandler = { event in
            if case GeneralPixel.webKitTerminationIndicatorClicked = event {
                expectation.fulfill()
            }
        }

        model.isShowingPopover = true
        model.isShowingPopover = true
        model.isShowingPopover = true
        XCTAssertEqual(firePixelCallCount, 1)

        model.isShowingPopover = false
        model.isShowingPopover = true
        XCTAssertEqual(firePixelCallCount, 2)

        model.isShowingPopover = false
        model.isShowingPopover = false
        model.isShowingPopover = false
        model.isShowingPopover = true
        model.isShowingPopover = true
        XCTAssertEqual(firePixelCallCount, 3)

        waitForExpectations(timeout: 0.1)
    }
}
