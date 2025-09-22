//
//  JobQueueManagerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class JobQueueManagerTests: XCTestCase {

    private var sut: JobQueueManager!

    private var mockQueue: MockBrokerProfileJobQueue!
    private var mockOperationsCreator: MockDataBrokerOperationsCreator!
    private var mockEmailConfirmationJobProvider: MockEmailConfirmationJobProvider!
    private var mockDatabase: MockDatabase!
    private var mockPixelHandler: MockPixelHandler!
    private var mockMismatchCalculator: MockMismatchCalculator!
    private var mockSchedulerConfig = BrokerJobExecutionConfig()
    private var mockScanRunner: MockScanSubJobWebRunner!
    private var mockOptOutRunner: MockOptOutSubJobWebRunner!
    private var mockEventsHandler: MockOperationEventsHandler!
    private var mockJobErrorDelegate: MockBrokerProfileJobErrorDelegate!
    private var mockDependencies: BrokerProfileJobDependencies!

    override func setUpWithError() throws {
        mockQueue = MockBrokerProfileJobQueue()
        mockOperationsCreator = MockDataBrokerOperationsCreator()
        mockEmailConfirmationJobProvider = MockEmailConfirmationJobProvider()
        mockDatabase = MockDatabase()
        mockPixelHandler = MockPixelHandler()
        mockMismatchCalculator = MockMismatchCalculator(database: mockDatabase, pixelHandler: mockPixelHandler)
        mockScanRunner = MockScanSubJobWebRunner()
        mockOptOutRunner = MockOptOutSubJobWebRunner()
        mockEventsHandler = MockOperationEventsHandler()

        mockDependencies = BrokerProfileJobDependencies(database: mockDatabase,
                                                        contentScopeProperties: ContentScopeProperties.mock,
                                                        privacyConfig: PrivacyConfigurationManagingMock(),
                                                        executionConfig: BrokerJobExecutionConfig(),
                                                        notificationCenter: .default,
                              pixelHandler: mockPixelHandler,
                                                        eventsHandler: mockEventsHandler,
                                                        dataBrokerProtectionSettings: DataBrokerProtectionSettings(defaults: .standard),
                                                        emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
                                                        captchaService: CaptchaServiceMock(),
                                                        featureFlagger: MockDBPFeatureFlagger())
    }

    func testWhenStartImmediateScanOperations_thenCreatorIsCalledWithManualScanOperationType() async throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false,
                                                    jobDependencies: mockDependencies,
                                                    errorHandler: nil,
                                                    completion: nil)

        // Then
        XCTAssertEqual(mockOperationsCreator.createdType, .manualScan)
    }

    func testWhenStartScheduledAllOperations_thenCreatorIsCalledWithAllOperationType() async throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)

        // When
        sut.startScheduledAllOperationsIfPermitted(showWebView: false,
                                                   jobDependencies: mockDependencies,
                                                   errorHandler: nil,
                                                   completion: nil)

        // Then
        XCTAssertEqual(mockOperationsCreator.createdType, .all)
    }

    func testWhenStartScheduledScanOperations_thenCreatorIsCalledWithScheduledScanOperationType() async throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)

        // When
        sut.startScheduledScanOperationsIfPermitted(showWebView: false,
                                                    jobDependencies: mockDependencies,
                                                    errorHandler: nil,
                                                    completion: nil)

        // Then
        XCTAssertEqual(mockOperationsCreator.createdType, .scheduledScan)
    }

    func testWhenStartImmediateScan_andScanCompletesWithErrors_thenCompletionIsCalledWithErrors() async throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        let mockOperation = MockBrokerProfileJob(id: 1, jobType: .manualScan, errorDelegate: sut)
        let mockOperationWithError = MockBrokerProfileJob(id: 2, jobType: .manualScan, errorDelegate: sut, shouldError: true)
        mockOperationsCreator.operationCollections = [mockOperation, mockOperationWithError]
        let expectation = expectation(description: "Expected completion to be called")
        var errorCollection: DataBrokerProtectionJobsErrorCollection!
        let expectedConcurrentOperations = BrokerJobExecutionConfig().concurrentJobsFor(.manualScan)
        var errorHandlerCalled = false

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollection = errors
            errorHandlerCalled = true
        } completion: {
            XCTAssertTrue(errorHandlerCalled)
            expectation.fulfill()
        }

        mockQueue.completeAllOperations()

        // Then
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssert(errorCollection.operationErrors?.count == 1)
        XCTAssertNil(mockOperationsCreator.priorityDate)
        XCTAssertEqual(mockQueue.maxConcurrentOperationCount, expectedConcurrentOperations)
    }

    func testWhenStartScheduledAllOperations_andOperationsCompleteWithErrors_thenErrorHandlerIsCalledWithErrors_followedByCompletionBlock() async throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        let mockOperation = MockBrokerProfileJob(id: 1, jobType: .all, errorDelegate: sut)
        let mockOperationWithError = MockBrokerProfileJob(id: 2, jobType: .all, errorDelegate: sut, shouldError: true)
        mockOperationsCreator.operationCollections = [mockOperation, mockOperationWithError]
        let expectation = expectation(description: "Expected completion to be called")
        var errorCollection: DataBrokerProtectionJobsErrorCollection!
        let expectedConcurrentOperations = BrokerJobExecutionConfig().concurrentJobsFor(.all)
        var errorHandlerCalled = false

        // When
        sut.startScheduledAllOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollection = errors
            errorHandlerCalled = true
        } completion: {
            XCTAssertTrue(errorHandlerCalled)
            expectation.fulfill()
        }

        mockQueue.completeAllOperations()

        // Then
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssert(errorCollection.operationErrors?.count == 1)
        XCTAssertNotNil(mockOperationsCreator.priorityDate)
        XCTAssertEqual(mockQueue.maxConcurrentOperationCount, expectedConcurrentOperations)
    }

    func testWhenStartScheduledScanOperations_andOperationsCompleteWithErrors_thenCompletionIsCalledWithErrors() async throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        let mockOperation = MockBrokerProfileJob(id: 1, jobType: .scheduledScan, errorDelegate: sut)
        let mockOperationWithError = MockBrokerProfileJob(id: 2, jobType: .scheduledScan, errorDelegate: sut, shouldError: true)
        mockOperationsCreator.operationCollections = [mockOperation, mockOperationWithError]
        let expectation = expectation(description: "Expected errors to be returned in completion")
        var errorCollection: DataBrokerProtectionJobsErrorCollection!
        let expectedConcurrentOperations = BrokerJobExecutionConfig().concurrentJobsFor(.scheduledScan)
        var errorHandlerCalled = false

        // When
        sut.startScheduledScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollection = errors
            errorHandlerCalled = true
        } completion: {
            XCTAssertTrue(errorHandlerCalled)
            expectation.fulfill()
        }

        mockQueue.completeAllOperations()

        // Then
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssert(errorCollection.operationErrors?.count == 1)
        XCTAssertNotNil(mockOperationsCreator.priorityDate)
        XCTAssertEqual(mockQueue.maxConcurrentOperationCount, expectedConcurrentOperations)
    }

    func testWhenStartImmediateScan_andCurrentModeIsScheduled_thenCurrentOperationsAreInterrupted_andCurrentCompletionIsCalledWithErrors() async throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        let mockOperationsWithError = (1...2).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut, shouldError: true) }
        var mockOperations = (3...4).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        mockOperationsCreator.operationCollections = mockOperationsWithError + mockOperations
        var errorCollection: DataBrokerProtectionJobsErrorCollection!

        // When
        sut.startScheduledAllOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollection = errors
        } completion: {
            // no-op
        }

        mockQueue.completeOperationsUpTo(index: 2)

        // Then
        XCTAssert(mockQueue.operationCount == 2)

        // Given
        mockOperations = (5...8).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        mockOperationsCreator.operationCollections = mockOperations

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { _ in
        } completion: {
            // no-op
        }

        // Then
        XCTAssert(errorCollection.operationErrors?.count == 2)
        let error = errorCollection.oneTimeError as? BrokerProfileJobQueueError
        XCTAssertEqual(error, .interrupted)
        XCTAssert(mockQueue.didCallCancelCount == 1)
        XCTAssert(mockQueue.operations.filter { !$0.isCancelled }.count == 4)
        XCTAssert(mockQueue.operations.filter { $0.isCancelled }.count >= 2)
    }

    func testWhenStartImmediateScan_andCurrentModeIsImmediate_thenCurrentOperationsAreInterrupted_andCurrentCompletionIsCalledWithErrors() async throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        let mockOperationsWithError = (1...2).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut, shouldError: true) }
        var mockOperations = (3...4).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        mockOperationsCreator.operationCollections = mockOperationsWithError + mockOperations
        var errorCollection: DataBrokerProtectionJobsErrorCollection!

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollection = errors
        } completion: {
            // no-op
        }

        mockQueue.completeOperationsUpTo(index: 2)

        // Then
        XCTAssert(mockQueue.operationCount == 2)

        // Given
        mockOperations = (5...8).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        mockOperationsCreator.operationCollections = mockOperations

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { _ in
        } completion: {
            // no-op
        }

        // Then
        XCTAssert(errorCollection.operationErrors?.count == 2)
        let error = errorCollection.oneTimeError as? BrokerProfileJobQueueError
        XCTAssertEqual(error, .interrupted)
        XCTAssert(mockQueue.didCallCancelCount == 1)
        XCTAssert(mockQueue.operations.filter { !$0.isCancelled }.count == 4)
        XCTAssert(mockQueue.operations.filter { $0.isCancelled }.count >= 2)
    }

    func testWhenSecondImmedateScanInterruptsFirst_andFirstHadErrors_thenSecondCompletesOnlyWithNewErrors() async throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        var mockOperationsWithError = (1...2).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut, shouldError: true) }
        var mockOperations = (3...4).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        mockOperationsCreator.operationCollections = mockOperationsWithError + mockOperations
        var errorCollectionFirst: DataBrokerProtectionJobsErrorCollection!

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollectionFirst = errors
        } completion: {
            // no-op
        }

        mockQueue.completeOperationsUpTo(index: 2)

        // Then
        XCTAssert(mockQueue.operationCount == 2)

        // Given
        var errorCollectionSecond: DataBrokerProtectionJobsErrorCollection!
        mockOperationsWithError = (5...6).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut, shouldError: true) }
        mockOperations = (7...8).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        mockOperationsCreator.operationCollections = mockOperationsWithError + mockOperations

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollectionSecond = errors
        } completion: {
            // no-op
        }

        mockQueue.completeAllOperations()

        // Then
        XCTAssert(errorCollectionFirst.operationErrors?.count == 2)
        XCTAssert(errorCollectionSecond.operationErrors?.count == 2)
        XCTAssert(mockQueue.didCallCancelCount == 1)
    }

    func testWhenStartScheduledAllOperations_andCurrentModeIsImmediate_thenCurrentOperationsAreNotInterrupted_andNewCompletionIsCalledWithError() throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        var mockOperations = (1...5).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        var mockOperationsWithError = (6...10).map { MockBrokerProfileJob(id: $0,
                                                                          jobType: .manualScan,
                                                                          errorDelegate: sut,
                                                                          shouldError: true) }
        mockOperationsCreator.operationCollections = mockOperations + mockOperationsWithError
        var errorCollection: DataBrokerProtectionJobsErrorCollection!

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { _ in
        } completion: {
            // no-op
        }

        // Then
        XCTAssert(mockQueue.operationCount == 10)

        // Given
        mockOperations = (11...15).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        mockOperationsWithError = (16...20).map { MockBrokerProfileJob(id: $0,
                                                                       jobType: .manualScan,
                                                                       errorDelegate: sut,
                                                                       shouldError: true) }
        mockOperationsCreator.operationCollections = mockOperations + mockOperationsWithError
        let expectedError = BrokerProfileJobQueueError.cannotInterrupt
        var completionCalled = false

        // When
        sut.startScheduledAllOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollection = errors
            completionCalled.toggle()
        } completion: {
            // no-op
        }

        // Then
        XCTAssert(mockQueue.didCallCancelCount == 0)
        XCTAssert(mockQueue.operations.filter { !$0.isCancelled }.count == 10)
        XCTAssert(mockQueue.operations.filter { $0.isCancelled }.count == 0)
        XCTAssertEqual((errorCollection.oneTimeError as? BrokerProfileJobQueueError), expectedError)
        XCTAssert(completionCalled)
    }

    func testWhenStartScheduledScanOperations_andCurrentModeIsImmediate_thenCurrentOperationsAreNotInterrupted_andNewCompletionIsCalledWithError() throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        var mockOperations = (1...5).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        var mockOperationsWithError = (6...10).map { MockBrokerProfileJob(id: $0,
                                                                          jobType: .manualScan,
                                                                          errorDelegate: sut,
                                                                          shouldError: true) }
        mockOperationsCreator.operationCollections = mockOperations + mockOperationsWithError
        var errorCollection: DataBrokerProtectionJobsErrorCollection!

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { _ in } completion: {
            // no-op
        }

        // Then
        XCTAssert(mockQueue.operationCount == 10)

        // Given
        mockOperations = (11...15).map { MockBrokerProfileJob(id: $0, jobType: .manualScan, errorDelegate: sut) }
        mockOperationsWithError = (16...20).map { MockBrokerProfileJob(id: $0,
                                                                       jobType: .manualScan,
                                                                       errorDelegate: sut,
                                                                       shouldError: true) }
        mockOperationsCreator.operationCollections = mockOperations + mockOperationsWithError
        let expectedError = BrokerProfileJobQueueError.cannotInterrupt
        var completionCalled = false

        // When
        sut.startScheduledScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollection = errors
        } completion: {
            completionCalled.toggle()
        }

        // Then
        XCTAssert(mockQueue.didCallCancelCount == 0)
        XCTAssert(mockQueue.operations.filter { !$0.isCancelled }.count == 10)
        XCTAssert(mockQueue.operations.filter { $0.isCancelled }.count == 0)
        XCTAssertEqual((errorCollection.oneTimeError as? BrokerProfileJobQueueError), expectedError)
        XCTAssert(completionCalled)
    }

    func testWhenOperationBuildingFails_thenCompletionIsCalledOnOperationCreationOneTimeError() async throws {
        // Given
        mockOperationsCreator.shouldError = true
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        let expectation = expectation(description: "Expected completion to be called")
        var errorCollection: DataBrokerProtectionJobsErrorCollection!

        // When
        sut.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: mockDependencies) { errors in
            errorCollection = errors
        } completion: {
            expectation.fulfill()
        }

        // Then
        await fulfillment(of: [expectation], timeout: 3)
        XCTAssertNotNil(errorCollection.oneTimeError)
    }

    func testWhenCallDebugOptOutCommand_thenOptOutOperationsAreCreated() throws {
        // Given
        sut = JobQueueManager(jobQueue: mockQueue,
                              jobProvider: mockOperationsCreator,
                              emailConfirmationJobProvider: mockEmailConfirmationJobProvider,
                              mismatchCalculator: mockMismatchCalculator,
                              pixelHandler: mockPixelHandler)
        let expectedConcurrentOperations = BrokerJobExecutionConfig().concurrentJobsFor(.optOut)
        XCTAssert(mockOperationsCreator.createdType == .manualScan)

        // When
        sut.execute(.startOptOutOperations(showWebView: false,
                                           jobDependencies: mockDependencies,
                                           errorHandler: nil,
                                           completion: nil))

        // Then
        XCTAssert(mockOperationsCreator.createdType == .optOut)
        XCTAssertEqual(mockQueue.maxConcurrentOperationCount, expectedConcurrentOperations)
    }
}
