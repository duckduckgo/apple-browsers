//
//  BrokerProfileJob.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation
import Common
import os.log
import BrowserServicesKit

public enum JobType {
    case manualScan
    case scheduledScan
    case optOut
    case all
}

public protocol BrokerProfileJobErrorDelegate: AnyObject {
    func dataBrokerOperationDidError(_ error: Error, withBrokerName brokerName: String?, version: String?)
}

public class BrokerProfileJob: Operation, @unchecked Sendable {

    private let dataBrokerID: Int64
    private let jobType: JobType
    private let priorityDate: Date? // The date to filter and sort operations priorities
    private let showWebView: Bool
    private(set) weak var errorDelegate: BrokerProfileJobErrorDelegate? // Internal read-only to enable mocking
    private let jobDependencies: BrokerProfileJobDependencyProviding

    private let id = UUID()
    private var _isExecuting = false
    private var _isFinished = false

    deinit {
        Logger.dataBrokerProtection.log("Deinit BrokerProfileJob: \(String(describing: self.id.uuidString), privacy: .public)")
    }

    init(dataBrokerID: Int64,
         jobType: JobType,
         priorityDate: Date? = nil,
         showWebView: Bool,
         errorDelegate: BrokerProfileJobErrorDelegate,
         jobDependencies: BrokerProfileJobDependencyProviding) {

        self.dataBrokerID = dataBrokerID
        self.priorityDate = priorityDate
        self.jobType = jobType
        self.showWebView = showWebView
        self.errorDelegate = errorDelegate
        self.jobDependencies = jobDependencies
        super.init()
    }

