//
//  BrokerProfileJobProvider.swift
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

import Common
import Foundation

public protocol BrokerProfileJobProviding {
    func createJobs(with jobType: JobType,
                    withPriorityDate priorityDate: Date?,
                    showWebView: Bool,
                    errorDelegate: BrokerProfileJobErrorDelegate,
                    jobDependencies: BrokerProfileJobDependencyProviding) throws -> [BrokerProfileJob]
}

public final class BrokerProfileJobProvider: BrokerProfileJobProviding {

    public init() {}

    public func createJobs(with jobType: JobType,
                           withPriorityDate priorityDate: Date?,
                           showWebView: Bool,
                           errorDelegate: BrokerProfileJobErrorDelegate,
                           jobDependencies: BrokerProfileJobDependencyProviding) throws -> [BrokerProfileJob] {

        let brokerProfileQueryData = try jobDependencies.database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true)
        var jobs: [BrokerProfileJob] = []
        var visitedDataBrokerIDs: Set<Int64> = []

        for queryData in brokerProfileQueryData {
            guard let dataBrokerID = queryData.dataBroker.id else { continue }

            if !visitedDataBrokerIDs.contains(dataBrokerID) {
                let job = BrokerProfileJob(dataBrokerID: dataBrokerID,
                                           jobType: jobType,
                                           priorityDate: priorityDate,
                                           showWebView: showWebView,
                                           errorDelegate: errorDelegate,
                                           jobDependencies: jobDependencies)
                jobs.append(job)
                visitedDataBrokerIDs.insert(dataBrokerID)
            }
        }

        return jobs
    }
}
