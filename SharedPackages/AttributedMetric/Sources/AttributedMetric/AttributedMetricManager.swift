//
//  AttributedMetricManager.swift
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
//

import Foundation
import PixelKit
import Combine
import PrivacyConfig
import os.log

/// macOS: `SystemDefaultBrowserProvider`
/// iOS: `DefaultBrowserManager` limited to 4 times p/y, cached value
public protocol AttributedMetricDefaultBrowserProviding {
    var isDefaultBrowser: Bool { get }
}

public protocol SubscriptionStateProviding {
    func isFreeTrial() async -> Bool
    var isActive: Bool { get }
}

public protocol DateProviding {
    func now() -> Date
    var debugDate: Date? { get set }
}

public class DefaultDateProvider: DateProviding {
    public init() {}

    public func now() -> Date {
        if let debugOverride = debugDate {
            return debugOverride
        } else {
            return Date()
        }
    }

    public var debugDate: Date?
}

public protocol AttributedMetricSettingsProviding {
    var bucketsSettings: [String: Any] { get }
    var originSendList: [String] { get }
}

/// https://app.asana.com/1/137249556945/project/1205842942115003/task/1210884473312053?focus=true
public final class AttributedMetricManager {

    struct Constants {
        static let monthTimeInterval: TimeInterval = Double(Constants.daysInAMonth) * .day
        static let daysInAMonth: Int = 28
    }

    private let pixelKit: PixelKit?
    private var dataStorage: any AttributedMetricDataStoring
    private let originProvider: (any AttributedMetricOriginProvider)?
    private let featureFlagger: any FeatureFlagger
    private let defaultBrowserProvider: any AttributedMetricDefaultBrowserProviding
    private let subscriptionStateProvider: any SubscriptionStateProviding
    private var dateProvider: any DateProviding
    private let featureSettings: any AttributedMetricSettingsProviding
    private var bucketModifier: any BucketModifier = DefaultBucketModifier()
    public let workQueue = DispatchQueue(label: "com.duckduckgo.AttributedMetricManager", qos: .background)
    public var cancellables = Set<AnyCancellable>()

    public init(pixelKit: PixelKit?,
                dataStoring: any AttributedMetricDataStoring,
                featureFlagger: any FeatureFlagger,
                originProvider: (any AttributedMetricOriginProvider)?,
                defaultBrowserProviding: any AttributedMetricDefaultBrowserProviding,
                subscriptionStateProvider: any SubscriptionStateProviding,
                dateProvider: any DateProviding = DefaultDateProvider(),
                settingsProvider: any AttributedMetricSettingsProviding) {
        self.pixelKit = pixelKit
        self.dataStorage = dataStoring
        self.originProvider = originProvider
        self.featureFlagger = featureFlagger
        self.defaultBrowserProvider = defaultBrowserProviding
        self.subscriptionStateProvider = subscriptionStateProvider
        self.dateProvider = dateProvider

        // Buckets
        self.featureSettings = settingsProvider
        updateBucketSettings()

        if dataStorage.installDate == nil {
            dataStorage.installDate = self.dateProvider.now()
        }

        if let debugDate = dataStorage.debugDate {
            self.dateProvider.debugDate = debugDate
        }
    }

    // MARK: - Private

    var isEnabled: Bool {
        featureFlagger.isFeatureOn(for: AttributedMetricFeatureFlag.attributedMetrics)
    }

    var daysSinceInstalled: Int {
        guard let installDate = dataStorage.installDate else {
            return 0
        }
        return Int(dateProvider.now().timeIntervalSince(installDate) / .day)
    }

    var timePastFromInstall: QuantisedTimePast? {
        guard let installDate = dataStorage.installDate else {
            Logger.attributedMetric.error("Install date missing")
            return nil
        }
        let now = dateProvider.now()
        return QuantisedTimePast.timePastFrom(date: now, andInstallationDate: installDate)
    }