    public override func start() {
        if isCancelled {
            finish()
            return
        }

        willChangeValue(forKey: #keyPath(isExecuting))
        _isExecuting = true
        didChangeValue(forKey: #keyPath(isExecuting))

        main()
    }

    public override var isAsynchronous: Bool {
        return true
    }

    public override var isExecuting: Bool {
        return _isExecuting
    }

    public override var isFinished: Bool {
        return _isFinished
    }

    public override func main() {
        Task {
            await runJob()
            finish()
        }
    }

    public static func eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: [BrokerProfileQueryData], jobType: JobType, priorityDate: Date?) -> [BrokerJobData] {
        let jobsData: [BrokerJobData]

        Logger.dataBrokerProtection.log("🔍 eligibleJobsSortedByPreferredRunOrder - jobType: \(String(describing: jobType), privacy: .public), priorityDate: \(String(describing: priorityDate), privacy: .public)")
        Logger.dataBrokerProtection.log("🔍 Total brokerProfileQueriesData count: \(brokerProfileQueriesData.count, privacy: .public)")

        switch jobType {
        case .optOut:
            jobsData = brokerProfileQueriesData.flatMap { $0.optOutJobData }
            Logger.dataBrokerProtection.log("🔍 .optOut - found \(jobsData.count, privacy: .public) opt-out jobs")
        case .manualScan, .scheduledScan:
            jobsData = brokerProfileQueriesData.filter { $0.profileQuery.deprecated == false }.compactMap { $0.scanJobData }
            Logger.dataBrokerProtection.log("🔍 .scan - found \(jobsData.count, privacy: .public) scan jobs")
        case .all:
            jobsData = brokerProfileQueriesData.flatMap { $0.jobsData }
            let optOutCount = brokerProfileQueriesData.flatMap { $0.optOutJobData }.count
            let scanCount = brokerProfileQueriesData.compactMap { $0.scanJobData }.count
            Logger.dataBrokerProtection.log("🔍 .all - found \(jobsData.count, privacy: .public) total jobs (opt-outs: \(optOutCount, privacy: .public), scans: \(scanCount, privacy: .public))")
        }

        // Log job details before filtering
        for (index, queryData) in brokerProfileQueriesData.enumerated() {
            let brokerName = queryData.dataBroker.name
            for job in queryData.jobsData {
                if let optOut = job as? OptOutJobData {
                    Logger.dataBrokerProtection.log("🔍 Pre-filter OptOut - broker: \(brokerName, privacy: .public) (id:\(optOut.brokerId, privacy: .public)), preferredRunDate: \(String(describing: optOut.preferredRunDate), privacy: .public), lastRunDate: \(String(describing: optOut.lastRunDate), privacy: .public), isRemovedByUser: \(optOut.isRemovedByUser, privacy: .public)")
                } else if let scan = job as? ScanJobData {
                    Logger.dataBrokerProtection.log("🔍 Pre-filter Scan - broker: \(brokerName, privacy: .public) (id:\(scan.brokerId, privacy: .public)), preferredRunDate: \(String(describing: scan.preferredRunDate), privacy: .public)")
                }
            }
        }

        let filteredAndSortedJobData: [BrokerJobData]

        if let priorityDate = priorityDate {
            let beforeFilter = jobsData.count
            filteredAndSortedJobData = jobsData
                .filteredByNilOrEarlierPreferredRunDateThan(date: priorityDate)
                .sortedByEarliestPreferredRunDateFirst()
            Logger.dataBrokerProtection.log("🔍 Filtered by priorityDate - before: \(beforeFilter, privacy: .public), after: \(filteredAndSortedJobData.count, privacy: .public)")
        } else {
            let beforeFilter = jobsData.count
            filteredAndSortedJobData = jobsData
                .excludingUserRemoved()
            Logger.dataBrokerProtection.log("🔍 Filtered excludingUserRemoved - before: \(beforeFilter, privacy: .public), after: \(filteredAndSortedJobData.count, privacy: .public)")
        }

        // Log filtered results
        Logger.dataBrokerProtection.log("🔍 Final filtered job count: \(filteredAndSortedJobData.count, privacy: .public)")
        
        // Need to map back to broker names for filtered results
        for job in filteredAndSortedJobData {
            if let optOut = job as? OptOutJobData {
                let brokerName = brokerProfileQueriesData.first { queryData in
                    queryData.optOutJobData.contains { $0.brokerId == optOut.brokerId && $0.profileQueryId == optOut.profileQueryId }
                }?.dataBroker.name ?? "Unknown"
                Logger.dataBrokerProtection.log("🔍 Post-filter OptOut selected - broker: \(brokerName, privacy: .public) (id:\(optOut.brokerId, privacy: .public)), preferredRunDate: \(String(describing: optOut.preferredRunDate), privacy: .public)")
            } else if let scan = job as? ScanJobData {
                let brokerName = brokerProfileQueriesData.first { queryData in
                    queryData.scanJobData.brokerId == scan.brokerId && queryData.scanJobData.profileQueryId == scan.profileQueryId
                }?.dataBroker.name ?? "Unknown"
                Logger.dataBrokerProtection.log("🔍 Post-filter Scan selected - broker: \(brokerName, privacy: .public) (id:\(scan.brokerId, privacy: .public))")
            }
        }

        return filteredAndSortedJobData
    }

    private func runJob() async {
        let allBrokerProfileQueryData: [BrokerProfileQueryData]

        do {
            allBrokerProfileQueryData = try jobDependencies.database.fetchAllBrokerProfileQueryData()
        } catch {
            Logger.dataBrokerProtection.error("DataBrokerOperationsCollection error: runOperation, error: \(error.localizedDescription, privacy: .public)")
            return
        }

        let brokerProfileQueriesData = allBrokerProfileQueryData.filter { $0.dataBroker.id == dataBrokerID }
        
        let brokerName = brokerProfileQueriesData.first?.dataBroker.name ?? "Unknown"
        Logger.dataBrokerProtection.log("🎯 BrokerProfileJob.runJob() - Processing broker: \(brokerName, privacy: .public) (id:\(self.dataBrokerID, privacy: .public))")

        let filteredAndSortedJobData = Self.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: brokerProfileQueriesData,
                                                                                  jobType: jobType,
                                                                                  priorityDate: priorityDate)

        Logger.dataBrokerProtection.log("🎯 filteredAndSortedOperationsData count: \(filteredAndSortedJobData.count, privacy: .public) for broker: \(brokerName, privacy: .public) (id:\(self.dataBrokerID, privacy: .public))")

        for jobData in filteredAndSortedJobData {
            if isCancelled {
                Logger.dataBrokerProtection.log("Cancelled operation, returning...")
                return
            }

            let brokerProfileData = brokerProfileQueriesData.filter {
                $0.dataBroker.id == jobData.brokerId && $0.profileQuery.id == jobData.profileQueryId
            }.first

            guard let brokerProfileData = brokerProfileData else {
                continue
            }

            do {
                Logger.dataBrokerProtection.log("Running operation: \(String(describing: jobData), privacy: .public)")

                if jobData is ScanJobData {
                    try await withTimeout(jobDependencies.executionConfig.scanJobTimeout) { [self] in
                        try await BrokerProfileScanSubJob(dependencies: jobDependencies).runScan(
                            brokerProfileQueryData: brokerProfileData,
                            showWebView: showWebView,
                            isManual: jobType == .manualScan,
                            shouldRunNextStep: { [weak self] in
                                guard let self = self else { return false }
                                return !self.isCancelled && !Task.isCancelled
                            })
                    }
                } else if let optOutJobData = jobData as? OptOutJobData {
                    try await withTimeout(jobDependencies.executionConfig.optOutJobTimeout) { [self] in
                        try await BrokerProfileOptOutSubJob(dependencies: jobDependencies).runOptOut(
                            for: optOutJobData.extractedProfile,
                            brokerProfileQueryData: brokerProfileData,
                            showWebView: showWebView,
                            shouldRunNextStep: { [weak self] in
                                guard let self = self else { return false }
                                return !self.isCancelled && !Task.isCancelled
                            })
                    }
                } else {
                    assertionFailure("Unsupported job data type")
                }

                let sleepInterval = jobDependencies.executionConfig.intervalBetweenSameBrokerJobs
                Logger.dataBrokerProtection.log("Waiting...: \(sleepInterval, privacy: .public)")
                try await Task.sleep(nanoseconds: UInt64(sleepInterval) * 1_000_000_000)
            } catch {
                Logger.dataBrokerProtection.error("Error: \(error.localizedDescription, privacy: .public)")

                errorDelegate?.dataBrokerOperationDidError(error,
                                                           withBrokerName: brokerProfileQueriesData.first?.dataBroker.name,
                                                           version: brokerProfileQueriesData.first?.dataBroker.version)
            }
        }

        finish()
    }

