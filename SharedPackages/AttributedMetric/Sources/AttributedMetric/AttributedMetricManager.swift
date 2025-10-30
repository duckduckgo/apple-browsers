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
import BrowserServicesKit
import os.log

/// macOS: `SystemDefaultBrowserProvider`
/// iOS: `DefaultBrowserManager` limited to 4 times p/y, cached value
public protocol AttributedMetricDefaultBrowserProviding {
    var isDefaultBrowser: Bool { get }
}

public protocol SubscriptionStateProviding {
    func isFreeTrial() async -> Bool
    var isActive: Bool { get }
    func subscriptionDate() async -> Date?
}

public protocol DateProviding {
    func now() -> Date
}

public struct DefaultDateProvider: DateProviding {
    public init() {}
    public func now() -> Date {
        Date()
    }
}

public protocol BucketsSettingsProviding {

    var bucketsSettings: [String: Any] { get }
}

/// https://app.asana.com/1/137249556945/project/1205842942115003/task/1210884473312053?focus=true
public final class AttributedMetricManager {

    struct Constants {
        static let monthTimeInterval: TimeInterval = Double(Constants.daysInAMonth) * .day
        static let daysInAMonth: Int = 28
    }

    private let pixelKit: PixelKit
    private var dataStorage: any AttributedMetricDataStoring
    private let originProvider: (any AttributedMetricOriginProvider)?
    private let featureFlagger: any FeatureFlagger
    private let defaultBrowserProvider: any AttributedMetricDefaultBrowserProviding
    private let subscriptionStateProvider: any SubscriptionStateProviding
    private let dateProvider: any DateProviding
    private let bucketsJsonProvider: any BucketsSettingsProviding
    private var bucketModifier: any BucketModifier = DefaultBucketModifier()
    var cancellables = Set<AnyCancellable>()

    public init(pixelKit: PixelKit,
                dataStoring: any AttributedMetricDataStoring,
                featureFlagger: any FeatureFlagger,
                originProvider: (any AttributedMetricOriginProvider)?,
                defaultBrowserProviding: any AttributedMetricDefaultBrowserProviding,
                subscriptionStateProvider: any SubscriptionStateProviding,
                dateProvider: any DateProviding = DefaultDateProvider(),
                bucketsSettingsProvider: any BucketsSettingsProviding) {
        self.pixelKit = pixelKit
        self.dataStorage = dataStoring
        self.originProvider = originProvider
        self.featureFlagger = featureFlagger
        self.defaultBrowserProvider = defaultBrowserProviding
        self.subscriptionStateProvider = subscriptionStateProvider
        self.dateProvider = dateProvider

        // Buckets
        self.bucketsJsonProvider = bucketsSettingsProvider
        updateBucketSettings()

        if dataStorage.installDate == nil {
            dataStorage.installDate = self.dateProvider.now()
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

    lazy var originOrInstall: (origin: String?, installDate: String?) = {
        if let origin = originProvider?.origin {
            return (origin, nil)
        } else {
            guard var installDate = dataStorage.installDate else {
                assertionFailure("Missing install date")
                return (nil, nil)
            }
            return (nil, installDate.ISO8601ETFormat())
        }
    }()

    var isDefaultBrowser: Bool { defaultBrowserProvider.isDefaultBrowser }

    var isLessThanSixMonths: Bool {
        guard let installDate = dataStorage.installDate else {
            return true
        }
        return installDate.isLessThan(daysAgo: Constants.daysInAMonth * 6)
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
            try bucketModifier.parseConfigurations(from: self.bucketsJsonProvider.bucketsSettings)
        } catch {
            Logger.attributedMetric.fault("Failed to parse buckets settings: \(error, privacy: .public)")
            assertionFailure("Failed to parse buckets settings: \(error)")
        }
    }

    // MARK: - Triggers

    public enum Trigger {
        case appDidStart
        case userDidSearch
        case userDidSelectAD
        case userDidDuckAIChat
        case userDidSubscribe
        case userDidSync(devicesCount: Int)
    }

    public func process(trigger: Trigger) {
        guard isEnabled else { return }

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
            processSyncCheck(devices: devicesCount)
        }
    }