    var originOrInstall: (origin: String?, installDate: String?) {
        if let origin = dataStorage.debugOrigin ?? originProvider?.origin,
           origin.containsAny(of: self.featureSettings.originSendList) {
            return (origin, nil)
        } else {
            let installDate = dataStorage.installDate
            return (nil, installDate?.ISO8601ETFormat())
        }
    }

    var isDefaultBrowser: Bool { defaultBrowserProvider.isDefaultBrowser }

    var isLessThanSixMonths: Bool {
        guard let installDate = dataStorage.installDate else {
            return true
        }
        let days = Constants.daysInAMonth * 6
        return installDate > self.dateProvider.now().addingTimeInterval(Double(-days) * TimeInterval.day)
    }

    var isSameDayOfInstallDate: Bool {
        guard let installDate = dataStorage.installDate else {
            return false
        }
        return Calendar.eastern.isDate(dateProvider.now(), inSameDayAs: installDate)
    }

    // MARK: - Buckets settings

    public func updateBucketSettings() {
        do {
            try bucketModifier.parseConfigurations(from: self.featureSettings.bucketsSettings)
        } catch {
            Logger.attributedMetric.fault("Failed to parse buckets settings: \(error, privacy: .public)")
            assertionFailure("Failed to parse buckets settings: \(error)")
        }
    }

    // MARK: - Triggers

    public enum Trigger: CustomDebugStringConvertible {
        case appDidStart
        case userDidSearch
        case userDidSelectAD
        case userDidDuckAIChat
        case userDidSubscribe
        case userDidSync(devicesCount: Int)

        public var debugDescription: String {
            switch self {
            case .appDidStart:
                "AppDidStart"
            case .userDidSearch:
                "UserDidSearch"
            case .userDidSelectAD:
                "UserDidSelectAD"
            case .userDidDuckAIChat:
                "UserDidDuckAIChat"
            case .userDidSubscribe:
                "UserDidSubscribe"
            case .userDidSync:
                "UserDidSync"
            }
        }
    }

    public func process(trigger: Trigger) {
        Logger.attributedMetric.log("Processing \(trigger.debugDescription, privacy: .public)")
        guard isEnabled else {
            Logger.attributedMetric.log("Feature disabled")
            return
        }

        guard isLessThanSixMonths else {
            dataStorage.removeAll()
            return
        }

        switch trigger {
        case .appDidStart:
            processRetention()
            processActiveSearchDays()
            processSubscriptionCheck()
        case .userDidSearch:
            recordActiveSearchDay()
            processAverageSearchCount()
        case .userDidSelectAD:
            recordAdClick()
            processAverageAdClick()
        case .userDidDuckAIChat:
            recordDuckAIChat()
            processAverageDuckAIChat()
        case .userDidSubscribe:
            processSubscriptionDay()
        case .userDidSync(devicesCount: let devicesCount):
            processSyncCheck(devicesCount: devicesCount)
        }
    }

    // MARK: - Retention
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929607?focus=true
    func processRetention() {
        guard let timePastFromInstall = timePastFromInstall else { return }
        let lastRetentionThreshold = dataStorage.lastRetentionThreshold
        guard lastRetentionThreshold != timePastFromInstall else {
            Logger.attributedMetric.error("Threshold not changed")
            return
        }
        dataStorage.lastRetentionThreshold = timePastFromInstall
        switch timePastFromInstall {
        case .none:
            Logger.attributedMetric.log("Less than a week from installation")
        case .weeks(let week):
            Logger.attributedMetric.log("\(week, privacy: .public) week(s) from installation")
            guard let bucket = try? bucketModifier.bucket(value: week, pixelName: .userRetentionWeek) else {
                Logger.attributedMetric.error("Failed to bucket week value")
                return
            }
            pixelKit?.fire(AttributedMetricPixel.userRetentionWeek(origin: originOrInstall.origin,
                                                                   installDate: originOrInstall.installDate,
                                                                   defaultBrowser: isDefaultBrowser,
                                                                   count: bucket.value,
                                                                   bucketVersion: bucket.version),
                           frequency: .legacyDailyNoSuffix,
                           includeAppVersionParameter: false)
        case .months(let month):
            Logger.attributedMetric.log("\(month, privacy: .public) month(s) from installation")
            guard let bucket = try? bucketModifier.bucket(value: month, pixelName: .userRetentionMonth) else {
                Logger.attributedMetric.error("Failed to bucket month value")
                return
            }
            pixelKit?.fire(AttributedMetricPixel.userRetentionMonth(origin: originOrInstall.origin,
                                                                    installDate: originOrInstall.installDate,
                                                                    defaultBrowser: isDefaultBrowser,
                                                                    count: bucket.value,
                                                                    bucketVersion: bucket.version),
                           frequency: .legacyDailyNoSuffix,
                           includeAppVersionParameter: false)
        }
    }

