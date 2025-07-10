//
//  BackgroundTaskScheduler.swift
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

import Foundation
import DataBrokerProtectionCore
import BackgroundTasks
import Common
import os.log
import BrowserServicesKit

public final class BackgroundTaskScheduler {
    public static let backgroundJobIdentifier = "com.duckduckgo.app.dbp.backgroundProcessing"

    public struct Constants {
        public static let defaultMaxWaitTime: TimeInterval = .hours(48)
        public static let defaultMinWaitTime: TimeInterval = .minutes(15)
    }

    private let maxWaitTime: TimeInterval
    private let minWaitTime: TimeInterval
    private let database: DataBrokerProtectionRepository
    private let queueManager: BrokerProfileJobQueueManaging
    private let jobDependencies: BrokerProfileJobDependencyProviding
    private let iOSPixelsHandler: EventMapping<IOSPixels>
    private let validateRunPrerequisites: () async -> Bool

    public init(maxWaitTime: TimeInterval = Constants.defaultMaxWaitTime,
                minWaitTime: TimeInterval = Constants.defaultMinWaitTime,
                database: DataBrokerProtectionRepository,
                queueManager: BrokerProfileJobQueueManaging,
                jobDependencies: BrokerProfileJobDependencyProviding,
                iOSPixelsHandler: EventMapping<IOSPixels>,
                validateRunPrerequisites: @escaping () async -> Bool) {
        self.maxWaitTime = maxWaitTime
        self.minWaitTime = minWaitTime
        self.database = database
        self.queueManager = queueManager
        self.jobDependencies = jobDependencies
        self.iOSPixelsHandler = iOSPixelsHandler
        self.validateRunPrerequisites = validateRunPrerequisites
    }

    public func calculateEarliestBeginDate(from date: Date = .init()) async throws -> Date {
        let allBrokerProfileQueryData = try database.fetchAllBrokerProfileQueryData()
        let maxWaitDate = date.addingTimeInterval(maxWaitTime)

        let eligibleJobs = BrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(
            brokerProfileQueriesData: allBrokerProfileQueryData,
            jobType: .all,
            priorityDate: maxWaitDate
        ).sortedByEarliestPreferredRunDateFirst()

        let firstJobDate = eligibleJobs.first?.preferredRunDate
        return calculateEarliestBeginDate(from: date, firstEligibleJobDate: firstJobDate)
    }
    
    public func calculateEarliestBeginDate(from date: Date, firstEligibleJobDate: Date?) -> Date {
        let maxWaitDate = date.addingTimeInterval(maxWaitTime)
        
        guard let jobDate = firstEligibleJobDate else {
            // No eligible jobs
            return maxWaitDate
        }
        
        let minWaitDate = date.addingTimeInterval(minWaitTime)
        
        // If overdue → ASAP
        if jobDate <= date {
            return date
        }
        
        // Otherwise → clamp to [minWaitTime, maxWaitTime]
        return min(max(jobDate, minWaitDate), maxWaitDate)
    }

    public func registerBackgroundTaskHandler() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundJobIdentifier, using: nil) { [weak self] task in
            self?.handleBGProcessingTask(task: task)
        }
    }

    public func scheduleBGProcessingTask() {
        Task {
            guard await validateRunPrerequisites() else {
                Logger.dataBrokerProtection.log("Prerequisites are invalid during scheduling of background task")
                return
            }
            
            let request = BGProcessingTaskRequest(identifier: Self.backgroundJobIdentifier)
            request.requiresNetworkConnectivity = true

            let currentDate = Date()
            
            var start = CFAbsoluteTimeGetCurrent()
            let earliestBeginDate = try await calculateEarliestBeginDate(from: currentDate)
            let diff = CFAbsoluteTimeGetCurrent() - start
            Logger.dataBrokerProtection.log("Earliest begin date calculation took \(diff) seconds: \(earliestBeginDate)")

            // Compare with new database calculation
            start = CFAbsoluteTimeGetCurrent()
            let dbFirstJobDate = try database.fetchFirstEligibleJobDate()
            let dbDiff = CFAbsoluteTimeGetCurrent() - start
            
            let dbEarliestBeginDate = calculateEarliestBeginDate(from: currentDate, firstEligibleJobDate: dbFirstJobDate)
            
            Logger.dataBrokerProtection.log("Database earliest begin date calculation took \(dbDiff) seconds: \(dbEarliestBeginDate)")
            Logger.dataBrokerProtection.log("Time difference: \(diff - dbDiff) seconds (positive means DB is faster)")
            Logger.dataBrokerProtection.log("Date difference: \(dbEarliestBeginDate.timeIntervalSince(earliestBeginDate)) seconds")
            
            request.earliestBeginDate = earliestBeginDate
            Logger.dataBrokerProtection.log("PIR Background Task: Scheduling next task for \(earliestBeginDate)")

#if !targetEnvironment(simulator)
            do {
                try BGTaskScheduler.shared.submit(request)
                Logger.dataBrokerProtection.log("Scheduling background task successful")
            } catch {
                Logger.dataBrokerProtection.log("Scheduling background task failed with error: \(error)")
// This should never ever go to production due to the deviceID and only exists for internal testing as long as PIR isn't public on iOS
                self.iOSPixelsHandler.fire(.backgroundTaskSchedulingFailed(error: error, deviceID: DataBrokerProtectionSettings.deviceIdentifier))
            }
#endif
        }
    }

    private func handleBGProcessingTask(task: BGTask) {
        Logger.dataBrokerProtection.log("Background task started")
// This should never ever go to production due to the deviceID and only exists for internal testing as long as PIR isn't public on iOS
        iOSPixelsHandler.fire(.backgroundTaskStarted(deviceID: DataBrokerProtectionSettings.deviceIdentifier))
        let startTime = Date.now

        task.expirationHandler = { [weak self] in
            self?.queueManager.stop()

            let timeTaken = Date.now.timeIntervalSince(startTime)
            Logger.dataBrokerProtection.log("Background task expired with time taken: \(timeTaken)")
// This should never ever go to production due to the deviceID and only exists for internal testing as long as PIR isn't public on iOS
            self?.iOSPixelsHandler.fire(.backgroundTaskExpired(duration: timeTaken * 1000.0,
                                                              deviceID: DataBrokerProtectionSettings.deviceIdentifier))
            self?.scheduleBGProcessingTask()
            task.setTaskCompleted(success: false)
        }

        Task {
            guard await validateRunPrerequisites() else {
                Logger.dataBrokerProtection.log("Prerequisites are invalid during background task")
                task.setTaskCompleted(success: false)
                return
            }
            queueManager.startScheduledAllOperationsIfPermitted(showWebView: false, jobDependencies: jobDependencies, errorHandler: nil) { [weak self] in
                Logger.dataBrokerProtection.log("All operations completed in background task")
                let timeTaken = Date.now.timeIntervalSince(startTime)
                Logger.dataBrokerProtection.log("Background task finshed all operations with time taken: \(timeTaken)")
// This should never ever go to production due to the deviceID and only exists for internal testing as long as PIR isn't public on iOS
                self?.iOSPixelsHandler.fire(.backgroundTaskEndedHavingCompletedAllJobs(
                    duration: timeTaken * 1000.0,
                    deviceID: DataBrokerProtectionSettings.deviceIdentifier))

                self?.scheduleBGProcessingTask()
                task.setTaskCompleted(success: true)
            }
        }
    }
}
