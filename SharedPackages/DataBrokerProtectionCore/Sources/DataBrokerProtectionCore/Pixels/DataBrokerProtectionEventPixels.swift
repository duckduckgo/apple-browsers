//
//  DataBrokerProtectionEventPixels.swift
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
import os.log
import BrowserServicesKit
import PixelKit
import Common

public protocol DataBrokerProtectionEventPixelsRepository {
    func markWeeklyPixelSent()

    func getLatestWeeklyPixel() -> Date?
}

public final class DataBrokerProtectionEventPixelsUserDefaults: DataBrokerProtectionEventPixelsRepository {

    enum Consts {
        static let weeklyPixelKey = "macos.browser.data-broker-protection.eventsWeeklyPixelKey"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func markWeeklyPixelSent() {
        userDefaults.set(Date(), forKey: Consts.weeklyPixelKey)
    }

    public func getLatestWeeklyPixel() -> Date? {
        userDefaults.object(forKey: Consts.weeklyPixelKey) as? Date
    }
}

public final class DataBrokerProtectionEventPixels {

    public enum Consts {
        public static let orphanedSessionThreshold: TimeInterval = .hours(1)
        public static let minimumValidDurationMs: Double = 0
        public static let maximumValidDurationMs: Double = TimeInterval.day * 1000.0
    }

    private let database: DataBrokerProtectionRepository
    private let repository: DataBrokerProtectionEventPixelsRepository
    private let handler: EventMapping<DataBrokerProtectionSharedPixels>
    private let calendar = Calendar.current

    public init(database: DataBrokerProtectionRepository,
                repository: DataBrokerProtectionEventPixelsRepository = DataBrokerProtectionEventPixelsUserDefaults(),
                handler: EventMapping<DataBrokerProtectionSharedPixels>) {
        self.database = database
        self.repository = repository
        self.handler = handler
    }

    public func tryToFireWeeklyPixels(isAuthenticated: Bool) {
        if shouldWeFireWeeklyPixel() {
            fireWeeklyReportPixels(isAuthenticated: isAuthenticated)
            repository.markWeeklyPixelSent()

            #if os(iOS)
            cleanupOldBackgroundTaskSessions()
            #endif
        }
    }

    func fireNewMatchEventPixel() {
        handler.fire(.scanningEventNewMatch)
    }

    func fireReappeareanceEventPixel() {
        handler.fire(.scanningEventReAppearance)
    }

    private func shouldWeFireWeeklyPixel() -> Bool {
        guard let lastPixelFiredDate = repository.getLatestWeeklyPixel() else {
            return true // Last pixel fired date is not present. We should fire it
        }

        return didWeekPassedBetweenDates(start: lastPixelFiredDate, end: Date())
    }

    public func fireWeeklyReportPixels(isAuthenticated: Bool) {
        let data: [BrokerProfileQueryData]

        do {
            data = try database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true)
        } catch {
            Logger.dataBrokerProtection.error("Database error: when attempting to fireWeeklyReportPixels, error: \(error.localizedDescription, privacy: .public)")
            return
        }
        fireWeeklyChildBrokerOrphanedOptOutsPixels(for: data, isAuthenticated: isAuthenticated)

        #if os(iOS)
        fireBackgroundTaskSessionMetrics(isAuthenticated: isAuthenticated)
        #endif

        #if os(iOS) || DEBUG
        fireStalledOperationMetrics(for: data, isAuthenticated: isAuthenticated)
        #endif
    }

