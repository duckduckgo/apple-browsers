//
//  DataBrokerProtectionStatsPixels.swift
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

import Foundation
import Common
import BrowserServicesKit
import PixelKit

public protocol DataBrokerProtectionStatsPixelsRepository {
    var customStatsPixelsLastSentTimestamp: Date? { get set }
}

public final class DataBrokerProtectionStatsPixelsUserDefaults: DataBrokerProtectionStatsPixelsRepository {

    enum Consts {
        static let customStatsPixelKey = "macos.browser.data-broker-protection.customStatsPixelKey"
    }

    private let userDefaults: UserDefaults

    public var customStatsPixelsLastSentTimestamp: Date? {
        get {
            userDefaults.object(forKey: Consts.customStatsPixelKey) as? Date
        }
        set {
            userDefaults.set(newValue, forKey: Consts.customStatsPixelKey)
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
}

protocol StatsPixels {
    /// Calculates and fires custom stats pixels if needed
    func fireCustomStatsPixelsIfNeeded()
}

/// Conforming types provide a method to check if we should fire custom stats based on an input date
public protocol CustomStatsPixelsTrigger {

    /// This method determines whether custom stats pixels should be fired based on the time interval since the provided fromDate.
    /// - Parameter fromDate: An optional date parameter representing the start date. If nil, the method will return true.
    /// - Returns: Returns true if more than 24 hours have passed since the fromDate. If fromDate is nil, it also returns true. Otherwise, it returns false.
    func shouldFireCustomStatsPixels(fromDate: Date?) -> Bool
}

public struct DefaultCustomStatsPixelsTrigger: CustomStatsPixelsTrigger {

    public init() {
    }

    public func shouldFireCustomStatsPixels(fromDate: Date?) -> Bool {
        guard let fromDate = fromDate else { return true }

        let interval = Date().timeIntervalSince(fromDate)
        let secondsIn24Hours: TimeInterval = 24 * 60 * 60
        return abs(interval) > secondsIn24Hours
    }
}

public extension Date {

    /// Returns the current date minus the specified number of hours
    /// If the date calculate fails, returns the current date
    /// - Parameter hours: Hours expressed as an integer
    /// - Returns: The current time minus the specified number of hours
    static func nowMinus(hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
    }

    static func nowPlus(hours: Int) -> Date {
        nowMinus(hours: -hours)
    }
}

public final class DataBrokerProtectionStatsPixels: StatsPixels {

    private let database: DataBrokerProtectionRepository
    private let handler: EventMapping<DataBrokerProtectionSharedPixels>
    private var repository: DataBrokerProtectionStatsPixelsRepository
    private let customStatsPixelsTrigger: CustomStatsPixelsTrigger
    private let customOptOutStatsProvider: DataBrokerProtectionCustomOptOutStatsProvider

    public init(database: DataBrokerProtectionRepository,
                handler: EventMapping<DataBrokerProtectionSharedPixels>,
                repository: DataBrokerProtectionStatsPixelsRepository = DataBrokerProtectionStatsPixelsUserDefaults(),
                customStatsPixelsTrigger: CustomStatsPixelsTrigger = DefaultCustomStatsPixelsTrigger(),
                customOptOutStatsProvider: DataBrokerProtectionCustomOptOutStatsProvider = DefaultDataBrokerProtectionCustomOptOutStatsProvider()) {
        self.database = database
        self.handler = handler
        self.repository = repository
        self.customStatsPixelsTrigger = customStatsPixelsTrigger
        self.customOptOutStatsProvider = customOptOutStatsProvider
    }

    public func tryToFireStatsPixels() {
        guard let brokerProfileQueryData = try? database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true) else {
            return
        }

        fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for: brokerProfileQueryData)
    }

    public func fireCustomStatsPixelsIfNeeded() {
        let startDate = repository.customStatsPixelsLastSentTimestamp

        guard customStatsPixelsTrigger.shouldFireCustomStatsPixels(fromDate: startDate),
        let queryData = try? database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true) else { return }

        let endDate = Date.nowMinus(hours: 24)

        let customOptOutStats = customOptOutStatsProvider.customOptOutStats(startDate: startDate,
                                                                            endDate: endDate,
                                                                            andQueryData: queryData)

        fireCustomDataBrokerStatsPixels(customOptOutStats: customOptOutStats)
        fireCustomGlobalStatsPixel(customOptOutStats: customOptOutStats)

