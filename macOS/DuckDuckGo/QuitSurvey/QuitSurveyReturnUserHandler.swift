//
//  QuitSurveyReturnUserHandler.swift
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
import os.log
import PixelKit

/// Handles firing the quit survey return user pixel when the app becomes active.
///
/// When a user completes the quit survey (thumbs down with reasons), the reasons are stored
/// in the persistor. This handler checks for pending reasons and fires the return user pixel
/// only if the user returns within the 8-14 day window after first launch.
///
/// - If user returns before day 8: Keep reasons stored, don't fire pixel yet
/// - If user returns between day 8-14: Fire pixel and clear reasons
/// - If user returns after day 14: Clear reasons without firing pixel (window expired)
final class QuitSurveyReturnUserHandler {

    // MARK: - Constants

    /// The start of the window (in days) when the return user pixel should be fired
    private static let returnWindowStartDays: TimeInterval = 8
    /// The end of the window (in days) when the return user pixel should be fired
    private static let returnWindowEndDays: TimeInterval = 14

    // MARK: - Dependencies

    private var persistor: QuitSurveyPersistor
    private let installDate: Date
    private let dateProvider: () -> Date

    // MARK: - Initialization

    init(
        persistor: QuitSurveyPersistor,
        installDate: Date,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.persistor = persistor
        self.installDate = installDate
        self.dateProvider = dateProvider
    }

    /// Fires the return user pixel if there are pending reasons and the user is within the 8-14 day window.
    /// This should be called when the app becomes active.
    func fireReturnUserPixelIfNeeded() {
        guard persistor.pendingReturnUserReasons != nil else {
            return
        }

        let daysSinceInstall = daysSince(installDate)

        // Before day 8: Keep waiting
        if daysSinceInstall < Self.returnWindowStartDays {
            Logger.general.debug("Quit survey return user: Day \(daysSinceInstall, privacy: .public), waiting for day 8-14 window")
            return
        }

        // After day 14: Window expired, clear reasons without firing
        if daysSinceInstall > Self.returnWindowEndDays {
            Logger.general.debug("Quit survey return user: Day \(daysSinceInstall, privacy: .public), window expired (after day 14)")
            persistor.pendingReturnUserReasons = nil
            return
        }

        // Within day 8-14 window: Fire pixel and clear reasons
        guard let reasons = persistor.pendingReturnUserReasons else { return }

        Logger.general.debug("Quit survey return user: Day \(daysSinceInstall, privacy: .public), firing pixel")
        PixelKit.fire(QuitSurveyPixels.quitSurveyReturnUser(reasons: reasons))
        persistor.pendingReturnUserReasons = nil
    }

    // MARK: - Helpers

    private func daysSince(_ date: Date) -> TimeInterval {
        let secondsPerDay: TimeInterval = 24 * 60 * 60
        return dateProvider().timeIntervalSince(date) / secondsPerDay
    }
}
