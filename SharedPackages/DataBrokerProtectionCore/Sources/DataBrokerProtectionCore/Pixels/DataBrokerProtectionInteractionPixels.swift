//
//  DataBrokerProtectionInteractionPixels.swift
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

import Foundation
import BrowserServicesKit
import PixelKit
import Common

public protocol DataBrokerProtectionInteractionPixelsRepository {
    func markDailyPixelSent()
    func markWeeklyPixelSent()
    func markMonthlyPixelSent()

    func getLatestDailyPixel() -> Date?
    func getLatestWeeklyPixel() -> Date?
    func getLatestMonthlyPixel() -> Date?
}

public final class DataBrokerProtectionInteractionPixelsUserDefaults: DataBrokerProtectionInteractionPixelsRepository {

    enum Consts {
        static let dailyPixelKey = "data-broker-protection.interaction.dailyPixelKey"
        static let weeklyPixelKey = "data-broker-protection.interaction.weeklyPixelKey"
        static let monthlyPixelKey = "data-broker-protection.interaction.monthlyPixelKey"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    public func markDailyPixelSent() {
        userDefaults.set(Date(), forKey: Consts.dailyPixelKey)
    }

    public func markWeeklyPixelSent() {
        userDefaults.set(Date(), forKey: Consts.weeklyPixelKey)
    }

    public func markMonthlyPixelSent() {
        userDefaults.set(Date(), forKey: Consts.monthlyPixelKey)
    }

    public func getLatestDailyPixel() -> Date? {
        userDefaults.object(forKey: Consts.dailyPixelKey) as? Date
    }

    public func getLatestWeeklyPixel() -> Date? {
        userDefaults.object(forKey: Consts.weeklyPixelKey) as? Date
    }

    public func getLatestMonthlyPixel() -> Date? {
        userDefaults.object(forKey: Consts.monthlyPixelKey) as? Date
    }
}

/// Fires `dbp_interaction_dau/wau/mau` when the PIR dashboard is presented to the user,
/// deduped on-device by last-fired date (parallel to `DataBrokerProtectionEngagementPixels`).
public final class DataBrokerProtectionInteractionPixels {
    private let repository: DataBrokerProtectionInteractionPixelsRepository
    private let handler: EventMapping<DataBrokerProtectionSharedPixels>

    public init(handler: EventMapping<DataBrokerProtectionSharedPixels>,
                repository: DataBrokerProtectionInteractionPixelsRepository) {
        self.handler = handler
        self.repository = repository
    }

    public func fireInteractionPixel(isAuthenticated: Bool, currentDate: Date = Date()) {
        let isFreeScan = !isAuthenticated

        if shouldWeFireDailyPixel(date: currentDate) {
            handler.fire(.dailyInteractedUser(isAuthenticated: isAuthenticated, isFreeScan: isFreeScan))
            repository.markDailyPixelSent()
        }

        if shouldWeFireWeeklyPixel(date: currentDate) {
            handler.fire(.weeklyInteractedUser(isAuthenticated: isAuthenticated, isFreeScan: isFreeScan))
            repository.markWeeklyPixelSent()
        }

        if shouldWeFireMonthlyPixel(date: currentDate) {
            handler.fire(.monthlyInteractedUser(isAuthenticated: isAuthenticated, isFreeScan: isFreeScan))
            repository.markMonthlyPixelSent()
        }
    }

    private func shouldWeFireDailyPixel(date: Date) -> Bool {
        guard let latestPixelFire = repository.getLatestDailyPixel() else { return true }
        return DataBrokerProtectionSharedPixelsUtilities.shouldWeFirePixel(startDate: latestPixelFire, endDate: date, daysDifference: .daily)
    }

    private func shouldWeFireWeeklyPixel(date: Date) -> Bool {
        guard let latestPixelFire = repository.getLatestWeeklyPixel() else { return true }
        return DataBrokerProtectionSharedPixelsUtilities.shouldWeFirePixel(startDate: latestPixelFire, endDate: date, daysDifference: .weekly)
    }

    private func shouldWeFireMonthlyPixel(date: Date) -> Bool {
        guard let latestPixelFire = repository.getLatestMonthlyPixel() else { return true }
        return DataBrokerProtectionSharedPixelsUtilities.shouldWeFirePixel(startDate: latestPixelFire, endDate: date, daysDifference: .monthly)
    }
}
