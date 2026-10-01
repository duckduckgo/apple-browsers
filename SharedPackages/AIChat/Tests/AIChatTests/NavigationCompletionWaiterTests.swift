//
//  NavigationCompletionWaiterTests.swift
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

import XCTest
@testable import AIChat

@MainActor
final class NavigationCompletionWaiterTests: XCTestCase {

    private enum TestError: Error, Equatable {
        case timeout
        case failed
        case terminated
    }

    private var waiter: NavigationCompletionWaiter!

    override func setUp() {
        super.setUp()
        waiter = NavigationCompletionWaiter()
    }

    override func tearDown() {
        waiter = nil
        super.tearDown()
    }

    /// Waits for a navigation, then runs `afterStart` once the wait is registered.
    private func wait(for navigation: AnyObject, timeout: TimeInterval = 5,
                      afterStart: @escaping @MainActor () -> Void) async -> Result<Void, Error> {
        await waiter.wait(timeout: timeout, timeoutError: TestError.timeout) {
            Task { @MainActor in afterStart() }
            return navigation
        }
    }

    func testWhenNavigationFinishesThenWaitSucceeds() async {
        let navigation = NSObject()

        let result = await wait(for: navigation) { [unowned self] in
            waiter.complete(navigation, with: .success(()))
        }

        XCTAssertNoThrow(try result.get())
    }

    func testWhenNavigationFailsThenWaitReturnsItsError() async {
        let navigation = NSObject()

        let result = await wait(for: navigation) { [unowned self] in
            waiter.complete(navigation, with: .failure(TestError.failed))
        }

        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? TestError, .failed) }
    }

    func testWhenAnotherNavigationReportsThenItIsIgnored() async {
        let navigation = NSObject()
        let staleNavigation = NSObject()

        let result = await wait(for: navigation) { [unowned self] in
            waiter.complete(staleNavigation, with: .failure(TestError.failed))
            waiter.complete(navigation, with: .success(()))
        }

        XCTAssertNoThrow(try result.get())
    }

    func testWhenANavigationReportsWithoutAHandleThenItIsIgnored() async {
        let navigation = NSObject()

        let result = await wait(for: navigation) { [unowned self] in
            waiter.complete(nil, with: .failure(TestError.failed))
            waiter.complete(navigation, with: .success(()))
        }

        XCTAssertNoThrow(try result.get())
    }

    func testWhenNavigationNeverReportsThenWaitTimesOut() async {
        let result = await wait(for: NSObject(), timeout: 0.05) {}

        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? TestError, .timeout) }
    }

    func testWhenPendingNavigationIsFailedThenWaitReturnsThatErrorImmediately() async {
        let result = await wait(for: NSObject()) { [unowned self] in
            waiter.failPendingNavigation(with: TestError.terminated)
        }

        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? TestError, .terminated) }
    }

    func testWhenTimedOutNavigationReportsLateThenNextWaitIsUnaffected() async {
        let timedOut = NSObject()
        _ = await wait(for: timedOut, timeout: 0.05) {}
        let next = NSObject()

        let result = await wait(for: next) { [unowned self] in
            waiter.complete(timedOut, with: .failure(TestError.failed))
            waiter.complete(next, with: .success(()))
        }

        XCTAssertNoThrow(try result.get())
    }
}
