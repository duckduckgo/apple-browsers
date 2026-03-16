//
//  DataClearingWideEventData.swift
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
import PixelKit

/// Wide event data for tracking data clearing operations.
///
/// This class captures comprehensive telemetry about data clearing flows, including:
/// - Overall clearing duration and status
/// - Per-action latency and error tracking
/// - Platform-specific metadata (iOS vs macOS)
/// - User selection context (options, trigger, scope)
///
/// The implementation follows the fire-and-forget pattern where overall status is either
/// SUCCESS or UNKNOWN (no FAILURE status), while individual actions can still report failures.
public class DataClearingWideEventData: WideEventData {

    // MARK: - Metadata

    public static let metadata = WideEventMetadata(
        pixelName: "data_clearing",
        featureName: "data-clearing",
        mobileMetaType: "ios-data-clearing",
        desktopMetaType: "macos-data-clearing",
        version: "1.0.0"
    )

    public static let clearingTimeout: TimeInterval = .minutes(15)

    // MARK: - WideEventData Required Properties

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData
    public var errorData: WideEventErrorData?

    // MARK: - Shared Feature Properties

    /// What data the user selected for clearing.
    public var options: Options

    /// What initiated the clearing flow.
    public var trigger: Trigger

    /// Overall duration from start of clearing attempt to end state.
    public var overallDuration: WideEvent.MeasuredInterval?

    // MARK: - iOS-Specific Properties

    /// Scope of the clearing action (iOS only).
    public var scope: Scope?

    /// Entry point that triggered the data clearing flow (iOS only).
    public var source: Source?

    // MARK: - macOS-Specific Properties

    /// Execution path during clearing (macOS only).
    public var path: Path?

    /// Comma-separated list of domain categories included (macOS only).
    public var includedDomains: String?

    // MARK: - Per-Action Properties

    // Shared actions
    public var clearTabsDuration: WideEvent.MeasuredInterval?
    public var clearTabsStatus: ActionStatus?
    public var clearTabsError: WideEventErrorData?

    public var clearSafelyRemovableWebsiteDataDuration: WideEvent.MeasuredInterval?
    public var clearSafelyRemovableWebsiteDataStatus: ActionStatus?
    public var clearSafelyRemovableWebsiteDataError: WideEventErrorData?

    public var clearFireproofableDataForNonFireproofDomainsDuration: WideEvent.MeasuredInterval?
    public var clearFireproofableDataForNonFireproofDomainsStatus: ActionStatus?
    public var clearFireproofableDataForNonFireproofDomainsError: WideEventErrorData?

    public var clearCookiesForNonFireproofedDomainsDuration: WideEvent.MeasuredInterval?
    public var clearCookiesForNonFireproofedDomainsStatus: ActionStatus?
    public var clearCookiesForNonFireproofedDomainsError: WideEventErrorData?

    public var clearAllHistoryDuration: WideEvent.MeasuredInterval?
    public var clearAllHistoryStatus: ActionStatus?
    public var clearAllHistoryError: WideEventErrorData?

    public var clearAIChatHistoryDuration: WideEvent.MeasuredInterval?
    public var clearAIChatHistoryStatus: ActionStatus?
    public var clearAIChatHistoryError: WideEventErrorData?

    public var clearAutoconsentManagementCacheDuration: WideEvent.MeasuredInterval?
    public var clearAutoconsentManagementCacheStatus: ActionStatus?
    public var clearAutoconsentManagementCacheError: WideEventErrorData?

    public var clearFaviconCacheDuration: WideEvent.MeasuredInterval?
    public var clearFaviconCacheStatus: ActionStatus?
    public var clearFaviconCacheError: WideEventErrorData?

    public var cancelAllDownloadsDuration: WideEvent.MeasuredInterval?
    public var cancelAllDownloadsStatus: ActionStatus?
    public var cancelAllDownloadsError: WideEventErrorData?

    public var clearBookmarkDatabaseDuration: WideEvent.MeasuredInterval?
    public var clearBookmarkDatabaseStatus: ActionStatus?
    public var clearBookmarkDatabaseError: WideEventErrorData?

