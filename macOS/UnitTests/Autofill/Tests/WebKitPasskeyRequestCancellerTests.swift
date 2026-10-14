//
//  WebKitPasskeyRequestCancellerTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AuthenticationServices
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class WebKitPasskeyRequestCancellerTests: XCTestCase {

    private final class WebKitDelegate: NSObject, ASAuthorizationControllerDelegate {}
    private final class OtherDelegate: NSObject, ASAuthorizationControllerDelegate {}

    private final class FakeController: PasskeyAuthorizationController {
        var delegate: ASAuthorizationControllerDelegate?
        private(set) var cancelCount = 0
        private(set) var performCount = 0
        private(set) var completedAsCancelledCount = 0

        init(delegate: ASAuthorizationControllerDelegate) {
            self.delegate = delegate
        }

        func cancel() {
            cancelCount += 1
        }

        func completeAsCancelled() {
            completedAsCancelledCount += 1
        }

        func perform() {
            performCount += 1
        }
    }

    private let delay: TimeInterval = 0.05
    private var isEnabled = true
    private var canceller: WebKitPasskeyRequestCanceller!

    override func setUp() {
        super.setUp()
        isEnabled = true
        canceller = WebKitPasskeyRequestCanceller(webKitDelegateClass: WebKitDelegate.self,
                                                  isEnabled: { [unowned self] in isEnabled },
                                                  delayAfterCancellingOpenRequest: delay)
    }

    override func tearDown() {
        canceller = nil
        super.tearDown()
    }

    private func webKitController() -> FakeController {
        FakeController(delegate: WebKitDelegate())
    }

    private func start(_ controller: FakeController) {
        canceller.willPerform(controller) { controller.perform() }
    }

    /// WebKit releases a request's delegate when it replaces the request.
    private func replaceInWebKit(_ controller: FakeController) {
        controller.delegate = nil
    }

    private func waitPastDelay() {
        let expectation = expectation(description: "delay passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay * 3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
    }

    func testWhenFirstWebKitRequestStarts_ThenItStartsAndNothingIsCancelled() {
        let first = webKitController()

        start(first)

        XCTAssertEqual(first.performCount, 1)
        XCTAssertEqual(first.cancelCount, 0)
    }

    func testWhenWebKitReplacedThePreviousRequest_ThenItIsCancelledAndTheNewOneStartsRightAway() {
        let previous = webKitController()
        let next = webKitController()

        start(previous)
        replaceInWebKit(previous)
        start(next)

        XCTAssertEqual(previous.cancelCount, 1)
        XCTAssertEqual(next.performCount, 1)
        XCTAssertEqual(next.cancelCount, 0)
    }

    func testWhenPreviousRequestIsStillOpenInAnotherPage_ThenItIsCancelledAndTheNewOneStartsAfterTheDelay() {
        let previous = webKitController()
        let next = webKitController()

        start(previous)
        start(next)

        XCTAssertEqual(previous.cancelCount, 1)
        XCTAssertNotNil(previous.delegate)
        XCTAssertEqual(next.performCount, 0)

        waitPastDelay()

        XCTAssertEqual(next.performCount, 1)
    }

    func testWhenSameRequestStartsAgain_ThenItStartsWithoutBeingCancelled() {
        let controller = webKitController()

        start(controller)
        start(controller)

        XCTAssertEqual(controller.cancelCount, 0)
        XCTAssertEqual(controller.performCount, 2)
    }

    func testWhenRequestsKeepReplacingEachOther_ThenEachPreviousIsCancelledOnce() {
        let first = webKitController()
        let second = webKitController()
        let third = webKitController()

        start(first)
        replaceInWebKit(first)
        start(second)
        replaceInWebKit(second)
        start(third)

        XCTAssertEqual(first.cancelCount, 1)
        XCTAssertEqual(second.cancelCount, 1)
        XCTAssertEqual(third.cancelCount, 0)
        XCTAssertEqual(third.performCount, 1)
    }

    func testWhenNonWebKitRequestStarts_ThenItStartsAndIsIgnored() {
        let webKitRequest = webKitController()
        let otherRequest = FakeController(delegate: OtherDelegate())
        let nextWebKitRequest = webKitController()

        start(webKitRequest)
        start(otherRequest)

        XCTAssertEqual(otherRequest.performCount, 1)
        XCTAssertEqual(webKitRequest.cancelCount, 0)

        replaceInWebKit(webKitRequest)
        start(nextWebKitRequest)

        XCTAssertEqual(webKitRequest.cancelCount, 1)
        XCTAssertEqual(otherRequest.cancelCount, 0)
    }

    func testWhenDisabled_ThenRequestsStartWithoutCancellingAndTrackingIsCleared() {
        let tracked = webKitController()
        let whileDisabled = webKitController()
        let afterReenabling = webKitController()

        start(tracked)
        isEnabled = false
        start(whileDisabled)

        XCTAssertEqual(whileDisabled.performCount, 1)
        XCTAssertEqual(tracked.cancelCount, 0)

        isEnabled = true
        start(afterReenabling)

        XCTAssertEqual(afterReenabling.performCount, 1)
        XCTAssertEqual(tracked.cancelCount, 0)
        XCTAssertEqual(whileDisabled.cancelCount, 0)
    }

    func testWhenWebKitCancelsAWaitingRequest_ThenItCompletesAsCancelledWithoutStarting() {
        let previous = webKitController()
        let waiting = webKitController()

        start(previous)
        start(waiting)

        XCTAssertFalse(canceller.willCancel(waiting))
        XCTAssertEqual(waiting.completedAsCancelledCount, 1)

        waitPastDelay()

        XCTAssertEqual(waiting.performCount, 0)
    }

    func testWhenANewerRequestReplacesAWaitingOne_ThenTheWaitingOneCompletesAsCancelledAndTheNewerOneWaits() {
        let previous = webKitController()
        let waiting = webKitController()
        let newer = webKitController()

        start(previous)
        start(waiting)
        start(newer)

        XCTAssertEqual(waiting.completedAsCancelledCount, 1)
        XCTAssertEqual(waiting.cancelCount, 0)
        XCTAssertEqual(newer.performCount, 0)

        waitPastDelay()

        XCTAssertEqual(waiting.performCount, 0)
        XCTAssertEqual(newer.performCount, 1)
    }

    func testWhenRequestIsNotWaiting_ThenWebKitsCancelGoesThrough() {
        let controller = webKitController()

        start(controller)

        XCTAssertTrue(canceller.willCancel(controller))
    }

    func testWhenWebKitDelegateClassIsMissing_ThenInstallFiresPixel() throws {
        guard #available(macOS 13.0, *) else { throw XCTSkip("Requires macOS 13") }
        let pixelFiring = PixelKitMock()

        WebKitPasskeyRequestCanceller.install(isEnabled: { true }, webKitDelegateClass: nil, pixelFiring: pixelFiring)

        XCTAssertEqual(pixelFiring.actualFireCalls, [
            ExpectedFireCall(pixel: PasskeyRequestCancellationPixel.installFailed(.webKitDelegateClass), frequency: .dailyAndCount)
        ])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters, ["reason": "webkit_delegate_class"])
    }
}
