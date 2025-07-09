//
//  BackgroundTaskSchedulerTests.swift
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
import Foundation
import Common
import BrowserServicesKit
import DataBrokerProtectionCoreTestsUtils
@testable import DataBrokerProtectionCore
@testable import DataBrokerProtection_iOS

final class BackgroundTaskSchedulerTests: XCTestCase {
    
    private var sut: BackgroundTaskScheduler!
    private var mockDatabase: MockDatabase!
    private var mockQueueManager: MockBrokerProfileJobQueueManager!
    private var mockJobDependencies: MockBrokerProfileJobDependencies!
    private var mockPixelsHandler: MockIOSPixelsHandler!
    private var validateRunPrerequisitesCalled = false
    private var validateRunPrerequisitesResult = true
    
    override func setUp() {
        super.setUp()

        let mockSharedPixelsHandler = DataBrokerProtectionCoreTestsUtils.MockPixelHandler()
        mockDatabase = MockDatabase()
        let mockMismatchCalculator = MockMismatchCalculator(database: mockDatabase, pixelHandler: mockSharedPixelsHandler)
        mockQueueManager = MockBrokerProfileJobQueueManager(
            jobQueue: MockBrokerProfileJobQueue(),
            jobProvider: MockDataBrokerOperationsCreator(),
            mismatchCalculator: mockMismatchCalculator,
            pixelHandler: mockSharedPixelsHandler)
        mockJobDependencies = MockBrokerProfileJobDependencies()
        mockPixelsHandler = MockIOSPixelsHandler(mapping: { _, _, _, _ in })

        sut = BackgroundTaskScheduler(
            maxWaitTime: .hours(48),
            maxEligibleJobsPerBackgroundTask: 10,
            database: mockDatabase,
            queueManager: mockQueueManager,
            jobDependencies: mockJobDependencies,
            iOSPixelsHandler: mockPixelsHandler,
            validateRunPrerequisites: { true }
        )
    }
    
    override func tearDown() {
        sut = nil
        mockDatabase = nil
        mockQueueManager = nil
        mockJobDependencies = nil
        mockPixelsHandler = nil
        super.tearDown()
    }
    