    public var forgetTextZoomDuration: WideEvent.MeasuredInterval?
    public var forgetTextZoomStatus: ActionStatus?
    public var forgetTextZoomError: WideEventErrorData?

    public var clearPrivacyStatsDuration: WideEvent.MeasuredInterval?
    public var clearPrivacyStatsStatus: ActionStatus?
    public var clearPrivacyStatsError: WideEventErrorData?

    // iOS-only actions
    public var clearURLCachesDuration: WideEvent.MeasuredInterval?
    public var clearURLCachesStatus: ActionStatus?
    public var clearURLCachesError: WideEventErrorData?

    public var clearDaxDialogsHeldURLDataDuration: WideEvent.MeasuredInterval?
    public var clearDaxDialogsHeldURLDataStatus: ActionStatus?
    public var clearDaxDialogsHeldURLDataError: WideEventErrorData?

    public var removeObservationsDataDuration: WideEvent.MeasuredInterval?
    public var removeObservationsDataStatus: ActionStatus?
    public var removeObservationsDataError: WideEventErrorData?

    public var removeAllContainersAfterDelayDuration: WideEvent.MeasuredInterval?
    public var removeAllContainersAfterDelayStatus: ActionStatus?
    public var removeAllContainersAfterDelayError: WideEventErrorData?

    // macOS-only actions
    public var clearPermissionsDuration: WideEvent.MeasuredInterval?
    public var clearPermissionsStatus: ActionStatus?
    public var clearPermissionsError: WideEventErrorData?

    public var clearVisitedLinksDuration: WideEvent.MeasuredInterval?
    public var clearVisitedLinksStatus: ActionStatus?
    public var clearVisitedLinksError: WideEventErrorData?

    public var clearRecentlyClosedDuration: WideEvent.MeasuredInterval?
    public var clearRecentlyClosedStatus: ActionStatus?
    public var clearRecentlyClosedError: WideEventErrorData?

    public var clearLastSessionStateDuration: WideEvent.MeasuredInterval?
    public var clearLastSessionStateStatus: ActionStatus?
    public var clearLastSessionStateError: WideEventErrorData?

    public var resetCookiePopupBlockedFlagDuration: WideEvent.MeasuredInterval?
    public var resetCookiePopupBlockedFlagStatus: ActionStatus?
    public var resetCookiePopupBlockedFlagError: WideEventErrorData?

    public var clearAutoconsentStatsDuration: WideEvent.MeasuredInterval?
    public var clearAutoconsentStatsStatus: ActionStatus?
    public var clearAutoconsentStatsError: WideEventErrorData?

    public var clearVisitsDuration: WideEvent.MeasuredInterval?
    public var clearVisitsStatus: ActionStatus?
    public var clearVisitsError: WideEventErrorData?

    public var clearFileCacheDuration: WideEvent.MeasuredInterval?
    public var clearFileCacheStatus: ActionStatus?
    public var clearFileCacheError: WideEventErrorData?

    public var clearDeviceHashSaltsDuration: WideEvent.MeasuredInterval?
    public var clearDeviceHashSaltsStatus: ActionStatus?
    public var clearDeviceHashSaltsError: WideEventErrorData?

    public var clearRemoveResourceLoadStatisticsDatabaseDuration: WideEvent.MeasuredInterval?
    public var clearRemoveResourceLoadStatisticsDatabaseStatus: ActionStatus?
    public var clearRemoveResourceLoadStatisticsDatabaseError: WideEventErrorData?

    // MARK: - Initialization

    public init(
        options: Options,
        trigger: Trigger,
        overallDuration: WideEvent.MeasuredInterval? = nil,
        scope: Scope? = nil,
        source: Source? = nil,
        path: Path? = nil,
        includedDomains: String? = nil,
        contextData: WideEventContextData,
        appData: WideEventAppData = WideEventAppData(),
        globalData: WideEventGlobalData = WideEventGlobalData()
    ) {
        self.options = options
        self.trigger = trigger
        self.overallDuration = overallDuration
        self.scope = scope
        self.source = source
        self.path = path
        self.includedDomains = includedDomains
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    // MARK: - WideEventData Protocol

    public func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        switch trigger {
        case .appLaunch:
            guard let start = overallDuration?.start else {
                return .complete(.unknown(reason: StatusReason.partialData.rawValue))
            }

            guard overallDuration?.end == nil else {
                return .complete(.unknown(reason: StatusReason.partialData.rawValue))
            }

            if Date() >= start.addingTimeInterval(Self.clearingTimeout) {
                return .complete(.unknown(reason: StatusReason.timeout.rawValue))
            }

            return .keepPending
        }
    }
}