    // MARK: - Active search days
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929609?focus=true

    func recordActiveSearchDay() {
        Logger.attributedMetric.log("Recording active search day")
        let search8Days = dataStorage.search8Days
        search8Days.increment(dateProvider: dateProvider)
        dataStorage.search8Days = search8Days
    }

    func processActiveSearchDays() {
        Logger.attributedMetric.log("Processing active search days")
        let daysSinceInstalled = daysSinceInstalled
        var addDaysSinceInstalled: Bool = false
        switch daysSinceInstalled {
        case 0:
            return
        case 1...7:
            addDaysSinceInstalled = true
        default:
            addDaysSinceInstalled = false
        }

        let search8Days = dataStorage.search8Days
        let searchCount = search8Days.countPast7Days
        guard searchCount > 0 else { return }
        Logger.attributedMetric.log("\(searchCount, privacy: .public) searches performed in the last week")
        guard let bucket = try? bucketModifier.bucket(value: searchCount, pixelName: .userActivePastWeek) else {
            Logger.attributedMetric.error("Failed to bucket search count value")
            return
        }
        pixelKit?.fire(AttributedMetricPixel.userActivePastWeek(origin: originOrInstall.origin,
                                                                installDate: originOrInstall.installDate,
                                                                days: bucket.value,
                                                                daysSinceInstalled: addDaysSinceInstalled ? daysSinceInstalled : nil,
                                                                bucketVersion: bucket.version),
                       frequency: .legacyDailyNoSuffix,
                       includeAppVersionParameter: false)
    }

    // MARK: - Average searches
    // https://app.asana.com/1/137249556945/project/1205842942115003/task/1211313432282643?focus=true

    func processAverageSearchCount() {
        Logger.attributedMetric.log("Calculating average search count")
        guard let timePastFromInstall = timePastFromInstall else { return }
        let search8Days = dataStorage.search8Days
        let average = search8Days.past7DaysAverage

        guard average > 0 else { return }

        switch timePastFromInstall {
        case .none:
            return
        case .weeks:
            guard let bucket = try? bucketModifier.bucket(value: average, pixelName: .userAverageSearchesPastWeekFirstMonth) else {
                Logger.attributedMetric.error("Failed to bucket average search count value")
                return
            }
            Logger.attributedMetric.debug("Average last week (first month) search count: \(average, privacy: .public), bucket: \(bucket.value, privacy: .public)")
            pixelKit?.fire(AttributedMetricPixel.userAverageSearchesPastWeekFirstMonth(origin: originOrInstall.origin,
                                                                                       installDate: originOrInstall.installDate,
                                                                                       count: bucket.value,
                                                                                       bucketVersion: bucket.version),
                           frequency: .legacyDailyNoSuffix,
                           includeAppVersionParameter: false)
        case .months:
            guard let bucket = try? bucketModifier.bucket(value: average, pixelName: .userAverageSearchesPastWeek) else {
                Logger.attributedMetric.error("Failed to bucket average search count value")
                return
            }
            Logger.attributedMetric.debug("Average last week search count: \(average, privacy: .public), bucket: \(bucket.value, privacy: .public)")
            pixelKit?.fire(AttributedMetricPixel.userAverageSearchesPastWeek(origin: originOrInstall.origin,
                                                                             installDate: originOrInstall.installDate,
                                                                             count: bucket.value,
                                                                             bucketVersion: bucket.version),
                           frequency: .legacyDailyNoSuffix,
                           includeAppVersionParameter: false)
        }
    }