        repository.customStatsPixelsLastSentTimestamp = Date.nowMinus(hours: 24)
    }

}

private extension DataBrokerProtectionStatsPixels {

    func fireCustomDataBrokerStatsPixels(customOptOutStats: CustomOptOutStats) {
        Task {
            for stat in customOptOutStats.customIndividualDataBrokerStat {
                handler.fire(pixel(for: stat))
                // Introduce a delay to prevent all databroker pixels from firing at (nearly) the same time
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func pixel(for dataBrokerStat: CustomIndividualDataBrokerStat) -> DataBrokerProtectionSharedPixels {
        .customDataBrokerStatsOptoutSubmit(dataBrokerURL: dataBrokerStat.dataBrokerURL,
                                           optOutSubmitSuccessRate: dataBrokerStat.optoutSubmitSuccessRate)
    }

    func fireCustomGlobalStatsPixel(customOptOutStats: CustomOptOutStats) {
        handler.fire(pixel(for: customOptOutStats.customAggregateBrokersStat))
    }

    func pixel(for aggregateStat: CustomAggregateBrokersStat) -> DataBrokerProtectionSharedPixels {
        .customGlobalStatsOptoutSubmit(optOutSubmitSuccessRate: aggregateStat.optoutSubmitSuccessRate)
    }
}

// MARK: - Opt out confirmation pixels

extension DataBrokerProtectionStatsPixels {
    // swiftlint:disable:next cyclomatic_complexity
    func fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for brokerProfileQueryData: [BrokerProfileQueryData]) {
        /*
         This fires pixels to indicate if any submitted opt outs have been confirmed or unconfirmed
         at fixed intervals after the submission (7, 14, and 21 days)
         Goal: Be able to calculate what % of removals occur within x weeks of successful opt-out submission.

         - We get all opt out jobs with status showing they were submitted successfully
         - Compare the date they were submitted successfully with the current date
         - Bucket into >=7, >=14, and >=21 days groups (with overlap between the groups, e.g. it's possible it's been 15 days but neither the 7 day or the 14 day pixel has been fired)
         - Filter those groups based on if the pixel for that time interval has been fired yet
         - Fire the appropriate confirmed/unconfirmed pixels for each job
         - Update the DB to indicate which pixels have been newly fired

         Because submittedSuccessfullyDate will be nil for data that existed before the migration
         the pixels won't fire for old data, which is the behaviour we want.
         */

        let allOptOuts = brokerProfileQueryData.flatMap { $0.optOutJobData }
        let successfullySubmittedOptOuts = allOptOuts.filter { $0.submittedSuccessfullyDate != nil && !$0.isRemovedByUser }

        let sevenDayOldPlusOptOutsThatHaveNotFiredPixel = successfullySubmittedOptOuts.filter { optOutJob in
            guard let submittedSuccessfullyDate = optOutJob.submittedSuccessfullyDate else { return false }
            let hasEnoughTimePassedToFirePixel = submittedSuccessfullyDate.hasBeenExceededByNumberOfDays(7)
            return hasEnoughTimePassedToFirePixel && !optOutJob.sevenDaysConfirmationPixelFired
        }

        let fourteenDayOldPlusOptOutsThatHaveNotFiredPixel = successfullySubmittedOptOuts.filter { optOutJob in
            guard let submittedSuccessfullyDate = optOutJob.submittedSuccessfullyDate else { return false }
            let hasEnoughTimePassedToFirePixel = submittedSuccessfullyDate.hasBeenExceededByNumberOfDays(14)
            return hasEnoughTimePassedToFirePixel && !optOutJob.fourteenDaysConfirmationPixelFired
        }

        let twentyOneDayOldPlusOptOutsThatHaveNotFiredPixel = successfullySubmittedOptOuts.filter { optOutJob in
            guard let submittedSuccessfullyDate = optOutJob.submittedSuccessfullyDate else { return false }
            let hasEnoughTimePassedToFirePixel = submittedSuccessfullyDate.hasBeenExceededByNumberOfDays(21)
            return hasEnoughTimePassedToFirePixel && !optOutJob.twentyOneDaysConfirmationPixelFired
        }

        let fortyTwoDayOldPlusOptOutsThatHaveNotFiredPixel = successfullySubmittedOptOuts.filter { optOutJob in
            guard let submittedSuccessfullyDate = optOutJob.submittedSuccessfullyDate else { return false }
            let hasEnoughTimePassedToFirePixel = submittedSuccessfullyDate.hasBeenExceededByNumberOfDays(42)
            return hasEnoughTimePassedToFirePixel && !optOutJob.fortyTwoDaysConfirmationPixelFired
        }

        let brokerIDsToURLs = brokerProfileQueryData.reduce(into: [Int64: String]()) {
            // Really the ID should never be zero
            $0[$1.dataBroker.id ?? -1] = $1.dataBroker.url
        }

        // Now fire the pixels and update the DB
        for optOutJob in sevenDayOldPlusOptOutsThatHaveNotFiredPixel {
            let brokerURL = brokerIDsToURLs[optOutJob.brokerId] ?? ""
            let isOptOutConfirmed = optOutJob.extractedProfile.removedDate != nil

            if isOptOutConfirmed {
                handler.fire(.optOutJobAt7DaysConfirmed(dataBroker: brokerURL))
            } else {
                handler.fire(.optOutJobAt7DaysUnconfirmed(dataBroker: brokerURL))
            }

            guard let extractedProfileID = optOutJob.extractedProfile.id else { continue }
            try? database.updateSevenDaysConfirmationPixelFired(true,
                                                                forBrokerId: optOutJob.brokerId,
                                                                profileQueryId: optOutJob.profileQueryId,
                                                                extractedProfileId: extractedProfileID)
        }

        for optOutJob in fourteenDayOldPlusOptOutsThatHaveNotFiredPixel {
            let brokerURL = brokerIDsToURLs[optOutJob.brokerId] ?? ""
            let isOptOutConfirmed = optOutJob.extractedProfile.removedDate != nil

            if isOptOutConfirmed {
                handler.fire(.optOutJobAt14DaysConfirmed(dataBroker: brokerURL))
            } else {
                handler.fire(.optOutJobAt14DaysUnconfirmed(dataBroker: brokerURL))
            }

            guard let extractedProfileID = optOutJob.extractedProfile.id else { continue }
            try? database.updateFourteenDaysConfirmationPixelFired(true,
                                                                   forBrokerId: optOutJob.brokerId,
                                                                   profileQueryId: optOutJob.profileQueryId,
                                                                   extractedProfileId: extractedProfileID)
        }

        for optOutJob in twentyOneDayOldPlusOptOutsThatHaveNotFiredPixel {
            let brokerURL = brokerIDsToURLs[optOutJob.brokerId] ?? ""
            let isOptOutConfirmed = optOutJob.extractedProfile.removedDate != nil

            if isOptOutConfirmed {
                handler.fire(.optOutJobAt21DaysConfirmed(dataBroker: brokerURL))
            } else {
                handler.fire(.optOutJobAt21DaysUnconfirmed(dataBroker: brokerURL))
            }

            guard let extractedProfileID = optOutJob.extractedProfile.id else { continue }
            try? database.updateTwentyOneDaysConfirmationPixelFired(true,
                                                                    forBrokerId: optOutJob.brokerId,
                                                                    profileQueryId: optOutJob.profileQueryId,
                                                                    extractedProfileId: extractedProfileID)
        }

        for optOutJob in fortyTwoDayOldPlusOptOutsThatHaveNotFiredPixel {
            let brokerURL = brokerIDsToURLs[optOutJob.brokerId] ?? ""
            let isOptOutConfirmed = optOutJob.extractedProfile.removedDate != nil

            if isOptOutConfirmed {
                handler.fire(.optOutJobAt42DaysConfirmed(dataBroker: brokerURL))
            } else {
                handler.fire(.optOutJobAt42DaysUnconfirmed(dataBroker: brokerURL))
            }

            guard let extractedProfileID = optOutJob.extractedProfile.id else { continue }
            try? database.updateFortyTwoDaysConfirmationPixelFired(true,
                                                                   forBrokerId: optOutJob.brokerId,
                                                                   profileQueryId: optOutJob.profileQueryId,
                                                                   extractedProfileId: extractedProfileID)
        }
    }
}

private extension Date {
    func hasBeenExceededByNumberOfDays(_ days: Int) -> Bool {
        guard let submittedDatePlusTimeInterval = Calendar.current.date(byAdding: .day, value: days, to: self) else {
            return false
        }
        return submittedDatePlusTimeInterval <= Date()
    }
}