// MARK: - Public Types

extension DataClearingWideEventData {

    /// What data the user selected for clearing.
    public enum Options: String, Codable, CaseIterable {
        // iOS options
        case tab
        case data
        case aiChats = "aichats"
        case all

        // macOS options
        case currentTab
        case currentWindow
        case allData
    }

    /// What initiated the clearing flow.
    public enum Trigger: String, Codable, CaseIterable {
        // iOS triggers
        case manualFire
        case autoClearOnLaunch
        case autoClearOnForeground

        // macOS triggers
        case manual
        case autoClear
    }

    /// Scope of the clearing action (iOS only).
    public enum Scope: String, Codable, CaseIterable {
        case tab
        case all
    }

    /// Entry point that triggered the data clearing flow (iOS only).
    public enum Source: String, Codable, CaseIterable {
        case browsing
        case tabSwitcher
        case settings
        case quickFire
        case deeplink
        case autoClear
    }

    /// Execution path during clearing (macOS only).
    public enum Path: String, Codable, CaseIterable {
        case burnEntity
        case burnAll
        case burnVisits
    }

    /// Status reason for unknown/incomplete clearing attempts.
    public enum StatusReason: String, Codable, CaseIterable {
        case partialData = "partial_data"
        case timeout
    }

    /// Per-action completion status.
    public enum ActionStatus: String, Codable, CaseIterable {
        case success = "SUCCESS"
        case failure = "FAILURE"
    }

    /// All trackable data clearing actions.
    public enum Action: String, Codable, CaseIterable {
        // Shared actions
        case clearTabs = "clear_tabs"
        case clearSafelyRemovableWebsiteData = "clear_website_data.clear_safely_removable_website_data"
        case clearFireproofableDataForNonFireproofDomains = "clear_website_data.clear_fireproofable_data_for_nonFireproof_domains"
        case clearCookiesForNonFireproofedDomains = "clear_website_data.clear_cookies_for_nonFireproofed_domains"
        case clearAllHistory = "clear_all_history"
        case clearAIChatHistory = "clear_aiChat_history"
        case clearAutoconsentManagementCache = "clear_autoconsent_management_cache"
        case clearFaviconCache = "clear_favicon_cache"
        case cancelAllDownloads = "cancel_all_downloads"
        case clearBookmarkDatabase = "clear_bookmark_database"
        case forgetTextZoom = "forget_text_zoom"
        case clearPrivacyStats = "clear_privacy_stats"

        // iOS-only actions
        case clearURLCaches = "clear_url_caches"
        case clearDaxDialogsHeldURLData = "clear_daxDialogs_held_URL_data"
        case removeObservationsData = "clear_website_data.remove_observations_data"
        case removeAllContainersAfterDelay = "clear_website_data.remove_all_containers_after_delay"

        // macOS-only actions
        case clearPermissions = "clear_permissions"
        case clearVisitedLinks = "clear_visited_links"
        case clearRecentlyClosed = "clear_recently_closed"
        case clearLastSessionState = "clear_last_session_state"
        case resetCookiePopupBlockedFlag = "reset_cookie_popup_blocked_flag"
        case clearAutoconsentStats = "clear_autoconsent_stats"
        case clearVisits = "clear_visits"
        case clearFileCache = "clear_website_data.clear_file_cache"
        case clearDeviceHashSalts = "clear_website_data.clear_device_hash_salts"
        case clearRemoveResourceLoadStatisticsDatabase = "clear_website_data.clear_remove_resource_load_statistics_database"

