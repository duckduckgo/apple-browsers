//
//  DBPVaultResources.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import DataBrokerProtectionCore

final class DBPVaultResources {
    let database: DataBrokerProtectionRepository
    var queueManager: JobQueueManaging
    let jobDependencies: BrokerProfileJobDependencyProviding
    let emailConfirmationDataService: EmailConfirmationDataServiceProvider
    private let brokerUpdaterProvider: () -> BrokerJSONServiceProvider?

    private let engagementPixelsRepository: DataBrokerProtectionEngagementPixelsRepository

    lazy var brokerUpdater = brokerUpdaterProvider()
    lazy var engagementPixels = DataBrokerProtectionEngagementPixels(
        database: jobDependencies.database,
        handler: jobDependencies.pixelHandler,
        repository: engagementPixelsRepository
    )
    lazy var eventPixels = DataBrokerProtectionEventPixels(
        database: jobDependencies.database,
        handler: jobDependencies.pixelHandler
    )
    lazy var statsPixels = DataBrokerProtectionStatsPixels(
        database: jobDependencies.database,
        handler: jobDependencies.pixelHandler
    )

    init(database: DataBrokerProtectionRepository,
         queueManager: JobQueueManaging,
         jobDependencies: BrokerProfileJobDependencyProviding,
         emailConfirmationDataService: EmailConfirmationDataServiceProvider,
         brokerUpdaterProvider: @escaping () -> BrokerJSONServiceProvider?,
         engagementPixelsRepository: DataBrokerProtectionEngagementPixelsRepository) {
        self.database = database
        self.queueManager = queueManager
        self.jobDependencies = jobDependencies
        self.emailConfirmationDataService = emailConfirmationDataService
        self.brokerUpdaterProvider = brokerUpdaterProvider
        self.engagementPixelsRepository = engagementPixelsRepository
    }
}
