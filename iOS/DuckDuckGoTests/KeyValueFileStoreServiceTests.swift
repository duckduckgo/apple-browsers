//
//  KeyValueFileStoreServiceTests.swift
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

import Persistence
import Common
import XCTest
@testable import DuckDuckGo

class KeyValueFileStoreTwoStepServiceTests: XCTestCase {

    private enum Error: Swift.Error {
        case initError
        case readError
    }

    // MARK: - Regular Service

    private class MockKeyValueFileStore: ThrowingKeyValueStoring {

        var throwOnSet: Error?
        var underlyingDict: [String: Any]

        init(throwOnInit: Error? = nil,
             underlyingDict: [String: Any] = [:]) throws {
            if let throwOnInit {
                throw throwOnInit
            }

            self.underlyingDict = underlyingDict
        }

        func object(forKey key: String) throws -> Any? {
            underlyingDict[key]
        }
        
        func set(_ value: Any?, forKey key: String) throws {
            if let throwOnSet {
                throw throwOnSet
            }

            underlyingDict[key] = value
        }
        
        func removeObject(forKey key: String) throws {
            underlyingDict[key] = nil
        }
    }

    func testWhenNilIsReturnedThenNoEventIsCalled() {

        let service = KeyValueFileStoreTwoStepService(keyValueFilesStoreFactory: {
            nil
        }, eventHandling: .init(mapping: { event, _, _, _ in
            XCTFail("Event received: \(event)")
        }))

        service.onForeground()
        service.onBackground()
        service.onForeground()
        service.onBackground()
    }

    func testWhenInitFailsEventIsRaised() {

        let e = expectation(description: "Error raised")

        _ = KeyValueFileStoreTwoStepService(keyValueFilesStoreFactory: {
            try MockKeyValueFileStore(throwOnInit: Error.initError)
        }, eventHandling: .init(mapping: { event, error, _, _ in
            e.fulfill()

            XCTAssertEqual(event, .kvfsInitError)
            XCTAssertEqual(error as? KeyValueFileStoreTwoStepServiceTests.Error, Error.initError)
        }))

        waitForExpectations(timeout: 1)
    }

    func testWhenInitialAndSecondFetchSucceedEventsAreRaised() {

        let firstEventFired = expectation(description: "1st Event Fired")
        let secondEventFired = expectation(description: "2nd Event Fired")

        let service = KeyValueFileStoreTwoStepService(keyValueFilesStoreFactory: {
            try MockKeyValueFileStore()
        }, eventHandling: .init(mapping: { event, error, params, _ in
            switch event {
            case .kvfsInitError, .appSupportDirAccessError:
                XCTFail("Unexpected event")
            case .kvfsFirstAccess(let status):
                firstEventFired.fulfill()
                XCTAssertNil(error)
                XCTAssertEqual(status, true)
            case .kvfsSecondAccess(let firstStatus, let secondStatus):
                secondEventFired.fulfill()
                XCTAssertNil(error)
                XCTAssertEqual(firstStatus, true)
                XCTAssertEqual(secondStatus, true)
                XCTAssertEqual(params?[KeyValueFileStoreTwoStepService.Constants.pixelSourceParam], "foreground")
            }
        }))

        service.onForeground()

        // Subsequent calls should not trigger pixels
        service.onBackground()

        waitForExpectations(timeout: 1)
    }

    func testWhenInitialFetchFailsEventIsRaisedAndSecondSuccessfulCheckReportsIt() throws {

        let store = try MockKeyValueFileStore()

        // Throw on first read
        store.throwOnSet = Error.readError

        let firstEventFired = expectation(description: "1st Event Fired")
        let secondEventFired = expectation(description: "2nd Event Fired")

        let service = KeyValueFileStoreTwoStepService(keyValueFilesStoreFactory: {
            store
        }, eventHandling: .init(mapping: { event, error, params, _ in
            switch event {
            case .kvfsInitError, .appSupportDirAccessError:
                XCTFail("Unexpected event")
            case .kvfsFirstAccess(let status):
                firstEventFired.fulfill()
                XCTAssertEqual(error as? KeyValueFileStoreTwoStepServiceTests.Error, Error.readError)
                XCTAssertEqual(status, false)
            case .kvfsSecondAccess(let firstStatus, let secondStatus):
                secondEventFired.fulfill()
                XCTAssertNil(error)
                XCTAssertEqual(firstStatus, false)
                XCTAssertEqual(secondStatus, true)
                XCTAssertEqual(params?[KeyValueFileStoreTwoStepService.Constants.pixelSourceParam], "background")
            }
        }))

        // Do not Throw on second read
        store.throwOnSet = nil
        service.onBackground()

        waitForExpectations(timeout: 1)
    }

    func testWhenInitialAndSecondFetchFailEventsAreRaised() throws {

        let store = try MockKeyValueFileStore()

        // Throw on first read
        store.throwOnSet = Error.readError

        let firstEventFired = expectation(description: "1st Event Fired")
        let secondEventFired = expectation(description: "2nd Event Fired")

        let service = KeyValueFileStoreTwoStepService(keyValueFilesStoreFactory: {
            store
        }, eventHandling: .init(mapping: { event, error, _, _ in
            switch event {
            case .kvfsInitError, .appSupportDirAccessError:
                XCTFail("Unexpected event")
            case .kvfsFirstAccess(let status):
                firstEventFired.fulfill()
                XCTAssertEqual(error as? KeyValueFileStoreTwoStepServiceTests.Error, Error.readError)
                XCTAssertEqual(status, false)
            case .kvfsSecondAccess(let firstStatus, let secondStatus):
                secondEventFired.fulfill()
                XCTAssertEqual(error as? KeyValueFileStoreTwoStepServiceTests.Error, Error.readError)
                XCTAssertEqual(firstStatus, false)
                XCTAssertEqual(secondStatus, false)
            }
        }))

        service.onForeground()

        waitForExpectations(timeout: 1)
    }