        /// Returns the keypath for accessing this action's duration property.
        public var durationPath: WritableKeyPath<DataClearingWideEventData, WideEvent.MeasuredInterval?> {
            switch self {
            case .clearTabs: return \.clearTabsDuration
            case .clearSafelyRemovableWebsiteData: return \.clearSafelyRemovableWebsiteDataDuration
            case .clearFireproofableDataForNonFireproofDomains: return \.clearFireproofableDataForNonFireproofDomainsDuration
            case .clearCookiesForNonFireproofedDomains: return \.clearCookiesForNonFireproofedDomainsDuration
            case .clearAllHistory: return \.clearAllHistoryDuration
            case .clearAIChatHistory: return \.clearAIChatHistoryDuration
            case .clearAutoconsentManagementCache: return \.clearAutoconsentManagementCacheDuration
            case .clearFaviconCache: return \.clearFaviconCacheDuration
            case .cancelAllDownloads: return \.cancelAllDownloadsDuration
            case .clearBookmarkDatabase: return \.clearBookmarkDatabaseDuration
            case .forgetTextZoom: return \.forgetTextZoomDuration
            case .clearPrivacyStats: return \.clearPrivacyStatsDuration
            case .clearURLCaches: return \.clearURLCachesDuration
            case .clearDaxDialogsHeldURLData: return \.clearDaxDialogsHeldURLDataDuration
            case .removeObservationsData: return \.removeObservationsDataDuration
            case .removeAllContainersAfterDelay: return \.removeAllContainersAfterDelayDuration
            case .clearPermissions: return \.clearPermissionsDuration
            case .clearVisitedLinks: return \.clearVisitedLinksDuration
            case .clearRecentlyClosed: return \.clearRecentlyClosedDuration
            case .clearLastSessionState: return \.clearLastSessionStateDuration
            case .resetCookiePopupBlockedFlag: return \.resetCookiePopupBlockedFlagDuration
            case .clearAutoconsentStats: return \.clearAutoconsentStatsDuration
            case .clearVisits: return \.clearVisitsDuration
            case .clearFileCache: return \.clearFileCacheDuration
            case .clearDeviceHashSalts: return \.clearDeviceHashSaltsDuration
            case .clearRemoveResourceLoadStatisticsDatabase: return \.clearRemoveResourceLoadStatisticsDatabaseDuration
            }
        }

        /// Returns the keypath for accessing this action's status property.
        public var statusPath: WritableKeyPath<DataClearingWideEventData, ActionStatus?> {
            switch self {
            case .clearTabs: return \.clearTabsStatus
            case .clearSafelyRemovableWebsiteData: return \.clearSafelyRemovableWebsiteDataStatus
            case .clearFireproofableDataForNonFireproofDomains: return \.clearFireproofableDataForNonFireproofDomainsStatus
            case .clearCookiesForNonFireproofedDomains: return \.clearCookiesForNonFireproofedDomainsStatus
            case .clearAllHistory: return \.clearAllHistoryStatus
            case .clearAIChatHistory: return \.clearAIChatHistoryStatus
            case .clearAutoconsentManagementCache: return \.clearAutoconsentManagementCacheStatus
            case .clearFaviconCache: return \.clearFaviconCacheStatus
            case .cancelAllDownloads: return \.cancelAllDownloadsStatus
            case .clearBookmarkDatabase: return \.clearBookmarkDatabaseStatus
            case .forgetTextZoom: return \.forgetTextZoomStatus
            case .clearPrivacyStats: return \.clearPrivacyStatsStatus
            case .clearURLCaches: return \.clearURLCachesStatus
            case .clearDaxDialogsHeldURLData: return \.clearDaxDialogsHeldURLDataStatus
            case .removeObservationsData: return \.removeObservationsDataStatus
            case .removeAllContainersAfterDelay: return \.removeAllContainersAfterDelayStatus
            case .clearPermissions: return \.clearPermissionsStatus
            case .clearVisitedLinks: return \.clearVisitedLinksStatus
            case .clearRecentlyClosed: return \.clearRecentlyClosedStatus
            case .clearLastSessionState: return \.clearLastSessionStateStatus
            case .resetCookiePopupBlockedFlag: return \.resetCookiePopupBlockedFlagStatus
            case .clearAutoconsentStats: return \.clearAutoconsentStatsStatus
            case .clearVisits: return \.clearVisitsStatus
            case .clearFileCache: return \.clearFileCacheStatus
            case .clearDeviceHashSalts: return \.clearDeviceHashSaltsStatus
            case .clearRemoveResourceLoadStatisticsDatabase: return \.clearRemoveResourceLoadStatisticsDatabaseStatus
            }
        }