    // MARK: - Average AD clicks
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929610?focus=true

    func recordAdClick() {
        Logger.attributedMetric.log("Record AD click")
        let adClick8Days = dataStorage.adClick8Days
        adClick8Days.increment(dateProvider: dateProvider)
        dataStorage.adClick8Days = adClick8Days
    }

    func processAverageAdClick() {
        Logger.attributedMetric.log("Process average AD click")
        guard !isSameDayOfInstallDate else { return }

        let adClick8Days = dataStorage.adClick8Days
        guard adClick8Days.countPast7Days > 0 else { return }
        let average = adClick8Days.past7DaysAverage
        guard let bucket = try? bucketModifier.bucket(value: average, pixelName: .userAverageAdClicksPastWeek) else {
            Logger.attributedMetric.error("Failed to bucket average AD click value")
            return
        }
        Logger.attributedMetric.log("Average AD click count in the last week: \(bucket.value, privacy: .public)")
        pixelKit?.fire(AttributedMetricPixel.userAverageAdClicksPastWeek(origin: originOrInstall.origin,
                                                                         installDate: originOrInstall.installDate,
                                                                         count: bucket.value,
                                                                         bucketVersion: bucket.version),
                       frequency: .legacyDailyNoSuffix,
                       includeAppVersionParameter: false)
    }

    // MARK: - Average Duck.ai chats
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929612?focus=true

    func recordDuckAIChat() {
        Logger.attributedMetric.log("Record DuckAI chat")
        let duckAIChat8Days = dataStorage.duckAIChat8Days
        duckAIChat8Days.increment(dateProvider: dateProvider)
        dataStorage.duckAIChat8Days = duckAIChat8Days
    }

    func processAverageDuckAIChat() {
        Logger.attributedMetric.log("Process average DuckAI chat")
        guard !isSameDayOfInstallDate else { return }

        let duckAIChat8Days = dataStorage.duckAIChat8Days
        guard duckAIChat8Days.countPast7Days > 0 else { return }
        let average = duckAIChat8Days.past7DaysAverage
        guard let bucket = try? bucketModifier.bucket(value: average, pixelName: .userAverageDuckAiUsagePastWeek) else {
            Logger.attributedMetric.error("Failed to bucket average Duck.AI chat value")
            return
        }
        Logger.attributedMetric.log("Average Duck.AI chats count in the last week: \(bucket.value, privacy: .public)")
        pixelKit?.fire(AttributedMetricPixel.userAverageDuckAiUsagePastWeek(origin: originOrInstall.origin,
                                                                            installDate: originOrInstall.installDate,
                                                                            count: bucket.value,
                                                                            bucketVersion: bucket.version),
                       frequency: .legacyDailyNoSuffix,
                       includeAppVersionParameter: false)
    }

    // MARK: - Subscription
    // https://app.asana.com/1/137249556945/project/1205842942115003/task/1211301604929613?focus=true

    func processSubscriptionDay() {

        Logger.attributedMetric.log("Processing subscription purchase")
        guard dataStorage.subscriptionDate == nil else { return }
        dataStorage.subscriptionDate = dateProvider.now()

        Task {
            let isFreeTrial = await subscriptionStateProvider.isFreeTrial()
            if isFreeTrial  {
                dataStorage.subscriptionFreeTrialFired = true
            } else {
                dataStorage.subscriptionMonth1Fired = true
            }

            let month = isFreeTrial ? 0 : 1
            guard let bucket = try? bucketModifier.bucket(value: month, pixelName: .userSubscribed) else {
                Logger.attributedMetric.error("Failed to bucket month value")
                return
            }
            pixelKit?.fire(AttributedMetricPixel.userSubscribed(origin: originOrInstall.origin,
                                                                installDate: originOrInstall.installDate,
                                                                month: bucket.value,
                                                                bucketVersion: bucket.version),
                           frequency: .legacyDailyNoSuffix,
                           includeAppVersionParameter: false)
        }
    }

