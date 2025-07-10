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
    static let backgroundJobIdentifier = "com.duckduckgo.app.dbp.backgroundProcessing"

    struct Constants {
        static let defaultMaxWaitTime: TimeInterval = .hours(48)
        static let defaultMaxEligibleJobsPerBackgroundTask = 10
    }

    private let maxWaitTime: TimeInterval
    private let maxEligibleJobsPerBackgroundTask: Int
    private let database: DataBrokerProtectionRepository
    private let queueManager: BrokerProfileJobQueueManaging
    private let jobDependencies: BrokerProfileJobDependencyProviding
    private let iOSPixelsHandler: EventMapping<IOSPixels>
    private let validateRunPrerequisites: () async -> Bool

    public init(maxWaitTime: TimeInterval = Constants.defaultMaxWaitTime,
                maxEligibleJobsPerBackgroundTask: Int = Constants.defaultMaxEligibleJobsPerBackgroundTask,
                database: DataBrokerProtectionRepository,
                queueManager: BrokerProfileJobQueueManaging,
                jobDependencies: BrokerProfileJobDependencyProviding,
                iOSPixelsHandler: EventMapping<IOSPixels>,
                validateRunPrerequisites: @escaping () async -> Bool) {
        self.maxWaitTime = maxWaitTime
        self.maxEligibleJobsPerBackgroundTask = maxEligibleJobsPerBackgroundTask
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

        guard !eligibleJobs.isEmpty else {
            return maxWaitDate
        }

        let jobsToSchedule = Array(eligibleJobs.prefix(maxEligibleJobsPerBackgroundTask))
        guard let lastJobDate = jobsToSchedule.compactMap(\.preferredRunDate).last else {
            return date
        }

        return max(date, min(lastJobDate, maxWaitDate))
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
            let earliestBeginDate = try await calculateEarliestBeginDate()
            request.earliestBeginDate = earliestBeginDate

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
