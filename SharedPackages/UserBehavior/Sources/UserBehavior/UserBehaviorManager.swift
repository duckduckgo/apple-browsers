//
//  UserBehaviorManager.swift
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
public protocol UserBehaviorDefaultBrowserProviding {
    var isDefaultBrowser: Bool { get }
}

/// https://app.asana.com/1/137249556945/project/1205842942115003/task/1210884473312053?focus=true
public final class UserBehaviorManager {

    struct Constants {
        static let monthTimeInterval: TimeInterval = Double(Constants.daysInAMonth) * .day
        static let daysInAMonth: Int = 28
    }

    private let pixelKit: PixelKit
    private var dataStorage: UserBehaviorDataStoring
    private let originProvider: (any UserBehaviorOriginProvider)?
    private let featureFlagger: FeatureFlagger
    private let defaultBrowserProviding: UserBehaviorDefaultBrowserProviding
    var cancellables = Set<AnyCancellable>()

    public init(pixelKit: PixelKit,
                dataStoring: UserBehaviorDataStoring,
                featureFlagger: FeatureFlagger,
                originProvider: (any UserBehaviorOriginProvider)?,
                defaultBrowserProviding: UserBehaviorDefaultBrowserProviding) {
        self.pixelKit = pixelKit
        self.dataStorage = dataStoring
        self.originProvider = originProvider
        self.featureFlagger = featureFlagger
        self.defaultBrowserProviding = defaultBrowserProviding

        if dataStorage.installDate == nil {
            dataStorage.installDate = Date()
        }

        if isEnabled {
            registerNotifications()
        }
    }

    // MARK: -

    var isEnabled: Bool {
        featureFlagger.isFeatureOn(for: UserBehaviorFeatureFlags.behaviorMetricsEnabled)
    }

    lazy var originOrInstall: (origin: String?, installDate: String?) = {
        if let origin = originProvider?.origin {
            return (origin, nil)
        } else {
            guard var installDate = dataStorage.installDate else {
                assertionFailure("Missing install date")
                return (nil, nil)
            }
            return (nil, installDate.ISO8601Format())
        }
    }()

    var isDefaultBrowser: Bool { defaultBrowserProviding.isDefaultBrowser }

    var isLessThanSixMonths: Bool {
        guard let installDate = dataStorage.installDate else {
            return true
        }
        return installDate.isLessThan(daysAgo: Constants.daysInAMonth * 6)
    }

    // MARK: - Triggers

