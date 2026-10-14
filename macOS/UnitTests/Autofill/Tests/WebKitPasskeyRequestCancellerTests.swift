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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class WebKitPasskeyRequestCancellerTests: XCTestCase {

    private final class WebKitDelegate: NSObject, ASAuthorizationControllerDelegate {}
    private final class OtherDelegate: NSObject, ASAuthorizationControllerDelegate {}

    private final class FakeController: PasskeyAuthorizationController {
        var delegate: ASAuthorizationControllerDelegate?
        private(set) var cancelCount = 0

        init(delegate: ASAuthorizationControllerDelegate) {
            self.delegate = delegate
        }

        func cancel() {
            cancelCount += 1
        }
    }

    private var isEnabled = true
    private var canceller: WebKitPasskeyRequestCanceller!

    override func setUp() {
        super.setUp()
        isEnabled = true
        canceller = WebKitPasskeyRequestCanceller(webKitDelegateClass: WebKitDelegate.self, isEnabled: { [unowned self] in isEnabled })
    }

    override func tearDown() {
        canceller = nil
        super.tearDown()
    }

    private func webKitController() -> FakeController {
        FakeController(delegate: WebKitDelegate())
    }

    func testWhenFirstWebKitRequestStarts_ThenNothingIsCancelled() {
        let first = webKitController()

        canceller.willPerform(first)

        XCTAssertEqual(first.cancelCount, 0)
        XCTAssertNotNil(first.delegate)
    }

    func testWhenNextWebKitRequestStarts_ThenPreviousIsDetachedAndCancelled() {
        let previous = webKitController()
        let next = webKitController()

        canceller.willPerform(previous)
        canceller.willPerform(next)

        XCTAssertEqual(previous.cancelCount, 1)
        XCTAssertNil(previous.delegate)
        XCTAssertEqual(next.cancelCount, 0)
        XCTAssertNotNil(next.delegate)
    }

    func testWhenSameRequestStartsAgain_ThenItIsNotCancelled() {
        let controller = webKitController()

        canceller.willPerform(controller)
        canceller.willPerform(controller)

        XCTAssertEqual(controller.cancelCount, 0)
        XCTAssertNotNil(controller.delegate)
    }

    func testWhenRequestsKeepStarting_ThenEachPreviousIsCancelledOnce() {
        let first = webKitController()
        let second = webKitController()
        let third = webKitController()

        canceller.willPerform(first)
        canceller.willPerform(second)
        canceller.willPerform(third)

        XCTAssertEqual(first.cancelCount, 1)
        XCTAssertEqual(second.cancelCount, 1)
        XCTAssertEqual(third.cancelCount, 0)
    }

    func testWhenNonWebKitRequestStarts_ThenItIsIgnored() {
        let webKitRequest = webKitController()
        let otherRequest = FakeController(delegate: OtherDelegate())
        let nextWebKitRequest = webKitController()

        canceller.willPerform(webKitRequest)
        canceller.willPerform(otherRequest)

        XCTAssertEqual(webKitRequest.cancelCount, 0)
        XCTAssertEqual(otherRequest.cancelCount, 0)

        canceller.willPerform(nextWebKitRequest)

        XCTAssertEqual(webKitRequest.cancelCount, 1)
        XCTAssertEqual(otherRequest.cancelCount, 0)
    }

    func testWhenDisabled_ThenNothingIsCancelledOrTracked() {
        let first = webKitController()
        let second = webKitController()
        let third = webKitController()

        isEnabled = false
        canceller.willPerform(first)
        canceller.willPerform(second)

        XCTAssertEqual(first.cancelCount, 0)
        XCTAssertEqual(second.cancelCount, 0)

        isEnabled = true
        canceller.willPerform(third)

        XCTAssertEqual(first.cancelCount, 0)
        XCTAssertEqual(second.cancelCount, 0)
    }
}