        /// Returns the keypath for accessing this action's error property.
        public var errorPath: WritableKeyPath<DataClearingWideEventData, WideEventErrorData?> {
            switch self {
            case .clearTabs: return \.clearTabsError
            case .clearSafelyRemovableWebsiteData: return \.clearSafelyRemovableWebsiteDataError
            case .clearFireproofableDataForNonFireproofDomains: return \.clearFireproofableDataForNonFireproofDomainsError
            case .clearCookiesForNonFireproofedDomains: return \.clearCookiesForNonFireproofedDomainsError
            case .clearAllHistory: return \.clearAllHistoryError
            case .clearAIChatHistory: return \.clearAIChatHistoryError
            case .clearAutoconsentManagementCache: return \.clearAutoconsentManagementCacheError
            case .clearFaviconCache: return \.clearFaviconCacheError
            case .cancelAllDownloads: return \.cancelAllDownloadsError
            case .clearBookmarkDatabase: return \.clearBookmarkDatabaseError
            case .forgetTextZoom: return \.forgetTextZoomError
            case .clearPrivacyStats: return \.clearPrivacyStatsError
            case .clearURLCaches: return \.clearURLCachesError
            case .clearDaxDialogsHeldURLData: return \.clearDaxDialogsHeldURLDataError
            case .removeObservationsData: return \.removeObservationsDataError
            case .removeAllContainersAfterDelay: return \.removeAllContainersAfterDelayError
            case .clearPermissions: return \.clearPermissionsError
            case .clearVisitedLinks: return \.clearVisitedLinksError
            case .clearRecentlyClosed: return \.clearRecentlyClosedError
            case .clearLastSessionState: return \.clearLastSessionStateError
            case .resetCookiePopupBlockedFlag: return \.resetCookiePopupBlockedFlagError
            case .clearAutoconsentStats: return \.clearAutoconsentStatsError
            case .clearVisits: return \.clearVisitsError
            case .clearFileCache: return \.clearFileCacheError
            case .clearDeviceHashSalts: return \.clearDeviceHashSaltsError
            case .clearRemoveResourceLoadStatisticsDatabase: return \.clearRemoveResourceLoadStatisticsDatabaseError
            }
        }
    }
}

// MARK: - WideEventParameterProviding

extension DataClearingWideEventData {

    public func jsonParameters() -> [String: Encodable] {
        // Process overall latency with rounding and capping
        let processedOverallLatency: Int? = {
            guard let duration = overallDuration?.durationMilliseconds else { return nil }
            return processedDuration(duration)
        }()

        var params: [String: Encodable] = Dictionary(compacting: [
            (WideEventParameter.DataClearingFeature.options, options.rawValue),
            (WideEventParameter.DataClearingFeature.trigger, trigger.rawValue),
            (WideEventParameter.DataClearingFeature.overallLatency, processedOverallLatency),
            (WideEventParameter.DataClearingFeature.scope, scope?.rawValue),
            (WideEventParameter.DataClearingFeature.source, source?.rawValue),
            (WideEventParameter.DataClearingFeature.path, path?.rawValue),
            (WideEventParameter.DataClearingFeature.includedDomains, includedDomains),
        ])

        for action in Action.allCases {
            addActionLatency(self[keyPath: action.durationPath], action: action, to: &params)
            addActionStatus(self[keyPath: action.statusPath], action: action, to: &params)
            addActionError(self[keyPath: action.errorPath], action: action, to: &params)
        }

        return params
    }
}

// MARK: - Private Helpers

private extension DataClearingWideEventData {