    private func fireBackgroundTaskSessionMetrics(isAuthenticated: Bool) {
        do {
            let events = try database.fetchBackgroundTaskEvents(since: .daysAgo(7))

            let metrics = BackgroundTaskEvent.calculateSessionMetrics(
                from: events,
                orphanedThreshold: Consts.orphanedSessionThreshold,
                durationRange: Consts.minimumValidDurationMs...Consts.maximumValidDurationMs,
                now: Date()
            )

            handler.fire(.weeklyReportBackgroundTaskSession(
                started: metrics.started,
                orphaned: metrics.orphaned,
                completed: metrics.completed,
                terminated: metrics.terminated,
                durationMinMs: Double(metrics.durationMinMs),
                durationMaxMs: Double(metrics.durationMaxMs),
                durationMedianMs: metrics.durationMedianMs,
                isAuthenticated: isAuthenticated
            ))
        } catch {
            Logger.dataBrokerProtection.error("Failed to fetch background task events: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fireStalledOperationMetrics(for data: [BrokerProfileQueryData], isAuthenticated: Bool) {
        let scanMetrics = StalledOperationCalculator.scan.calculate(from: data)
        handler.fire(.weeklyReportStalledScans(
            numTotal: scanMetrics.total,
            numStalled: scanMetrics.stalled,
            totalByBroker: scanMetrics.totalByBroker.encodeToJSON() ?? "{}",
            stalledByBroker: scanMetrics.stalledByBroker.encodeToJSON() ?? "{}",
            isAuthenticated: isAuthenticated
        ))

        let optOutMetrics = StalledOperationCalculator.optOut.calculate(from: data)
        handler.fire(.weeklyReportStalledOptOuts(
            numTotal: optOutMetrics.total,
            numStalled: optOutMetrics.stalled,
            totalByBroker: optOutMetrics.totalByBroker.encodeToJSON() ?? "{}",
            stalledByBroker: optOutMetrics.stalledByBroker.encodeToJSON() ?? "{}",
            isAuthenticated: isAuthenticated
        ))
    }

    private func didWeekPassedBetweenDates(start: Date, end: Date) -> Bool {
        let components = calendar.dateComponents([.day], from: start, to: end)

        if let differenceInDays = components.day {
            return differenceInDays >= 7
        } else {
            return false
        }
    }

    #if os(iOS)
    private func cleanupOldBackgroundTaskSessions() {
        do {
            try database.deleteBackgroundTaskEvents(olderThan: .daysAgo(7))
            Logger.dataBrokerProtection.log("Cleaned up background task events older than 7 days")
        } catch {
            Logger.dataBrokerProtection.error("Failed to clean up old background task events: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}

// MARK: - Orphaned profiles stuff

extension DataBrokerProtectionEventPixels {

    func weeklyOptOuts(for brokerProfileQueries: [BrokerProfileQueryData]) -> [OptOutJobData] {
        let optOuts = brokerProfileQueries.flatMap { $0.optOutJobData }
        let weeklyOptOuts = optOuts.filter { !didWeekPassedBetweenDates(start: $0.createdDate, end: Date()) }
        return weeklyOptOuts
    }

    func fireWeeklyChildBrokerOrphanedOptOutsPixels(for data: [BrokerProfileQueryData], isAuthenticated: Bool) {
        let brokerURLsToQueryData = Dictionary(grouping: data, by: { $0.dataBroker.url })
        let childBrokerURLsToOrphanedProfilesCount = childBrokerURLsToOrphanedProfilesWeeklyCount(for: data)
        for (childBrokerURL, value) in childBrokerURLsToOrphanedProfilesCount {
            guard let childQueryData = brokerURLsToQueryData[childBrokerURL],
                  let parentURL = childQueryData.first?.dataBroker.parent,
                  let parentQueryData = brokerURLsToQueryData[parentURL] else {
                continue
            }
            let childRecordsCount = weeklyOptOuts(for: childQueryData).count
            let parentRecordsCount = weeklyOptOuts(for: parentQueryData).count
            let recordsCountDifference = childRecordsCount - parentRecordsCount

            // If both values are zero there's no point sending the pixel
            if recordsCountDifference <= 0 && value == 0 {
                continue
            }
            handler.fire(.weeklyChildBrokerOrphanedOptOuts(dataBrokerURL: childBrokerURL,
                                                           childParentRecordDifference: recordsCountDifference,
                                                           calculatedOrphanedRecords: value,
                                                           isAuthenticated: isAuthenticated))
        }
    }

    func childBrokerURLsToOrphanedProfilesWeeklyCount(for data: [BrokerProfileQueryData]) -> [String: Int] {

        let brokerURLsToQueryData = Dictionary(grouping: data, by: { $0.dataBroker.url })
        let childBrokerURLsToQueryData = brokerURLsToQueryData.filter { (_, value: Array<BrokerProfileQueryData>) in
            guard let first = value.first,
                  first.dataBroker.parent != nil else {
                return false
            }
            return true
        }

        let childBrokerURLsToOrphanedProfilesCount = childBrokerURLsToQueryData.mapValues { value in
            guard let parent = value.first?.dataBroker.parent,
                let parentsQueryData = brokerURLsToQueryData[parent] else {
                return 0
            }

            let optOuts = weeklyOptOuts(for: value)
            let parentBrokerOptOuts = weeklyOptOuts(for: parentsQueryData)

            return orphanedProfilesCount(with: optOuts, parentOptOuts: parentBrokerOptOuts)
        }

        return childBrokerURLsToOrphanedProfilesCount
    }

    func orphanedProfilesCount(with childOptOuts: [OptOutJobData], parentOptOuts: [OptOutJobData]) -> Int {
        let matchingCount = childOptOuts.reduce(0) { (partialResult: Int, optOut: OptOutJobData) in
            let hasFoundParentMatch = parentOptOuts.contains { parentOptOut in
                optOut.extractedProfile.doesMatchExtractedProfile(parentOptOut.extractedProfile)
            }
            return partialResult + (hasFoundParentMatch ? 1 : 0)
        }
        return childOptOuts.count - matchingCount
    }
}

private extension [String: Int] {
    func encodeToJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

private extension Int {
    var toString: String {
        if self < 25 {
            return "0-25"
        } else if self < 50 {
            return "25-50"
        } else if self < 75 {
            return "50-75"
        } else if self <= 100 {
            return "75-100"
        } else {
            return "error"
        }
    }
}