    // MARK: - Retention
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929607?focus=true
    func processRetention() {
        guard let installDate = dataStorage.installDate else {
            Logger.attributedMetric.error("Install date missing")
            return
        }
        let now = dateProvider.now()

        let timePastFromInstall = QuantisedTimePast.timePastFrom(date: now, andInstallationDate: installDate)
        let lastRetentionThreshold = dataStorage.lastRetentionThreshold
        guard lastRetentionThreshold != timePastFromInstall else {
            Logger.attributedMetric.error("Threshold not changed")
            return
        }

        switch timePastFromInstall {
        case .none:
            Logger.attributedMetric.debug("Less than a week from installation")
        case .weeks(let week):
            Logger.attributedMetric.debug("\(week) week(s) from installation")
            guard let bucket = try? bucketModifier.bucket(value: week, pixelName: .userRetentionWeek) else {
                Logger.attributedMetric.error("Failed to bucket week value")
                return
            }
            pixelKit.fire(AttributedMetricPixel.userRetentionWeek(origin: originOrInstall.origin, installDate: originOrInstall.installDate, defaultBrowser: isDefaultBrowser, count: bucket.value, bucketVersion: bucket.version), frequency: .legacyDailyNoSuffix)
            dataStorage.lastRetentionThreshold = timePastFromInstall
        case .months(let month):
            Logger.attributedMetric.debug("\(month) month(s) from installation")
            guard let bucket = try? bucketModifier.bucket(value: month, pixelName: .userRetentionMonth) else {
                Logger.attributedMetric.error("Failed to bucket month value")
                return
            }
            pixelKit.fire(AttributedMetricPixel.userRetentionMonth(origin: originOrInstall.origin, installDate: originOrInstall.installDate, defaultBrowser: isDefaultBrowser, count: bucket.value, bucketVersion: bucket.version), frequency: .legacyDailyNoSuffix)
            dataStorage.lastRetentionThreshold = timePastFromInstall
        }
    }

    // MARK: - Active search days
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929609?focus=true

    func recordActiveSearchDay() {
        let search8Days = dataStorage.search8Days
        search8Days.increment(dateProvider: dateProvider)
        dataStorage.search8Days = search8Days
    }

    func processActiveSearchDays() {
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
        Logger.attributedMetric.debug("\(searchCount) searches performed in the last week")
        guard let bucket = try? bucketModifier.bucket(value: searchCount, pixelName: .userActivePastWeek) else {
            Logger.attributedMetric.error("Failed to bucket search count value")
            return
        }
        pixelKit.fire(AttributedMetricPixel.userActivePastWeek(origin: originOrInstall.origin,
                                                               installDate: originOrInstall.installDate,
                                                               days: bucket.value,
                                                               daysSinceInstalled: addDaysSinceInstalled ? daysSinceInstalled : nil,
                                                               bucketVersion: bucket.version),
                      frequency: .legacyDailyNoSuffix)
    }

    // MARK: - Average searches
    // https://app.asana.com/1/137249556945/project/1205842942115003/task/1211313432282643?focus=true

    func processAverageSearchCount() {
        let search8Days = dataStorage.search8Days
        guard search8Days.countPast7Days > 0 else { return }
        let average = search8Days.past7DaysAverage

        if daysSinceInstalled < Constants.daysInAMonth {
            guard let bucket = try? bucketModifier.bucket(value: average, pixelName: .userAverageSearchesPastWeekFirstMonth) else {
                Logger.attributedMetric.error("Failed to bucket average search count value")
                return
            }
            Logger.attributedMetric.debug("Average search count in the last week: \(bucket.value)")
            pixelKit.fire(AttributedMetricPixel.userAverageSearchesPastWeekFirstMonth(origin: originOrInstall.origin,
                                                                                      installDate: originOrInstall.installDate,
                                                                                      count: bucket.value,
                                                                                      bucketVersion: bucket.version),
                          frequency: .legacyDailyNoSuffix)
        } else {
            guard let bucket = try? bucketModifier.bucket(value: average, pixelName: .userAverageSearchesPastWeek) else {
                Logger.attributedMetric.error("Failed to bucket average search count value")
                return
            }
            Logger.attributedMetric.debug("Average search count in the last week: \(bucket.value)")
            pixelKit.fire(AttributedMetricPixel.userAverageSearchesPastWeek(origin: originOrInstall.origin,
                                                                            installDate: originOrInstall.installDate,
                                                                            count: bucket.value,
                                                                            bucketVersion: bucket.version),
                          frequency: .legacyDailyNoSuffix)
        }
    }

    // MARK: - Average AD clicks
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929610?focus=true

    func recordAdClick() {
        let adClick8Days = dataStorage.adClick8Days
        adClick8Days.increment(dateProvider: dateProvider)
        dataStorage.adClick8Days = adClick8Days
    }

    func processAverageAdClick() {
        guard !isSameDayOfInstallDate else { return }

        let adClick8Days = dataStorage.adClick8Days
        guard adClick8Days.countPast7Days > 0 else { return }
        let average = adClick8Days.past7DaysAverage
        guard let bucket = try? bucketModifier.bucket(value: average, pixelName: .userAverageAdClicksPastWeek) else {
            Logger.attributedMetric.error("Failed to bucket average ad click value")
            return
        }
        Logger.attributedMetric.debug("Average AD click count in the last week: \(bucket.value)")
        pixelKit.fire(AttributedMetricPixel.userAverageAdClicksPastWeek(origin: originOrInstall.origin,
                                                                        installDate: originOrInstall.installDate,
                                                                        count: bucket.value,
                                                                        bucketVersion: bucket.version),
                      frequency: .legacyDailyNoSuffix)
    }

    // MARK: - Average Duck.ai chats
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929612?focus=true

    func recordDuckAIChat() {
        let duckAIChat8Days = dataStorage.duckAIChat8Days
        duckAIChat8Days.increment(dateProvider: dateProvider)
        dataStorage.duckAIChat8Days = duckAIChat8Days
    }