    // MARK: - Async Service

    func testAsyncWhenNilIsReturnedThenNoEventIsCalled() {

        let e = expectation(description: "Not called")
        e.isInverted = true

        let service = KeyValueFileStoreAsyncService(keyValueFilesStoreFactory: {
            nil
        }, eventHandling: .init(mapping: { event, _, _, _ in
            XCTFail("Event received: \(event)")
        }))

        waitForExpectations(timeout: 1)
    }

    func testAsyncWhenInitFailsEventIsRaised() {

        let e = expectation(description: "Error raised")

        _ = KeyValueFileStoreAsyncService(keyValueFilesStoreFactory: {
            try MockKeyValueFileStore(throwOnInit: Error.initError)
        }, eventHandling: .init(mapping: { event, error, _, _ in
            e.fulfill()

            XCTAssertEqual(event, .kvfsInitError)
            XCTAssertEqual(error as? KeyValueFileStoreTwoStepServiceTests.Error, Error.initError)
        }))

        waitForExpectations(timeout: 1)
    }

    func testAsyncWhenInitialFetchSucceedEventIsRaised() {

        let eventFired = expectation(description: "Event Fired")

        let service = KeyValueFileStoreAsyncService(keyValueFilesStoreFactory: {
            try MockKeyValueFileStore()
        }, eventHandling: .init(mapping: { event, error, _, _ in
            switch event {
            case .kvfsInitError, .appSupportDirAccessError:
                XCTFail("Unexpected event")
            case .kvfsAccess(let status):
                eventFired.fulfill()
                XCTAssertNil(error)
                XCTAssertEqual(status, true)
            }
        }))

        waitForExpectations(timeout: 1)
    }

    // MARK: - Retry Service

    func testRetryWhenNilIsReturnedThenNoEventIsCalled() {

        let e = expectation(description: "Not called")
        e.isInverted = true

        let service = KeyValueFileStoreRetryService(keyValueFilesStoreFactory: {
            nil
        }, eventHandling: .init(mapping: { event, _, _, _ in
            XCTFail("Event received: \(event)")
        }))

        waitForExpectations(timeout: 1)
    }

    func testRetryWhenInitialFetchSucceedEventIsRaised() {

        let eventFired = expectation(description: "Event Fired")

        let service = KeyValueFileStoreRetryService(keyValueFilesStoreFactory: {
            try MockKeyValueFileStore()
        }, eventHandling: .init(mapping: { event, error, _, _ in
            switch event {
            case .kvfsInitError, .appSupportDirAccessError:
                XCTFail("Unexpected event")
            case .kvfsAccess(let status, let delay):
                eventFired.fulfill()
                XCTAssertNil(error)
                XCTAssertEqual(status, true)
                XCTAssertEqual(delay, 0)
            }
        }))

        waitForExpectations(timeout: 1)
    }

    func testRetryWhenInitFailsEventIsRaisedButOnlyTillItSucceeds() throws {

        let eventFired = expectation(description: "Error raised not enough times")
        eventFired.expectedFulfillmentCount = 2

        let upperLimit = expectation(description: "Error raised too many times")
        upperLimit.expectedFulfillmentCount = 3
        upperLimit.isInverted = true

        let store = try MockKeyValueFileStore()
        store.throwOnSet = KeyValueFileStoreTwoStepServiceTests.Error.readError

        let service = KeyValueFileStoreRetryService(keyValueFilesStoreFactory: {
            store
        }, eventHandling: .init(mapping: { event, error, _, _ in
            upperLimit.fulfill()

            switch event {
            case .kvfsInitError, .appSupportDirAccessError:
                XCTFail("Unexpected event")
            case .kvfsAccess(let status, let delay):
                eventFired.fulfill()

                if delay == 0 {
                    XCTAssertEqual(error as? KeyValueFileStoreTwoStepServiceTests.Error, Error.readError)
                    XCTAssertEqual(status, false)
                    XCTAssertEqual(delay, 0)

                    store.throwOnSet = nil
                } else {
                    XCTAssertNil(error)
                    XCTAssertEqual(status, true)
                    XCTAssertEqual(delay, 1)
                }
            }

        }))

        waitForExpectations(timeout: 5)
    }

    func testRetryWhenInitFailsEventIsRaisedButOnly5Times() throws {
        throw XCTSkip("Slow, run locally")

        let eventFired = expectation(description: "Error raised not enough times")
        eventFired.expectedFulfillmentCount = 5

        let upperLimit = expectation(description: "Error raised too many times")
        upperLimit.expectedFulfillmentCount = 6
        upperLimit.isInverted = true

        let store = try MockKeyValueFileStore()
        store.throwOnSet = KeyValueFileStoreTwoStepServiceTests.Error.readError

        var expectedDelay = 0

        let service = KeyValueFileStoreRetryService(keyValueFilesStoreFactory: {
            store
        }, eventHandling: .init(mapping: { event, error, _, _ in
            upperLimit.fulfill()

            switch event {
            case .kvfsInitError, .appSupportDirAccessError:
                XCTFail("Unexpected event")
            case .kvfsAccess(let status, let delay):
                eventFired.fulfill()
                XCTAssertEqual(error as? KeyValueFileStoreTwoStepServiceTests.Error, Error.readError)
                XCTAssertEqual(status, false)
                XCTAssertEqual(delay, expectedDelay)

                if delay == 0 {
                    expectedDelay = 1
                } else {
                    expectedDelay *= 2
                }
            }

        }))

        waitForExpectations(timeout: 30)
    }
}