    func processSubscriptionCheck() {
        Task {
            guard let subscriptionDate = dataStorage.subscriptionDate,
                  subscriptionStateProvider.isActive
             else {
                Logger.attributedMetric.log("Not subscribed or subscription date is missing")
                return
            }

            let now = dateProvider.now()
            let freeTrialPixelSent = dataStorage.subscriptionFreeTrialFired
            let firstMonthPixelSent = dataStorage.subscriptionMonth1Fired
            let isFreeTrial = await subscriptionStateProvider.isFreeTrial()
            let monthsActive = Double(QuantisedTimePast.daysBetween(from: subscriptionDate, to: now)) / Double(Constants.daysInAMonth)
            let activeFromMoreThan1Month = monthsActive > 1.0

            if freeTrialPixelSent && !isFreeTrial {
                // At each app startup, check the subscription state. If the a month=0 pixel was sent, the user is no longer on a free trial, and the state is autoRenewable or notAutoRenewable, send this pixel with month=1.
                do {
                    let bucket = try bucketModifier.bucket(value: 1, pixelName: .userSubscribed)
                    pixelKit?.fire(AttributedMetricPixel.userSubscribed(origin: originOrInstall.origin,
                                                                        installDate: originOrInstall.installDate,
                                                                        month: bucket.value,
                                                                        bucketVersion: bucket.version),
                                   frequency: .legacyDailyNoSuffix,
                                   includeAppVersionParameter: false)
                    dataStorage.subscriptionMonth1Fired = true
                } catch {
                    Logger.attributedMetric.error("Failed to bucket length value: \(error, privacy: .public)")
                }
            } else if firstMonthPixelSent && activeFromMoreThan1Month {
                // At each app startup, check the subscription state. If the a month=1 pixel was sent, the state is autoRenewable or notAutoRenewable, and the subscription has been active for more than a month, send this pixel with month=2+.
                do {
                    let subscriptionMonth = Int(monthsActive.rounded(.up))
                    let bucket = try bucketModifier.bucket(value: subscriptionMonth, pixelName: .userSubscribed)
                    pixelKit?.fire(AttributedMetricPixel.userSubscribed(origin: originOrInstall.origin,
                                                                        installDate: originOrInstall.installDate,
                                                                        month: bucket.value,
                                                                        bucketVersion: bucket.version),
                                   frequency: .legacyDailyNoSuffix,
                                   includeAppVersionParameter: false)
                } catch {
                    Logger.attributedMetric.error("Failed to bucket length value: \(error, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Sync
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929616?focus=true

    func processSyncCheck(devicesCount: Int) {
        Logger.attributedMetric.log("Device Sync")

        // check if the number of devices is changed
        let currentDevicesCount = dataStorage.syncDevicesCount
        guard devicesCount > currentDevicesCount else {
            Logger.attributedMetric.debug("No changes in the sync devices count")
            return
        }

        guard devicesCount < 3 else {
            Logger.attributedMetric.debug("Devices count higher than 2")
            return
        }

        dataStorage.syncDevicesCount = devicesCount

        guard let bucket = try? bucketModifier.bucket(value: devicesCount, pixelName: .userSyncedDevice) else {
            Logger.attributedMetric.error("Failed to bucket devices value")
            assertionFailure("Failed to bucket devices value")
            return
        }
        pixelKit?.fire(AttributedMetricPixel.userSyncedDevice(origin: originOrInstall.origin,
                                                              installDate: originOrInstall.installDate,
                                                              devices: bucket.value,
                                                              bucketVersion: bucket.version),
                       frequency: .standard,
                       includeAppVersionParameter: false)
    }
}