    func processAverageDuckAIChat() {
        guard !isSameDayOfInstallDate else { return }

        let duckAIChat8Days = dataStorage.duckAIChat8Days
        guard duckAIChat8Days.countPast7Days > 0 else { return }
        let average = duckAIChat8Days.past7DaysAverage
        guard let bucket = try? bucketModifier.bucket(value: average, pixelName: .userAverageDuckAiUsagePastWeek) else {
            Logger.attributedMetric.error("Failed to bucket average Duck.AI chat value")
            return
        }
        Logger.attributedMetric.debug("Average Duck.AI chats count in the last week: \(bucket.value)")
        pixelKit.fire(AttributedMetricPixel.userAverageDuckAiUsagePastWeek(origin: originOrInstall.origin,
                                                                           installDate: originOrInstall.installDate,
                                                                           count: bucket.value,
                                                                           bucketVersion: bucket.version),
                      frequency: .legacyDailyNoSuffix)
    }

    // MARK: - Subscription
    // https://app.asana.com/1/137249556945/project/1205842942115003/task/1211301604929613?focus=true

    func processSubscriptionDay() {

        guard dataStorage.subscriptionDate == nil else { return }

        dataStorage.subscriptionDate = dateProvider.now()
        Logger.attributedMetric.debug("Subscription purchased today")

        Task {
            let isFreeTrial = await subscriptionStateProvider.isFreeTrial()
            if isFreeTrial  {
                dataStorage.subscriptionFreeTrialFired = true
            } else {
                dataStorage.subscriptionMonth1Fired = true
            }

            let length = isFreeTrial ? 0 : 1
            guard let bucket = try? bucketModifier.bucket(value: length, pixelName: .userSubscribed) else {
                Logger.attributedMetric.error("Failed to bucket length value")
                return
            }
            pixelKit.fire(AttributedMetricPixel.userSubscribed(origin: originOrInstall.origin,
                                                               installDate: originOrInstall.installDate,
                                                               length: bucket.value,
                                                               bucketVersion: bucket.version),
                          frequency: .legacyDailyNoSuffix)
        }
    }

    func processSubscriptionCheck() {
        guard let subscriptionDate = dataStorage.subscriptionDate else {
            Logger.attributedMetric.error("Missing subscription date")
            return
        }
        Task {
            let now = dateProvider.now()
            let freeTrialPixelSent = dataStorage.subscriptionFreeTrialFired
            let firstMonthPixelSent = dataStorage.subscriptionMonth1Fired
            let isFreeTrial = await subscriptionStateProvider.isFreeTrial()
            let isActive = subscriptionStateProvider.isActive

            switch (freeTrialPixelSent, isFreeTrial, isActive, firstMonthPixelSent) {
            case (true, // free trial sent
                  false, // is not free trial anymore
                  true, // is subscribed
                  _):
                // At each app startup, check the subscription state. If the a month=0 pixel was sent, the user is no longer on a free trial, and the state is autoRenewable or notAutoRenewable, send this pixel with month=1.
                guard let bucket = try? bucketModifier.bucket(value: 1, pixelName: .userSubscribed) else {
                    Logger.attributedMetric.error("Failed to bucket length value")
                    return
                }
                pixelKit.fire(AttributedMetricPixel.userSubscribed(origin: originOrInstall.origin,
                                                                   installDate: originOrInstall.installDate,
                                                                   length: bucket.value,
                                                                   bucketVersion: bucket.version),
                              frequency: .legacyDailyNoSuffix)
            case (_, _,
                  true, // is subscribed
                  true // 1 month pixel sent
            ):
                // At each app startup, check the subscription state. If the a month=1 pixel was sent, the state is autoRenewable or notAutoRenewable, and the subscription has been active for more than a month, send this pixel with month=2+.
                guard let bucket = try? bucketModifier.bucket(value: 2, pixelName: .userSubscribed) else {
                    Logger.attributedMetric.error("Failed to bucket length value")
                    return
                }
                if QuantisedTimePast.daysBetween(from: subscriptionDate, to: now) >= Constants.daysInAMonth {
                    pixelKit.fire(AttributedMetricPixel.userSubscribed(origin: originOrInstall.origin,
                                                                       installDate: originOrInstall.installDate,
                                                                       length: bucket.value,
                                                                       bucketVersion: bucket.version),
                                  frequency: .legacyDailyNoSuffix)
                }
            default:
                break
            }
        }
    }

    // MARK: - Sync
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929616?focus=true

    func processSyncCheck(devices: Int) {

        guard devices < 3 else { return }

        Logger.attributedMetric.debug("Device Sync")
        // specs not clear: https://app.asana.com/1/137249556945/task/1211301604929616/comment/1211362907479310?focus=true
        guard let bucket = try? bucketModifier.bucket(value: devices, pixelName: .userSyncedDevice) else {
            Logger.attributedMetric.error("Failed to bucket devices value")
            return
        }
        pixelKit.fire(AttributedMetricPixel.userSyncedDevice(origin: originOrInstall.origin, installDate: originOrInstall.installDate, devices: bucket.value, bucketVersion: bucket.version), frequency: .standard)
    }
}
