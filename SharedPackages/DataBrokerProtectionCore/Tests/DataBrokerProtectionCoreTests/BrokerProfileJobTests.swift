//
//  BrokerProfileJobTests.swift
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

@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
import XCTest

final class BrokerProfileJobTests: XCTestCase {
    lazy var mockOptOutQueryData: [BrokerProfileQueryData] = {
        let brokerId: Int64 = 1

        let mockNilPreferredRunDateQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: nil, optOutJobData: [BrokerProfileQueryData.createOptOutJobData(extractedProfileId: Int64($0), brokerId: brokerId, profileQueryId: Int64($0), preferredRunDate: nil)])
        }
        let mockPastQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowMinus(hours: $0), optOutJobData: [BrokerProfileQueryData.createOptOutJobData(extractedProfileId: Int64($0), brokerId: brokerId, profileQueryId: Int64($0), preferredRunDate: .nowMinus(hours: $0))])
        }
        let mockFutureQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowPlus(hours: $0), optOutJobData: [BrokerProfileQueryData.createOptOutJobData(extractedProfileId: Int64($0), brokerId: brokerId, profileQueryId: Int64($0), preferredRunDate: .nowPlus(hours: $0))])
        }

        return mockNilPreferredRunDateQueryData + mockPastQueryData + mockFutureQueryData
    }()

    lazy var mockScanQueryData: [BrokerProfileQueryData] = {
        let mockNilPreferredRunDateQueryData = Array(1...10).map { _ in
            BrokerProfileQueryData.mock(preferredRunDate: nil)
        }
        let mockPastQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowMinus(hours: $0))
        }
        let mockFutureQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowPlus(hours: $0))
        }

        return mockNilPreferredRunDateQueryData + mockPastQueryData + mockFutureQueryData
    }()

    // MARK: - Lifecycle Tests

    func testWhenFetchingBrokerProfileQueryDataFails_ThenJobCompletesWithNoOutput() {
        let delegate = MockBrokerProfileJobErrorDelegate()
        let database = MockDatabase()
        let mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.database = database

        database.fetchAllBrokerProfileQueryDataError = NSError(domain: "pir.test.error", code: 0, userInfo: nil)

        let job = BrokerProfileJob(dataBrokerID: 1,
                                   jobType: .all,
                                   showWebView: false,
                                   errorDelegate: delegate,
                                   jobDependencies: mockDependencies)

        let finishedExpectation = expectation(for: NSPredicate(format: "isFinished == true"), evaluatedWith: job, handler: nil)
        job.start()
        wait(for: [finishedExpectation], timeout: 10.0)

        XCTAssertTrue(job.isFinished)
        XCTAssertTrue(database.scanEvents.isEmpty)
        XCTAssertTrue(database.optOutEvents.isEmpty)
    }

    func testWhenScanDataIsPresent_ThenScanEventsAreCreated() {
        let delegate = MockBrokerProfileJobErrorDelegate()
        let database = MockDatabase()
        let mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.database = database

        database.brokerProfileQueryDataToReturn = [
            .init(dataBroker: .mock(withId: 1), profileQuery: .mock, scanJobData: .mock(withBrokerId: 1))
        ]

        let job = BrokerProfileJob(dataBrokerID: 1,
                                   jobType: .all,
                                   showWebView: false,
                                   errorDelegate: delegate,
                                   jobDependencies: mockDependencies)

        let finishedExpectation = expectation(for: NSPredicate(format: "isFinished == true"), evaluatedWith: job, handler: nil)
        job.start()
        wait(for: [finishedExpectation], timeout: 10.0)

        XCTAssertTrue(job.isFinished)
        XCTAssertTrue(database.scanEvents.contains(where: { $0.type == .scanStarted }))
        XCTAssertTrue(database.scanEvents.contains(where: { $0.type == .noMatchFound }))
        XCTAssertTrue(database.optOutEvents.isEmpty)
    }

    func testWhenOptOutDataIsPresent_ThenOptOutEventsAreCreated() {
        let delegate = MockBrokerProfileJobErrorDelegate()
        let database = MockDatabase()
        let mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.database = database

        let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        let currentPreferredRunDate = Date()

        let mockDataBroker = DataBroker(id: brokerId,
                                        name: "databroker",
                                        url: "databroker.com",
                                        steps: [Step](),
                                        version: "1.0",
                                        schedulingConfig: config,
                                        optOutUrl: "",
                                        eTag: "",
                                        removedAt: nil)
        let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

        let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
        let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

        let extractedProfileSaved = ExtractedProfile(id: 1, name: "Some name", profileUrl: "abc")

        let optOutData = [OptOutJobData.mock(with: extractedProfileSaved)]

        let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker,
                                                            profileQuery: mockProfileQuery,
                                                            scanJobData: mockScanOperation,
                                                            optOutJobData: optOutData)
        database.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

        let job = BrokerProfileJob(dataBrokerID: 1,
                                   jobType: .all,
                                   showWebView: false,
                                   errorDelegate: delegate,
                                   jobDependencies: mockDependencies)

        let finishedExpectation = expectation(for: NSPredicate(format: "isFinished == true"), evaluatedWith: job, handler: nil)
        job.start()
        wait(for: [finishedExpectation], timeout: 10.0)

        XCTAssertTrue(job.isFinished)
        XCTAssertTrue(database.scanEvents.contains(where: { $0.type == .scanStarted }))
        XCTAssertTrue(database.scanEvents.contains(where: { $0.type == .noMatchFound }))
        XCTAssertTrue(database.optOutEvents.contains(where: { $0.type == .optOutStarted }))
        XCTAssertTrue(database.optOutEvents.contains(where: { $0.type == .optOutRequested }))
        XCTAssertTrue(database.optOutEvents.contains(where: { $0.type == .optOutConfirmed }))
    }

    // MARK: - Filtering Tests

    func testWhenFilteringOptOutOperationData_thenAllButFuturePreferredRunDateIsReturned() {
        let operationData1 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockOptOutQueryData, jobType: .optOut, priorityDate: nil)
        let operationData2 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockOptOutQueryData, jobType: .optOut, priorityDate: .now)
        let operationData3 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockOptOutQueryData, jobType: .optOut, priorityDate: .distantPast)
        let operationData4 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockOptOutQueryData, jobType: .optOut, priorityDate: .distantFuture)

        XCTAssertEqual(operationData1.count, 30) // all jobs
        XCTAssertEqual(operationData2.count, 20) // nil preferred run date + past jobs
        XCTAssertEqual(operationData3.count, 10) // nil preferred run date jobs
        XCTAssertEqual(operationData4.count, 30) // all jobs
    }

    func testWhenFilteringScanOperationData_thenPreferredRunDatePriorToPriorityDateIsReturned() {
        let operationData1 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockScanQueryData, jobType: .scheduledScan, priorityDate: nil)
        let operationData2 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockScanQueryData, jobType: .manualScan, priorityDate: .now)
        let operationData3 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockScanQueryData, jobType: .scheduledScan, priorityDate: .distantPast)
        let operationData4 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockScanQueryData, jobType: .manualScan, priorityDate: .distantFuture)

        XCTAssertEqual(operationData1.count, 30) // all jobs
        XCTAssertEqual(operationData2.count, 10) // past jobs
        XCTAssertEqual(operationData3.count, 0) // no jobs
        XCTAssertEqual(operationData4.count, 20) // past + future jobs
    }

    func testFilteringAllOperationData() {
        let operationData1 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockOptOutQueryData, jobType: .all, priorityDate: nil)
        let operationData2 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockOptOutQueryData, jobType: .all, priorityDate: .now)
        let operationData3 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockOptOutQueryData, jobType: .all, priorityDate: .distantPast)
        let operationData4 = MockBrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: mockOptOutQueryData, jobType: .all, priorityDate: .distantFuture)

        XCTAssertEqual(operationData1.filter { $0 is ScanJobData }.count, 30) // all jobs
        XCTAssertEqual(operationData1.filter { $0 is OptOutJobData }.count, 30) // all jobs
        XCTAssertEqual(operationData1.count, 30+30)

        XCTAssertEqual(operationData2.filter { $0 is ScanJobData }.count, 10) // past jobs
        XCTAssertEqual(operationData2.filter { $0 is OptOutJobData }.count, 20) // nil preferred run date + past jobs
        XCTAssertEqual(operationData2.count, 10+20)

        XCTAssertEqual(operationData3.filter { $0 is ScanJobData }.count, 0) // no jobs
        XCTAssertEqual(operationData3.filter { $0 is OptOutJobData }.count, 10) // nil preferred run date jobs
        XCTAssertEqual(operationData3.count, 0+10)

        XCTAssertEqual(operationData4.filter { $0 is ScanJobData }.count, 20) // past + future jobs
        XCTAssertEqual(operationData4.filter { $0 is OptOutJobData }.count, 30) // all jobs
        XCTAssertEqual(operationData4.count, 20+30)
    }

    func testSortPredicateForBackgroundTasks() {
            let now = Date()

            let jobs: [BrokerJobData] = [
                ScanJobData.mock(historyEvents: [HistoryEvent.mock(type: .matchesFound(count: 1))], preferredRunDate: now.addingTimeInterval(100)), // Maintenance
                OptOutJobData.mock(attemptCount: 10, preferredRunDate: now), // Opt-out
                ScanJobData.mock(historyEvents: [], preferredRunDate: now.addingTimeInterval(-100)), // Initial scan
                ScanJobData.mock(historyEvents: [HistoryEvent.mock(type: .scanStarted)], preferredRunDate: nil), // Other scan
                OptOutJobData.mock(attemptCount: 1, preferredRunDate: now.addingTimeInterval(50)), // Opt-out
                ScanJobData.mock(historyEvents: [HistoryEvent.mock(type: .optOutRequested)], preferredRunDate: now), // Confirm opt-out
                ScanJobData.mock(historyEvents: [HistoryEvent.mock(type: .error(error: DataBrokerProtectionError.unknown("Test error")))], preferredRunDate: now.addingTimeInterval(-50)), // Retry
                OptOutJobData.mock(attemptCount: 5, preferredRunDate: nil), // Opt-out
                ScanJobData.mock(historyEvents: [HistoryEvent.mock(type: .noMatchFound)], preferredRunDate: now.addingTimeInterval(-200)), // Maintenance
                ScanJobData.mock(historyEvents: [], preferredRunDate: nil), // Initial scan
                ScanJobData.mock(historyEvents: [HistoryEvent.mock(type: .error(error: DataBrokerProtectionError.unknown("Test error")))], preferredRunDate: now.addingTimeInterval(200)), // Retry
                ScanJobData.mock(historyEvents: [], preferredRunDate: now), // Initial scan
            ]

            let sorted = jobs.sorted(by: BrokerJobDataComparators.byPriorityForBackgroundTask)

            // 1. Initial scans (sorted by date, nil last)
            XCTAssertEqual((sorted[0] as? ScanJobData)?.scanType(), .initial)
            XCTAssertEqual(sorted[0].preferredRunDate, now.addingTimeInterval(-100))

            XCTAssertEqual((sorted[1] as? ScanJobData)?.scanType(), .initial)
            XCTAssertEqual(sorted[1].preferredRunDate, now)

            XCTAssertEqual((sorted[2] as? ScanJobData)?.scanType(), .initial)
            XCTAssertNil(sorted[2].preferredRunDate)

            // 2. Opt-outs (sorted by attempt count ascending: 1, 5, 10)
            XCTAssertEqual((sorted[3] as? OptOutJobData)?.attemptCount, 1)
            XCTAssertEqual((sorted[4] as? OptOutJobData)?.attemptCount, 5)
            XCTAssertEqual((sorted[5] as? OptOutJobData)?.attemptCount, 10)

            // 3. Confirm opt-out scans
            XCTAssertEqual((sorted[6] as? ScanJobData)?.scanType(), .confirmOptOut)

            // 4. Retry scans (sorted by date)
            XCTAssertEqual((sorted[7] as? ScanJobData)?.scanType(), .retry)
            XCTAssertEqual(sorted[7].preferredRunDate, now.addingTimeInterval(-50))

            XCTAssertEqual((sorted[8] as? ScanJobData)?.scanType(), .retry)
            XCTAssertEqual(sorted[8].preferredRunDate, now.addingTimeInterval(200))

            // 5. Maintenance scans (sorted by date)
            XCTAssertEqual((sorted[9] as? ScanJobData)?.scanType(), .maintenance)
            XCTAssertEqual(sorted[9].preferredRunDate, now.addingTimeInterval(-200))

            XCTAssertEqual((sorted[10] as? ScanJobData)?.scanType(), .maintenance)
            XCTAssertEqual(sorted[10].preferredRunDate, now.addingTimeInterval(100))

            // 6. Other scans
            XCTAssertEqual((sorted[11] as? ScanJobData)?.scanType(), .other)
            XCTAssertNil(sorted[11].preferredRunDate)
        }
}
