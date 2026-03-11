//
//  UpdateWideEventData.swift
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

import AppUpdaterShared
import Foundation
import PixelKit

/// Data model for Sparkle update cycle Wide Events.
///
/// Encapsulates all data tracked during an update flow, including version information,
/// timing measurements, cancellation reasons, and system context.
///
/// ## Scope and Responsibilities
///
/// - Defines the complete data structure for tracking a single update flow
/// - Encapsulates conversion to pixel parameters with proper string encoding
/// - Provides utility for disk space measurement (called only on failures)
/// - Does NOT manage flow lifecycle (that's SparkleUpdateWideEvent's responsibility)
/// - Does NOT persist data (handled by WideEventManager)
///
/// ## Timing Measurements
///
/// Timing properties use `WideEvent.MeasuredInterval` which supports the pattern:
/// - Start timing at milestone entry: `.startingNow()`
/// - Complete at milestone exit: `.complete()`
/// - Incomplete intervals (not completed before flow ends) won't be included in pixel parameters
public final class UpdateWideEventData: WideEventData {
    public static let metadata = WideEventMetadata(
        pixelName: "sparkle_update_cycle",
        featureName: "sparkle-update",
        mobileMetaType: "ios-sparkle-update",
        desktopMetaType: "macos-sparkle-update",
        version: "1.0.1"
    )

    // Required protocol properties
    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData
    public var errorData: WideEventErrorData?

    // Update-specific data
    public var fromVersion: String
    public var fromBuild: String
    public var toVersion: String?
    public var toBuild: String?
    public var updateType: UpdateType?
    public var initiationType: InitiationType
    public var updateConfiguration: UpdateConfiguration
    public var lastKnownStep: UpdateStep?
    public var osVersion: String

    // Optional contextual data
    public var cancellationReason: CancellationReason?
    public var diskSpaceRemainingBytes: UInt64?
    public var timeSinceLastUpdateBucket: TimeSinceUpdateBucket?

    // Timing measurements for each phase of the update cycle.
    // Incomplete intervals won't be included in pixel parameters.
    public var updateCheckDuration: WideEvent.MeasuredInterval?
    public var downloadDuration: WideEvent.MeasuredInterval?
    public var extractionDuration: WideEvent.MeasuredInterval?
    public var totalDuration: WideEvent.MeasuredInterval?

    /// Type of update available.
    public enum UpdateType: String, Codable {
        case regular
        case critical
    }

    /// How the update was initiated.
    public enum InitiationType: String, Codable {
        case automatic  // Background check
        case manual     // User-triggered check
    }

    /// User's automatic update preference setting.
    public enum UpdateConfiguration: String, Codable {
        case automatic
        case manual
    }

    /// Reason an update flow was cancelled.
    public enum CancellationReason: String, Codable {
        case appQuit          // App terminated during update
        case settingsChanged  // Automatic updates toggled
        case buildExpired     // Current build too old
        case newCheckStarted  // New check interrupted this one
    }

    /// Reason an update flow completed successfully.
    public enum SuccessReason: String {
        case noUpdateAvailable = "no_update_available"
        case restartingToUpdate = "restarting_to_update"
        case installingOnQuit = "installing_on_quit"
    }

    /// Last known step in the update process before flow ended.
    public enum UpdateStep: String, Codable {
        case updateCheckStarted
        case updateFound
        case noUpdateFound
        case downloadStarted
        case downloadCompleted
        case extractionStarted
        case extractionCompleted
        case restartingToUpdate
    }

    /// Time bucket for privacy-safe update frequency tracking.
    public enum TimeSinceUpdateBucket: String, Codable {
        case lessThan30Minutes = "<30m"
        case lessThan2Hours = "<2h"
        case lessThan6Hours = "<6h"
        case lessThan1Day = "<1d"
        case lessThan2Days = "<2d"
        case lessThan1Week = "<1w"
        case lessThan1Month = "<1M"
        case greaterThanOrEqual1Month = ">=1M"