    func testCalculateEarliestBeginDate_NoJobs_ReturnsMaxWaitDate() async throws {
        // Given
        let startDate = Date()
        mockDatabase.brokerProfileQueryDataToReturn = []
        
        // When
        let result = try await sut.calculateEarliestBeginDate(from: startDate)
        
        // Then
        let expectedDate = startDate.addingTimeInterval(.hours(48))
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: result, date2: expectedDate))
    }
    
    func testCalculateEarliestBeginDate_EmptyBrokerProfileData_ReturnsMaxWaitDate() async throws {
        // Given
        let startDate = Date()
        mockDatabase.brokerProfileQueryDataToReturn = []
        
        // When
        let result = try await sut.calculateEarliestBeginDate(from: startDate)
        
        // Then
        let expectedDate = startDate.addingTimeInterval(.hours(48))
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: result, date2: expectedDate))
    }
    
    func testCalculateEarliestBeginDate_MultipleJobs_ReturnsLastJobDateWithinLimit() async throws {
        // Given
        let startDate = Date()
        let dates = (1...5).map { startDate.addingTimeInterval(.hours($0)) }
        mockDatabase.brokerProfileQueryDataToReturn = dates.map {
            createBrokerProfileQueryData(preferredRunDate: $0)
        }.shuffled()

        // When
        let result = try await sut.calculateEarliestBeginDate(from: startDate)
        
        // Then
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: result, date2: dates.max(by: <)!))
    }
    
    func testCalculateEarliestBeginDate_MoreThan10Jobs_OnlyConsidersFirst10() async throws {
        // Given
        let startDate = Date()
        let dates = (1...15).map { startDate.addingTimeInterval(TimeInterval.hours($0)) }
        mockDatabase.brokerProfileQueryDataToReturn = dates.map {
            createBrokerProfileQueryData(preferredRunDate: $0)
        }.shuffled()

        // When
        let result = try await sut.calculateEarliestBeginDate(from: startDate)
        
        // Then
        let expectedDate = dates.sorted(by: <)[9]
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: result, date2: expectedDate))
    }
    
    func testCalculateEarliestBeginDate_JobsWithNilDates_HandlesCorrectly() async throws {
        // Given
        let startDate = Date()
        let futureDate = startDate.addingTimeInterval(.hours(12))
        mockDatabase.brokerProfileQueryDataToReturn = [
            createBrokerProfileQueryData(preferredRunDate: nil),
            createBrokerProfileQueryData(preferredRunDate: futureDate),
            createBrokerProfileQueryData(preferredRunDate: nil),
        ]
        
        // When
        let result = try await sut.calculateEarliestBeginDate(from: startDate)
        
        // Then
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: result, date2: futureDate))
    }
    
    func testCalculateEarliestBeginDate_AllJobsBeyondMaxWait_ReturnsMaxWaitDate() async throws {
        // Given
        let startDate = Date()
        let beyondMaxDates = (60...65).map { startDate.addingTimeInterval(TimeInterval.hours($0)) }
        mockDatabase.brokerProfileQueryDataToReturn = beyondMaxDates.map {
            createBrokerProfileQueryData(preferredRunDate: $0)
        }
        
        // When
        let result = try await sut.calculateEarliestBeginDate(from: startDate)
        
        // Then
        let expectedDate = startDate.addingTimeInterval(TimeInterval.hours(48))
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: result, date2: expectedDate))
    }
    
    func testCalculateEarliestBeginDate_CustomStartDate_CalculatesFromProvidedDate() async throws {
        // Given
        let customStartDate = Date().addingTimeInterval(TimeInterval.hours(100))
        let futureDate = customStartDate.addingTimeInterval(TimeInterval.hours(12))
        mockDatabase.brokerProfileQueryDataToReturn = [
            createBrokerProfileQueryData(preferredRunDate: futureDate)
        ]
        
        // When
        let result = try await sut.calculateEarliestBeginDate(from: customStartDate)
        
        // Then
        XCTAssertEqual(result.timeIntervalSince1970, futureDate.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testCalculateEarliestBeginDate_MoreThan10JobsMixedWithNilDates_ReturnsLastNonNilDate() async throws {
        // Given
        let startDate = Date()
        mockDatabase.brokerProfileQueryDataToReturn = [
            createBrokerProfileQueryData(preferredRunDate: nil),
            createBrokerProfileQueryData(preferredRunDate: nil),
            createBrokerProfileQueryData(preferredRunDate: nil),
            createBrokerProfileQueryData(preferredRunDate: nil),
            createBrokerProfileQueryData(preferredRunDate: nil),
            createBrokerProfileQueryData(preferredRunDate: nil),
            createBrokerProfileQueryData(preferredRunDate: nil),
            createBrokerProfileQueryData(preferredRunDate: nil),
            createBrokerProfileQueryData(preferredRunDate: startDate),
            createBrokerProfileQueryData(preferredRunDate: startDate.addingTimeInterval(.hours(5))),
            createBrokerProfileQueryData(preferredRunDate: startDate.addingTimeInterval(-.hours(2))),
            createBrokerProfileQueryData(preferredRunDate: startDate.addingTimeInterval(.hours(50))),
            createBrokerProfileQueryData(preferredRunDate: startDate.addingTimeInterval(.hours(10))),
            createBrokerProfileQueryData(preferredRunDate: startDate.addingTimeInterval(.hours(20))),
            createBrokerProfileQueryData(preferredRunDate: startDate.addingTimeInterval(.hours(45))),
        ].shuffled()

        // When
        let result = try await sut.calculateEarliestBeginDate(from: startDate)
        
        // Then
        let expectedDate = startDate.addingTimeInterval(.hours(45))
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: result, date2: expectedDate))
    }
    
    func testCalculateEarliestBeginDate_DatabaseError_ThrowsError() async {
        // Given
        mockDatabase.fetchAllBrokerProfileQueryDataError = NSError(domain: "test", code: 1, userInfo: nil)
        
        // When/Then
        do {
            _ = try await sut.calculateEarliestBeginDate()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createBrokerProfileQueryData(
        preferredRunDate: Date?,
        isOptOut: Bool = Bool.random()
    ) -> BrokerProfileQueryData {
        if isOptOut {
            let extractedProfile = ExtractedProfile(id: 1)
            let optOutJobData = [BrokerProfileQueryData.createOptOutJobData(
                extractedProfileId: 1,
                brokerId: 1,
                profileQueryId: 1,
                preferredRunDate: preferredRunDate
            )]
            return BrokerProfileQueryData.mock(
                preferredRunDate: nil,
                extractedProfile: extractedProfile,
                optOutJobData: optOutJobData
            )
        } else {
            return BrokerProfileQueryData.mock(preferredRunDate: preferredRunDate)
        }
    }
}

class MockIOSPixelsHandler: EventMapping<IOSPixels> {}