    public enum Trigger {
        case appDidStart
        case userDidSearch
        case userDidClickAD
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
        case .userDidClickAD:
            recordAdClick()
            processAverageAdClick()
        case .userDidDuckAIChat:
            recordDuckAIChat()
            processAverageDuckAIChat()
        case .userDidSubscribe:
            recordSubscriptionDate()
            processSubscriptionDay()
        case .userDidSync(devicesCount: let devicesCount):
            processSyncCheck(devices: devicesCount)
        }
    }

    // MARK: - Retention
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929607?focus=true

    func processRetention() {

        guard let installDate = dataStorage.installDate else {
            Logger.userBehavior.error("Install date missing")
            return
        }
        let now = Date()

        let timePastFromInstall = TimePast.timePastFrom(date: now, andInstallationDate: installDate)
        let lastRetentionThreshold = dataStorage.lastRetentionThreshold
        guard lastRetentionThreshold != timePastFromInstall else {
            Logger.userBehavior.error("Threshold not changed")
            return
        }

        switch timePastFromInstall {
        case .none:
            Logger.userBehavior.debug("Less than a week from installation")
        case .weeks(let week):
            Logger.userBehavior.debug("\(week) week(s) from installation")
            let bucketedWeek = String(week) // TODO: implement
            pixelKit.fire(UserBehaviorPixel.userRetentionWeek(origin: originOrInstall.origin, installDate: originOrInstall.installDate, defaultBrowser: isDefaultBrowser, count: bucketedWeek), frequency: .legacyDailyNoSuffix)
            dataStorage.lastRetentionThreshold = timePastFromInstall
        case .months(let month):
            Logger.userBehavior.debug("\(month) month(s) from installation")
            let bucketedMonth = String(month) // TODO: implement
            pixelKit.fire(UserBehaviorPixel.userRetentionMonth(origin: originOrInstall.origin, installDate: originOrInstall.installDate, defaultBrowser: isDefaultBrowser, count: bucketedMonth), frequency: .legacyDailyNoSuffix)
            dataStorage.lastRetentionThreshold = timePastFromInstall
        }
    }

    // MARK: - Active search days
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929609?focus=true

    func recordActiveSearchDay() {
        let search8Days = dataStorage.search8Days
        search8Days.increment()
        dataStorage.search8Days = search8Days
    }

    func processActiveSearchDays() {
        let search8Days = dataStorage.search8Days
        let searchCount = search8Days.countPast7Days
        guard searchCount > 0 else { return }
        Logger.userBehavior.debug("\(searchCount) searches performed in the last week")
        let bucketedSearchCount = searchCount // TODO: implement
        pixelKit.fire(UserBehaviorPixel.userActivePastWeek(origin: originOrInstall.origin, installDate: originOrInstall.installDate, days: bucketedSearchCount), frequency: .legacyDailyNoSuffix)
    }

    // MARK: - Average searches
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211313432282643?focus=true

    func processAverageSearchCount() {
        let search8Days = dataStorage.search8Days
        guard search8Days.countPast7Days > 1 else { return }
        let average = search8Days.past7DaysAverage
        let bucketedAverage = String(average) // TODO: implement
        Logger.userBehavior.debug("Average search count in the last week: \(bucketedAverage)")
        pixelKit.fire(UserBehaviorPixel.userAverageSearchesPastWeek(origin: originOrInstall.origin, installDate: originOrInstall.installDate, count: bucketedAverage), frequency: .legacyDailyNoSuffix)
    }

    // MARK: - Average AD clicks
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929610?focus=true

    func recordAdClick() {
        let adClick8Days = dataStorage.adClick8Days
        adClick8Days.increment()
        dataStorage.adClick8Days = adClick8Days
    }

    func processAverageAdClick() {
        let adClick8Days = dataStorage.adClick8Days
        guard adClick8Days.countPast7Days > 1 else { return }
        let average = adClick8Days.past7DaysAverage
        let bucketedAverage = String(average) // TODO: implement
        Logger.userBehavior.debug("Average AD click count in the last week: \(bucketedAverage)")
        pixelKit.fire(UserBehaviorPixel.userAverageAdClicksPastWeek(origin: originOrInstall.origin, installDate: originOrInstall.installDate, count: bucketedAverage), frequency: .legacyDailyNoSuffix)
    }

    // MARK: - Average Duck.ai chats
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929612?focus=true

    func recordDuckAIChat() {
        let duckAIChat8Days = dataStorage.duckAIChat8Days
        duckAIChat8Days.increment()
        dataStorage.duckAIChat8Days = duckAIChat8Days
    }

    func processAverageDuckAIChat() {
        let duckAIChat8Days = dataStorage.duckAIChat8Days
        guard duckAIChat8Days.countPast7Days > 1 else { return }
        let average = duckAIChat8Days.past7DaysAverage
        let bucketedAverage = String(average) // TODO: implement
        Logger.userBehavior.debug("Average Duck.AI chats count in the last week: \(bucketedAverage)")
        pixelKit.fire(UserBehaviorPixel.userAverageDuckAiUsagePastWeek(origin: originOrInstall.origin, installDate: originOrInstall.installDate, count: bucketedAverage), frequency: .legacyDailyNoSuffix)
    }

    // MARK: - Subscription

    func recordSubscriptionDate() {
        dataStorage.subscriptionDate = Date()
    }

    func processSubscriptionDay() {
        Logger.userBehavior.debug("Subscription purchased today")
        pixelKit.fire(UserBehaviorPixel.userSubscribed(origin: originOrInstall.origin, installDate: originOrInstall.installDate, length: "1"), frequency: .legacyDailyNoSuffix)
    }

    func processSubscriptionCheck() {
        guard let subscriptionDate = dataStorage.subscriptionDate else {
            Logger.userBehavior.error("Missing subscription date")
            return
        }
        let now = Date()
        if TimePast.daysBetween(from: subscriptionDate, to: now) >= Constants.daysInAMonth {
            Logger.userBehavior.debug("Subscription purchased more than 1 month ago")
            pixelKit.fire(UserBehaviorPixel.userSubscribed(origin: originOrInstall.origin, installDate: originOrInstall.installDate, length: "2+"), frequency: .legacyDailyNoSuffix)
        }
    }

    // MARK: - Sync
    // https://app.asana.com/1/137249556945/project/1113117197328546/task/1211301604929616?focus=true

    func processSyncCheck(devices: Int) {
        Logger.userBehavior.debug("Device Sync")
        // TODO: specs not clear: https://app.asana.com/1/137249556945/task/1211301604929616/comment/1211362907479310?focus=true
        pixelKit.fire(UserBehaviorPixel.userSyncedDevice(origin: originOrInstall.origin, installDate: originOrInstall.installDate, devices: devices == 1 ? "1" : "2+"), frequency: .standard)
    }
}

private extension Date {

    func ISO8601Format() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        return formatter.string(from: self)
    }
}