    /// Processes duration for pixel reporting: rounds to 10ms precision and caps at 10 seconds.
    ///
    /// This ensures all duration values conform to the pixel schema constraints:
    /// - `multipleOf: 10` - Round to nearest 10ms
    /// - `maximum: 10000` - Cap at 10 seconds (10000ms)
    ///
    /// - Parameter durationMs: Raw duration in milliseconds
    /// - Returns: Processed duration (rounded to 10ms, capped at 10000ms)
    func processedDuration(_ durationMs: Int) -> Int {
        // Round to nearest 10ms
        let rounded = (Double(durationMs) / 10.0).rounded() * 10.0

        // Cap at 10 seconds (10000ms) and ensure non-negative
        let capped = min(max(rounded, 0), 10000.0)

        return Int(capped)
    }

    func addActionLatency(_ interval: WideEvent.MeasuredInterval?, action: Action, to params: inout [String: Encodable]) {
        guard let duration = interval?.durationMilliseconds else { return }
        params[WideEventParameter.DataClearingFeature.latency(at: action)] = processedDuration(duration)
    }

    func addActionStatus(_ status: ActionStatus?, action: Action, to params: inout [String: Encodable]) {
        guard let status else { return }
        params[WideEventParameter.DataClearingFeature.status(at: action)] = status.rawValue
    }

    func addActionError(_ error: WideEventErrorData?, action: Action, to params: inout [String: Encodable]) {
        guard let error else { return }
        let errorParams = error.jsonParameters()
        for (key, value) in errorParams {
            let actionKey = transformErrorKey(key, for: action)
            params[actionKey] = value
        }
    }

    func transformErrorKey(_ key: String, for action: Action) -> String {
        switch key {
        case WideEventParameter.Feature.errorDomain:
            return WideEventParameter.DataClearingFeature.errorDomain(at: action)

        case WideEventParameter.Feature.errorCode:
            return WideEventParameter.DataClearingFeature.errorCode(at: action)

        case WideEventParameter.Feature.errorDescription:
            return WideEventParameter.DataClearingFeature.errorDescription(at: action)

        case let key where key.hasPrefix(WideEventParameter.Feature.underlyingErrorDomain):
            let suffix = key.dropFirst(WideEventParameter.Feature.underlyingErrorDomain.count)
            return WideEventParameter.DataClearingFeature.errorUnderlyingDomain(at: action, suffix: String(suffix))

        case let key where key.hasPrefix(WideEventParameter.Feature.underlyingErrorCode):
            let suffix = key.dropFirst(WideEventParameter.Feature.underlyingErrorCode.count)
            return WideEventParameter.DataClearingFeature.errorUnderlyingCode(at: action, suffix: String(suffix))

        default:
            assertionFailure("Unexpected error parameter key: \(key)")
            return key
        }
    }
}

// MARK: - Wide Event Parameters

extension WideEventParameter {

    /// Parameter keys for data clearing wide events.
    public enum DataClearingFeature {
        static let options = "feature.data.ext.options"
        static let trigger = "feature.data.ext.trigger"
        static let overallLatency = "feature.data.ext.overall_latency_ms"
        static let scope = "feature.data.ext.scope"
        static let source = "feature.data.ext.source"
        static let path = "feature.data.ext.path"
        static let includedDomains = "feature.data.ext.included_domains"

        static func latency(at action: DataClearingWideEventData.Action) -> String {
            "feature.data.ext.\(action.rawValue)_latency_ms"
        }

        static func status(at action: DataClearingWideEventData.Action) -> String {
            "feature.data.ext.\(action.rawValue)_status"
        }

        static func errorDomain(at action: DataClearingWideEventData.Action) -> String {
            "feature.data.ext.\(action.rawValue)_error.domain"
        }

        static func errorCode(at action: DataClearingWideEventData.Action) -> String {
            "feature.data.ext.\(action.rawValue)_error.code"
        }

        static func errorDescription(at action: DataClearingWideEventData.Action) -> String {
            "feature.data.ext.\(action.rawValue)_error.description"
        }

        static func errorUnderlyingDomain(at action: DataClearingWideEventData.Action, suffix: String) -> String {
            return "feature.data.ext.\(action.rawValue)_error.underlying_domain\(suffix)"
        }

        static func errorUnderlyingCode(at action: DataClearingWideEventData.Action, suffix: String) -> String {
            return "feature.data.ext.\(action.rawValue)_error.underlying_code\(suffix)"
        }
    }
}