    private func finish() {
        willChangeValue(forKey: #keyPath(isExecuting))
        willChangeValue(forKey: #keyPath(isFinished))

        _isExecuting = false
        _isFinished = true

        didChangeValue(forKey: #keyPath(isExecuting))
        didChangeValue(forKey: #keyPath(isFinished))

        Logger.dataBrokerProtection.log("Finished operation: \(self.id.uuidString, privacy: .public)")
    }
}

extension Array where Element == BrokerJobData {
    /// Filters jobs based on their preferred run date:
    /// - Opt-out jobs with no preferred run date and not manually removed by users (using "This isn't me") are included.
    /// - Jobs with a preferred run date on or before the priority date are included.
    ///
    /// Note: Opt-out jobs without a preferred run date may be:
    /// 1. From child brokers (will be skipped during runOptOut).
    /// 2. From former child brokers now acting as parent brokers (will be processed if extractedProfile hasn't been removed).
    public func filteredByNilOrEarlierPreferredRunDateThan(date priorityDate: Date) -> [BrokerJobData] {
        filter { jobData in
            guard let preferredRunDate = jobData.preferredRunDate else {
                return jobData is OptOutJobData && !jobData.isRemovedByUser
            }

            return preferredRunDate <= priorityDate
        }
    }

    /// Sorts BrokerJobData array based on their preferred run dates.
    /// - Jobs with non-nil preferred run dates are sorted in ascending order (earliest date first).
    /// - Opt-out jobs with nil preferred run dates come last, maintaining their original relative order.
    public func sortedByEarliestPreferredRunDateFirst() -> [BrokerJobData] {
        sorted { lhs, rhs in
            switch (lhs.preferredRunDate, rhs.preferredRunDate) {
            case (nil, nil):
                return false
            case (_, nil):
                return true
            case (nil, _):
                return false
            case (let lhsRunDate?, let rhsRunDate?):
                return lhsRunDate < rhsRunDate
            }
        }
    }

    public func excludingUserRemoved() -> [BrokerJobData] {
        filter { !$0.isRemovedByUser }
    }
}
