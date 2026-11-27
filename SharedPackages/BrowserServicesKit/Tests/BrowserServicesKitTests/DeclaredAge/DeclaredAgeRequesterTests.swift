//
//  DeclaredAgeRequesterTests.swift
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

@_spi(Testing) import Persistence
import XCTest
@testable import BrowserServicesKit

@MainActor
final class DeclaredAgeRequesterTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC
    private var storage: (any ThrowingKeyedStoring<DeclaredAgeSettings>)!

    override func setUp() async throws {
        try await super.setUp()
        storage = InMemoryKeyValueStore().throwingKeyedStoring()
    }

    func testFirstLaunchIsRequestNeeded() async throws {
        let isNeeded = try await makeRequester().isRequestNeeded(isReinstall: false)

        XCTAssertTrue(isNeeded)
    }

    func testNotRequiredIsNotRequestNeeded() async throws {
        let isNeeded = try await makeRequester(service: ServiceMock(isRequired: false)).isRequestNeeded(isReinstall: false)

        XCTAssertFalse(isNeeded)
    }

    func testNotRequiredIsNotCheckedAgainOnceMarked() async throws {
        makeRequester().markNotRequired(isReinstall: false)

        let service = ServiceMock(isRequired: true)
        let isNeeded = try await makeRequester(service: service).isRequestNeeded(isReinstall: false)

        XCTAssertFalse(isNeeded)
        XCTAssertEqual(service.checkCount, 0)
    }

    func testAlreadyRequestedIsNotMarkedAsNotRequired() throws {
        try storeMarker(at: start)

        makeRequester().markNotRequired(isReinstall: false)

        XCTAssertNil(try storage.requestWasNotRequired)
    }

    func testFailedCheckThrowsAndStoresNothing() async {
        let requester = makeRequester(service: ServiceMock(isRequired: true, checkError: CancellationError()))

        let isNeeded = try? await requester.isRequestNeeded(isReinstall: false)

        XCTAssertNil(isNeeded)
        XCTAssertTrue(requester.isRequestDue(isReinstall: false))
    }

    func testNotRequiredIsCheckedAgainOnceAfterReinstall() async throws {
        makeRequester().markNotRequired(isReinstall: false)
        let service = ServiceMock(isRequired: false)
        let requester = makeRequester(service: service)

        _ = try await requester.isRequestNeeded(isReinstall: true)
        requester.markNotRequired(isReinstall: true)
        _ = try await requester.isRequestNeeded(isReinstall: true)

        XCTAssertEqual(service.checkCount, 1)
    }

    func testSuccessfulRequestStoresMarker() async throws {
        let service = ServiceMock(isRequired: true)
        let succeeded = await makeRequester(service: service).requestDeclaredAge(isReinstall: false, in: makeAnchor())

        XCTAssertTrue(succeeded)
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(try storage.lastRequestDate, start)
    }

    func testFailedRequestDoesNotStoreMarker() async throws {
        let service = ServiceMock(isRequired: true, requestError: CancellationError())
        let succeeded = await makeRequester(service: service).requestDeclaredAge(isReinstall: false, in: makeAnchor())

        XCTAssertFalse(succeeded)
        XCTAssertNil(try storage.lastRequestDate)
    }

    func testNotDueWithinAYear() throws {
        try storeMarker(at: start)
        let requester = makeRequester(now: start.addingTimeInterval(364 * 24 * 3600))

        XCTAssertFalse(requester.isRequestDue(isReinstall: false))
    }

    func testNotDueAfterAYear() throws {
        try storeMarker(at: start)
        let requester = makeRequester(now: start.addingTimeInterval(366 * 24 * 3600))

        XCTAssertFalse(requester.isRequestDue(isReinstall: false))
    }

    func testDueAfterReinstall() throws {
        try storeMarker(at: start)

        XCTAssertTrue(makeRequester().isRequestDue(isReinstall: true))
    }

    func testReinstallIsHandledOnce() async throws {
        try storeMarker(at: start)
        let requester = makeRequester()

        _ = await requester.requestDeclaredAge(isReinstall: true, in: makeAnchor())
        let isNeeded = try await requester.isRequestNeeded(isReinstall: true)

        XCTAssertFalse(isNeeded)
    }

    private func storeMarker(at date: Date) throws {
        try storage.set(date, for: \.lastRequestDate)
    }

    private func makeAnchor() -> DeclaredAgeAnchor {
#if os(macOS)
        NSWindow()
#else
        UIViewController()
#endif
    }

    private func makeRequester(service: ServiceMock? = nil,
                               now: Date? = nil) -> DeclaredAgeRequester {
        let date = now ?? start
        return DeclaredAgeRequester(service: service ?? ServiceMock(isRequired: true),
                                  storage: storage,
                                  now: { date })
    }
}

@MainActor
private final class ServiceMock: DeclaredAgeServicing {
    let isRequired: Bool
    let checkError: Error?
    let requestError: Error?
    private(set) var checkCount = 0
    private(set) var requestCount = 0

    init(isRequired: Bool, checkError: Error? = nil, requestError: Error? = nil) {
        self.isRequired = isRequired
        self.checkError = checkError
        self.requestError = requestError
    }

    func isRequestRequired() async throws -> Bool {
        checkCount += 1
        if let checkError {
            throw checkError
        }
        return isRequired
    }

    func requestDeclaredAge(in anchor: DeclaredAgeAnchor) async throws -> Bool {
        requestCount += 1
        if let requestError {
            throw requestError
        }
        return true
    }
}
