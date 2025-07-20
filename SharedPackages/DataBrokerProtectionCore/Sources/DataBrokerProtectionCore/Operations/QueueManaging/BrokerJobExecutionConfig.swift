//
//  BrokerJobExecutionConfig.swift
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

public struct BrokerJobExecutionConfig {

    public struct Constants {
        /// Minimum time interval between consecutive jobs for the same broker
        public static let defaultIntervalBetweenSameBrokerJobs: TimeInterval = .seconds(2)

        /// Maximum time allowed for a scan/opt-out job to complete
        #if os(iOS)
        public static let defaultScanJobTimeout: TimeInterval = .minutes(5)
        public static let defaultOptOutJobTimeout: TimeInterval = .minutes(5)
        #else
        public static let defaultScanJobTimeout: TimeInterval = .minutes(30)
        public static let defaultOptOutJobTimeout: TimeInterval = .minutes(30)
        #endif

        /// Maximum time allowed for a CSS action to complete before timing out
        public static let defaultCssActionTimeout: TimeInterval = .seconds(60)

        /// Interval for checking if a CSS action should be cancelled
        public static let defaultCssActionCancellationCheckInterval: TimeInterval = .seconds(1)
        /// Number of concurrent jobs allowed for different brokers
        public static let defaultConcurrentJobsDifferentBrokers: Int = 2
        /// Number of concurrent jobs allowed during manual scans
        public static let defaultConcurrentJobsOnManualScans: Int = 6
    }

    let intervalBetweenSameBrokerJobs: TimeInterval
    public let scanJobTimeout: TimeInterval
    public let optOutJobTimeout: TimeInterval
    public let cssActionTimeout: TimeInterval
    public let cssActionCancellationCheckInterval: TimeInterval

    private let concurrentJobsDifferentBrokers: Int
    // https://app.asana.com/0/481882893211075/1206981742767469/f
    private let concurrentJobsOnManualScans: Int
    func concurrentJobsFor(_ jobType: JobType) -> Int {
        switch jobType {
        case .all, .optOut, .scheduledScan:
            return concurrentJobsDifferentBrokers
        case .manualScan:
            return concurrentJobsOnManualScans
        }
    }

    public init(intervalBetweenSameBrokerJobs: TimeInterval = Constants.defaultIntervalBetweenSameBrokerJobs,
                scanJobTimeout: TimeInterval = Constants.defaultScanJobTimeout,
                optOutJobTimeout: TimeInterval = Constants.defaultOptOutJobTimeout,
                cssActionTimeout: TimeInterval = Constants.defaultCssActionTimeout,
                cssActionCancellationCheckInterval: TimeInterval = Constants.defaultCssActionCancellationCheckInterval,
                concurrentJobsDifferentBrokers: Int = Constants.defaultConcurrentJobsDifferentBrokers,
                concurrentJobsOnManualScans: Int = Constants.defaultConcurrentJobsOnManualScans) {
        self.intervalBetweenSameBrokerJobs = intervalBetweenSameBrokerJobs
        self.scanJobTimeout = scanJobTimeout
        self.optOutJobTimeout = optOutJobTimeout
        self.cssActionTimeout = cssActionTimeout
        self.cssActionCancellationCheckInterval = cssActionCancellationCheckInterval
        self.concurrentJobsDifferentBrokers = concurrentJobsDifferentBrokers
        self.concurrentJobsOnManualScans = concurrentJobsOnManualScans
    }
}