        public init(interval: TimeInterval) {
            let minutes = interval / 60.0
            let hours = minutes / 60.0
            let days = hours / 24.0
            let weeks = days / 7.0
            let months = days / 30.0

            if months >= 1 {
                self = .greaterThanOrEqual1Month
            } else if weeks >= 1 {
                self = .lessThan1Month
            } else if days >= 2 {
                self = .lessThan1Week
            } else if days >= 1 {
                self = .lessThan2Days
            } else if hours >= 6 {
                self = .lessThan1Day
            } else if hours >= 2 {
                self = .lessThan6Hours
            } else if minutes >= 30 {
                self = .lessThan2Hours
            } else {
                self = .lessThan30Minutes
            }
        }

        /// Convenience initializer that calculates the interval between two dates.
        public init(from lastDate: Date, to currentDate: Date = Date()) {
            let interval = currentDate.timeIntervalSince(lastDate)
            self.init(interval: interval)
        }
    }

    public init(fromVersion: String,
                fromBuild: String,
                toVersion: String? = nil,
                toBuild: String? = nil,
                updateType: UpdateType? = nil,
                initiationType: InitiationType,
                updateConfiguration: UpdateConfiguration,
                lastKnownStep: UpdateStep? = nil,
                osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
                cancellationReason: CancellationReason? = nil,
                diskSpaceRemainingBytes: UInt64? = nil,
                timeSinceLastUpdateBucket: TimeSinceUpdateBucket? = nil,
                updateCheckDuration: WideEvent.MeasuredInterval? = nil,
                downloadDuration: WideEvent.MeasuredInterval? = nil,
                extractionDuration: WideEvent.MeasuredInterval? = nil,
                totalDuration: WideEvent.MeasuredInterval? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.fromVersion = fromVersion
        self.fromBuild = fromBuild
        self.toVersion = toVersion
        self.toBuild = toBuild
        self.updateType = updateType
        self.initiationType = initiationType
        self.updateConfiguration = updateConfiguration
        self.lastKnownStep = lastKnownStep
        self.osVersion = osVersion
        self.cancellationReason = cancellationReason
        self.diskSpaceRemainingBytes = diskSpaceRemainingBytes
        self.timeSinceLastUpdateBucket = timeSinceLastUpdateBucket
        self.updateCheckDuration = updateCheckDuration
        self.downloadDuration = downloadDuration
        self.extractionDuration = extractionDuration
        self.totalDuration = totalDuration
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    public func jsonParameters() -> [String: Encodable] {
        Dictionary(compacting: [
            ("feature.data.ext.from_version", fromVersion),
            ("feature.data.ext.from_build", fromBuild),
            ("feature.data.ext.to_version", toVersion),
            ("feature.data.ext.to_build", toBuild),
            ("feature.data.ext.update_type", updateType?.rawValue),
            ("feature.data.ext.initiation_type", initiationType.rawValue),
            ("feature.data.ext.update_configuration", updateConfiguration.rawValue),
            ("feature.data.ext.last_known_step", lastKnownStep?.rawValue),
            ("feature.data.ext.os_version", osVersion),
            ("feature.data.ext.cancellation_reason", cancellationReason?.rawValue),
            ("feature.data.ext.disk_space_remaining_bytes", diskSpaceRemainingBytes),
            ("feature.data.ext.time_since_last_update", timeSinceLastUpdateBucket?.rawValue),
            ("feature.data.ext.update_check_duration_ms", updateCheckDuration?.intValue(.noBucketing)),
            ("feature.data.ext.download_duration_ms", downloadDuration?.intValue(.noBucketing)),
            ("feature.data.ext.extraction_duration_ms", extractionDuration?.intValue(.noBucketing)),
            ("feature.data.ext.total_duration_ms", totalDuration?.intValue(.noBucketing)),
        ])
    }

    /// Returns available disk space in bytes.
    ///
    /// Uses `volumeAvailableCapacityForImportantUsage` which returns space available for
    /// important operations, excluding purgeable content that may not be immediately available.
    ///
    /// - Returns: Available disk space in bytes, or nil if unable to determine
    ///
    /// - Note: Called only on update FAILURE to help diagnose whether insufficient disk space
    ///   caused the failure.
    public static func getAvailableDiskSpace() -> UInt64? {
        guard let homeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        do {
            let values = try homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage.map { UInt64($0) }
        } catch {
            return nil
        }
    }
}
