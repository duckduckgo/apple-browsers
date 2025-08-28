//
//  BrokerProfileJobDependencies.swift
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
import Common
import os.log
import BrowserServicesKit

public protocol BrokerProfileJobDependencyProviding {
    var database: DataBrokerProtectionRepository { get }
    var contentScopeProperties: ContentScopeProperties { get }
    var privacyConfig: PrivacyConfigurationManaging { get }
    var executionConfig: BrokerJobExecutionConfig { get }
    var notificationCenter: NotificationCenter { get }
    var pixelHandler: EventMapping<DataBrokerProtectionSharedPixels> { get }
    var eventsHandler: EventMapping<JobEvent> { get }
    var dataBrokerProtectionSettings: DataBrokerProtectionSettings { get }
    var emailService: EmailServiceProtocol { get }
    var captchaService: CaptchaServiceProtocol { get }
    var vpnBypassService: VPNBypassFeatureProvider? { get }
    var jobSortPredicate: BrokerJobDataComparators.Predicate { get }

    func createScanRunner(profileQuery: BrokerProfileQueryData,
                          stageDurationCalculator: StageDurationCalculator,
                          shouldRunNextStep: @escaping () -> Bool) -> BrokerProfileScanSubJobWebRunning

    func createOptOutRunner(profileQuery: BrokerProfileQueryData,
                            stageDurationCalculator: StageDurationCalculator,
                            shouldRunNextStep: @escaping () -> Bool) -> BrokerProfileOptOutSubJobWebRunning
}

public struct BrokerProfileJobDependencies: BrokerProfileJobDependencyProviding {
    public let database: DataBrokerProtectionRepository
    public let contentScopeProperties: ContentScopeProperties
    public let privacyConfig: PrivacyConfigurationManaging
    public var executionConfig: BrokerJobExecutionConfig
    public let notificationCenter: NotificationCenter
    public let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    public let eventsHandler: EventMapping<JobEvent>
    public let dataBrokerProtectionSettings: DataBrokerProtectionSettings
    public let emailService: EmailServiceProtocol
    public let captchaService: CaptchaServiceProtocol
    public let vpnBypassService: VPNBypassFeatureProvider?
    public let jobSortPredicate: BrokerJobDataComparators.Predicate

    public init(database: any DataBrokerProtectionRepository,
                contentScopeProperties: ContentScopeProperties,
                privacyConfig: PrivacyConfigurationManaging,
                executionConfig: BrokerJobExecutionConfig,
                notificationCenter: NotificationCenter,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                eventsHandler: EventMapping<JobEvent>,
                dataBrokerProtectionSettings: DataBrokerProtectionSettings,
                emailService: EmailServiceProtocol,
                captchaService: CaptchaServiceProtocol,
                vpnBypassService: VPNBypassFeatureProvider? = nil,
                jobSortPredicate: @escaping BrokerJobDataComparators.Predicate = BrokerJobDataComparators.default
    ) {
        self.database = database
        self.contentScopeProperties = contentScopeProperties
        self.privacyConfig = privacyConfig
        self.executionConfig = executionConfig
        self.notificationCenter = notificationCenter
        self.pixelHandler = pixelHandler
        self.eventsHandler = eventsHandler
        self.dataBrokerProtectionSettings = dataBrokerProtectionSettings
        self.emailService = emailService
        self.captchaService = captchaService
        self.vpnBypassService = vpnBypassService
        self.jobSortPredicate = jobSortPredicate
    }

    public func createScanRunner(profileQuery: BrokerProfileQueryData,
                                 stageDurationCalculator: StageDurationCalculator,
                                 shouldRunNextStep: @escaping () -> Bool) -> BrokerProfileScanSubJobWebRunning {
        return BrokerProfileScanSubJobWebRunner(
            privacyConfig: self.privacyConfig,
            prefs: self.contentScopeProperties,
            context: profileQuery,
            emailService: self.emailService,
            captchaService: self.captchaService,
            stageDurationCalculator: stageDurationCalculator,
            pixelHandler: self.pixelHandler,
            executionConfig: self.executionConfig,
            shouldRunNextStep: shouldRunNextStep
        )
    }

    public func createOptOutRunner(profileQuery: BrokerProfileQueryData,
                                   stageDurationCalculator: StageDurationCalculator,
                                   shouldRunNextStep: @escaping () -> Bool) -> BrokerProfileOptOutSubJobWebRunning {
        return BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: self.privacyConfig,
            prefs: self.contentScopeProperties,
            context: profileQuery,
            emailService: self.emailService,
            captchaService: self.captchaService,
            stageCalculator: stageDurationCalculator,
            pixelHandler: self.pixelHandler,
            executionConfig: self.executionConfig,
            shouldRunNextStep: shouldRunNextStep
        )
    }
}
