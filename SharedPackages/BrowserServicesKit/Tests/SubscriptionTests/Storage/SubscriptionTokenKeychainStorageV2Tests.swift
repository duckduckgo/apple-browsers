//
//  SubscriptionTokenKeychainStorageV2Tests.swift
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
import Networking
import NetworkingTestingUtils
@testable import Subscription
import SubscriptionTestingUtilities

final class SubscriptionTokenKeychainStorageV2Tests: XCTestCase {

    private var storage: SubscriptionTokenKeychainStorageV2!
    private var mockKeychain: MockKeychainOperations!
    private var errorEvents: [(AccountKeychainAccessType, AccountKeychainAccessError)] = []
    private let errorEventsQueue = DispatchQueue(label: "test.error.events", attributes: .concurrent)

    override func setUp() {
        super.setUp()
        errorEvents = []
        mockKeychain = MockKeychainOperations()
        storage = SubscriptionTokenKeychainStorageV2(
            keychainType: .dataProtection(.unspecified),
            errorEventsHandler: { [weak self] type, error in
                self?.errorEventsQueue.async(flags: .barrier) {
                    self?.errorEvents.append((type, error))
                }
            },
            keychainOperations: mockKeychain
        )
    }

    override func tearDown() {
        mockKeychain?.reset()
        storage = nil
        mockKeychain = nil
        errorEvents = []
        super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testGetTokenContainer_WhenNoTokenExists_ReturnsNil() throws {
        let result = try storage.getTokenContainer()
        XCTAssertNil(result)
    }

    func testSaveAndGetTokenContainer_BasicFlow() throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        try storage.saveTokenContainer(tokenContainer)
        let retrieved = try storage.getTokenContainer()

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.accessToken, tokenContainer.accessToken)
        XCTAssertEqual(retrieved?.refreshToken, tokenContainer.refreshToken)
    }

    func testSaveTokenContainer_WithNilValue_RemovesExistingToken() throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        // First save a token
        try storage.saveTokenContainer(tokenContainer)
        XCTAssertNotNil(try storage.getTokenContainer())

        // Then remove it by saving nil
        try storage.saveTokenContainer(nil)
        XCTAssertNil(try storage.getTokenContainer())
    }

    func testUpdateExistingTokenContainer() throws {
        let originalToken = OAuthTokensFactory.makeValidTokenContainer()
        let updatedToken = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7200) // 2 hours

        try storage.saveTokenContainer(originalToken)
        try storage.saveTokenContainer(updatedToken)

        let retrieved = try storage.getTokenContainer()
        XCTAssertEqual(retrieved?.accessToken, updatedToken.accessToken)
        XCTAssertEqual(retrieved?.refreshToken, updatedToken.refreshToken)
    }

    // MARK: - Concurrency Tests

    func testConcurrentReadOperations() throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        try storage.saveTokenContainer(tokenContainer)

        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        let concurrentQueue = DispatchQueue(label: "test.concurrent.reads", attributes: .concurrent)

        for i in 0..<100 {
            concurrentQueue.async {
                do {
                    let result = try self.storage.getTokenContainer()
                    XCTAssertNotNil(result, "Read operation \(i) should succeed")
                    XCTAssertEqual(result?.accessToken, tokenContainer.accessToken)
                    expectation.fulfill()
                } catch {
                    XCTFail("Read operation \(i) failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testConcurrentWriteOperations() throws {
        let expectation = XCTestExpectation(description: "Concurrent writes complete")
        expectation.expectedFulfillmentCount = 50

        let concurrentQueue = DispatchQueue(label: "test.concurrent.writes", attributes: .concurrent)

        for i in 0..<50 {
            concurrentQueue.async {
                do {
                    let token = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: TimeInterval(3600 + i))
                    try self.storage.saveTokenContainer(token)
                    expectation.fulfill()
                } catch {
                    XCTFail("Write operation \(i) failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // Verify that some token was saved (the last one to complete)
        let finalToken = try storage.getTokenContainer()
        XCTAssertNotNil(finalToken)
        XCTAssertTrue(finalToken?.accessToken.contains("AccessTokenExpiringIn") ?? false)
    }

    func testConcurrentReadWriteOperations() throws {
        let initialToken = OAuthTokensFactory.makeValidTokenContainer()
        try storage.saveTokenContainer(initialToken)

        let readExpectation = XCTestExpectation(description: "Concurrent reads complete")
        readExpectation.expectedFulfillmentCount = 50

        let writeExpectation = XCTestExpectation(description: "Concurrent writes complete")
        writeExpectation.expectedFulfillmentCount = 25

        let concurrentQueue = DispatchQueue(label: "test.concurrent.mixed", attributes: .concurrent)

        // Start read operations
        for i in 0..<50 {
            concurrentQueue.async {
                do {
                    let result = try self.storage.getTokenContainer()
                    XCTAssertNotNil(result, "Read operation \(i) should return some token")
                    readExpectation.fulfill()
                } catch {
                    XCTFail("Read operation \(i) failed: \(error)")
                }
            }
        }

        // Start write operations
        for i in 0..<25 {
            concurrentQueue.async {
                do {
                    let token = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: TimeInterval(1800 + i))
                    try self.storage.saveTokenContainer(token)
                    writeExpectation.fulfill()
                } catch {
                    XCTFail("Write operation \(i) failed: \(error)")
                }
            }
        }

        wait(for: [readExpectation, writeExpectation], timeout: 15.0)

        // Verify final state is consistent
        let finalToken = try storage.getTokenContainer()
        XCTAssertNotNil(finalToken)
    }

    func testConcurrentDeleteOperations() throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        try storage.saveTokenContainer(tokenContainer)

        let expectation = XCTestExpectation(description: "Concurrent deletes complete")
        expectation.expectedFulfillmentCount = 20

        let concurrentQueue = DispatchQueue(label: "test.concurrent.deletes", attributes: .concurrent)

        for i in 0..<20 {
            concurrentQueue.async {
                do {
                    try self.storage.saveTokenContainer(nil) // This triggers deletion
                    expectation.fulfill()
                } catch {
                    XCTFail("Delete operation \(i) failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // Verify token is deleted
        let result = try storage.getTokenContainer()
        XCTAssertNil(result)
    }

    func testMultipleStorageInstancesConcurrency() throws {
        let mockKeychain1 = MockKeychainOperations()
        let mockKeychain2 = MockKeychainOperations()
        let mockKeychain3 = MockKeychainOperations()

        let storage1 = SubscriptionTokenKeychainStorageV2(
            errorEventsHandler: { _, _ in },
            keychainOperations: mockKeychain1
        )
        let storage2 = SubscriptionTokenKeychainStorageV2(
            errorEventsHandler: { _, _ in },
            keychainOperations: mockKeychain2
        )
        let storage3 = SubscriptionTokenKeychainStorageV2(
            errorEventsHandler: { _, _ in },
            keychainOperations: mockKeychain3
        )

        let expectation = XCTestExpectation(description: "Multiple instances complete")
        expectation.expectedFulfillmentCount = 60

        let concurrentQueue = DispatchQueue(label: "test.multiple.instances", attributes: .concurrent)

        // Operations with storage1
        for i in 0..<20 {
            concurrentQueue.async {
                do {
                    let token = OAuthTokensFactory.makeValidTokenContainer()
                    try storage1.saveTokenContainer(token)
                    expectation.fulfill()
                } catch {
                    XCTFail("Storage1 operation \(i) failed: \(error)")
                }
            }
        }

        // Operations with storage2
        for i in 0..<20 {
            concurrentQueue.async {
                do {
                    _ = try storage2.getTokenContainer()
                    // Result might be nil or contain a token, both are valid
                    expectation.fulfill()
                } catch {
                    XCTFail("Storage2 operation \(i) failed: \(error)")
                }
            }
        }

        // Operations with storage3
        for i in 0..<20 {
            concurrentQueue.async {
                do {
                    let token = OAuthTokensFactory.makeValidTokenContainer()
                    try storage3.saveTokenContainer(token)
                    expectation.fulfill()
                } catch {
                    XCTFail("Storage3 operation \(i) failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 15.0)

        // Verify final consistency - each storage should have its own state
        let finalToken1 = try storage1.getTokenContainer()
        XCTAssertNotNil(finalToken1)

        _ = try storage2.getTokenContainer()
        // This might be nil since we were only reading

        let finalToken3 = try storage3.getTokenContainer()
        XCTAssertNotNil(finalToken3)
    }

    // MARK: - Stress Tests

    func testHighVolumeOperations() throws {
        let operationCount = 1000
        let expectation = XCTestExpectation(description: "High volume operations complete")
        expectation.expectedFulfillmentCount = operationCount

        let concurrentQueue = DispatchQueue(label: "test.high.volume", attributes: .concurrent)

        for i in 0..<operationCount {
            concurrentQueue.async {
                do {
                    if i % 3 == 0 {
                        // Write operation
                        let token = OAuthTokensFactory.makeValidTokenContainer()
                        try self.storage.saveTokenContainer(token)
                    } else if i % 3 == 1 {
                        // Read operation
                        _ = try self.storage.getTokenContainer()
                    } else {
                        // Delete operation
                        try self.storage.saveTokenContainer(nil)
                    }
                    expectation.fulfill()
                } catch {
                    XCTFail("High volume operation \(i) failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 30.0)
    }

    func testRapidSuccessiveOperations() throws {
        let iterations = 100
        let expectation = XCTestExpectation(description: "Rapid successive operations complete")
        expectation.expectedFulfillmentCount = iterations * 3

        let serialQueue = DispatchQueue(label: "test.rapid.successive")

        serialQueue.async {
            for i in 0..<iterations {
                do {
                    // Save
                    let token = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: TimeInterval(3600 + i))
                    try self.storage.saveTokenContainer(token)
                    expectation.fulfill()

                    // Read
                    let retrieved = try self.storage.getTokenContainer()
                    XCTAssertNotNil(retrieved)
                    expectation.fulfill()

                    // Update
                    let updatedToken = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: TimeInterval(7200 + i))
                    try self.storage.saveTokenContainer(updatedToken)
                    expectation.fulfill()

                } catch {
                    XCTFail("Rapid operation \(i) failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 20.0)
    }

    // MARK: - Error Handling Tests

    func testErrorHandlerCalledOnKeychainFailure() throws {
        // Test keychain add failure
        mockKeychain.shouldFailAdd = true
        mockKeychain.addFailureStatus = errSecAuthFailed

        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        XCTAssertThrowsError(try storage.saveTokenContainer(tokenContainer)) { error in
            XCTAssertTrue(error is AccountKeychainAccessError)
        }

        // Verify error handler was called
        let errors = getErrorEvents()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].0, AccountKeychainAccessType.storeAuthToken)
    }

    func testKeychainLookupFailure() throws {
        mockKeychain.shouldFailCopyMatching = true
        mockKeychain.copyMatchingFailureStatus = errSecAuthFailed

        XCTAssertThrowsError(try storage.getTokenContainer()) { error in
            XCTAssertTrue(error is AccountKeychainAccessError)
        }

        // Verify error handler was called
        let errors = getErrorEvents()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].0, AccountKeychainAccessType.getAuthToken)
    }

    func testKeychainUpdateFailure() throws {
        // First add a token successfully
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        try storage.saveTokenContainer(tokenContainer)

        // Now make update fail
        mockKeychain.shouldFailUpdate = true
        mockKeychain.updateFailureStatus = errSecAuthFailed

        let updatedToken = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7200)

        XCTAssertThrowsError(try storage.saveTokenContainer(updatedToken)) { error in
            XCTAssertTrue(error is AccountKeychainAccessError)
        }

        // Verify error handler was called
        let errors = getErrorEvents()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].0, AccountKeychainAccessType.storeAuthToken)
    }

    func testKeychainDeleteFailure() throws {
        // First add a token successfully
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        try storage.saveTokenContainer(tokenContainer)

        // Now make delete fail
        mockKeychain.shouldFailDelete = true
        mockKeychain.deleteFailureStatus = errSecAuthFailed

        XCTAssertThrowsError(try storage.saveTokenContainer(nil)) { error in
            XCTAssertTrue(error is AccountKeychainAccessError)
        }

        // Verify error handler was called
        let errors = getErrorEvents()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].0, AccountKeychainAccessType.storeAuthToken)
    }

    func testConcurrentErrorHandling() throws {
        var errorCount = 0
        let errorCountQueue = DispatchQueue(label: "test.error.count")

        let storage = SubscriptionTokenKeychainStorageV2(
            errorEventsHandler: { _, _ in
                errorCountQueue.sync {
                    errorCount += 1
                }
            },
            keychainOperations: mockKeychain
        )

        // Make operations fail
        mockKeychain.shouldFailAdd = true
        mockKeychain.addFailureStatus = errSecAuthFailed

        let expectation = XCTestExpectation(description: "Concurrent errors handled")
        expectation.expectedFulfillmentCount = 10

        let concurrentQueue = DispatchQueue(label: "test.concurrent.errors", attributes: .concurrent)

        for i in 0..<10 {
            concurrentQueue.async {
                do {
                    let token = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: TimeInterval(3600 + i))
                    try storage.saveTokenContainer(token)
                    XCTFail("Should have thrown error")
                } catch {
                    // Expected to fail
                    expectation.fulfill()
                }
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Verify all errors were handled
        let finalErrorCount = errorCountQueue.sync { errorCount }
        XCTAssertEqual(finalErrorCount, 10)
    }

    // MARK: - Mock Keychain Specific Tests

    func testMockKeychainStorageIntegrity() throws {
        // Test that the mock keychain properly stores and retrieves data
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        try storage.saveTokenContainer(tokenContainer)

        // Verify the mock keychain has the data
        XCTAssertEqual(mockKeychain.storedItemsCount, 1)

        // Retrieve and verify
        let retrieved = try storage.getTokenContainer()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.accessToken, tokenContainer.accessToken)
        XCTAssertEqual(retrieved?.refreshToken, tokenContainer.refreshToken)

        // Delete and verify
        try storage.saveTokenContainer(nil)
        XCTAssertEqual(mockKeychain.storedItemsCount, 0)
        XCTAssertNil(try storage.getTokenContainer())
    }

    func testMockKeychainDuplicateHandling() throws {
        let tokenContainer1 = OAuthTokensFactory.makeValidTokenContainer()
        let tokenContainer2 = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7200)

        // Save first token
        try storage.saveTokenContainer(tokenContainer1)
        XCTAssertEqual(mockKeychain.storedItemsCount, 1)

        // Save second token (should update, not duplicate)
        try storage.saveTokenContainer(tokenContainer2)
        XCTAssertEqual(mockKeychain.storedItemsCount, 1)

        // Verify the second token was stored
        let retrieved = try storage.getTokenContainer()
        XCTAssertEqual(retrieved?.accessToken, tokenContainer2.accessToken)
    }

    func testMockKeychainThreadSafety() throws {
        let expectation = XCTestExpectation(description: "Mock keychain thread safety")
        expectation.expectedFulfillmentCount = 100

        let concurrentQueue = DispatchQueue(label: "test.mock.thread.safety", attributes: .concurrent)

        // Test concurrent operations on the mock keychain
        for i in 0..<100 {
            concurrentQueue.async {
                do {
                    let token = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: TimeInterval(3600 + i))
                    try self.storage.saveTokenContainer(token)
                    _ = try self.storage.getTokenContainer()
                    expectation.fulfill()
                } catch {
                    XCTFail("Mock keychain operation \(i) failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // Verify final state
        XCTAssertEqual(mockKeychain.storedItemsCount, 1)
        let finalToken = try storage.getTokenContainer()
        XCTAssertNotNil(finalToken)
    }

    func testPerformanceOfConcurrentReads() throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        try storage.saveTokenContainer(tokenContainer)

        measure {
            let expectation = XCTestExpectation(description: "Performance reads complete")
            expectation.expectedFulfillmentCount = 100

            let concurrentQueue = DispatchQueue(label: "test.performance.reads", attributes: .concurrent)

            for _ in 0..<100 {
                concurrentQueue.async {
                    do {
                        _ = try self.storage.getTokenContainer()
                        expectation.fulfill()
                    } catch {
                        XCTFail("Performance read failed: \(error)")
                    }
                }
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

    func testPerformanceOfConcurrentWrites() throws {
        measure {
            let expectation = XCTestExpectation(description: "Performance writes complete")
            expectation.expectedFulfillmentCount = 50

            let concurrentQueue = DispatchQueue(label: "test.performance.writes", attributes: .concurrent)

            for i in 0..<50 {
                concurrentQueue.async {
                    do {
                        let token = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: TimeInterval(3600 + i))
                        try self.storage.saveTokenContainer(token)
                        expectation.fulfill()
                    } catch {
                        XCTFail("Performance write failed: \(error)")
                    }
                }
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

    private func getErrorEvents() -> [(AccountKeychainAccessType, AccountKeychainAccessError)] {
        return errorEventsQueue.sync {
            return self.errorEvents
        }
    }
}

// MARK: - Test Utilities (factory already provides TokenContainer creation)

extension SubscriptionTokenKeychainStorageV2Tests {

    func assertNoErrorsReported() {
        let errors = getErrorEvents()
        XCTAssertTrue(errors.isEmpty, "Expected no errors, but got: \(errors)")
    }

    func assertErrorsReported(count: Int) {
        let errors = getErrorEvents()
        XCTAssertEqual(errors.count, count, "Expected \(count) errors, but got \(errors.count)")
    }
}
