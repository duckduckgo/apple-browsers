//
//  DataClearingWideEventDataTests.swift
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

import XCTest
import PixelKit
@testable import BrowserServicesKit

final class DataClearingWideEventDataTests: XCTestCase {

    // MARK: - A. Initialization Tests

    func testInitialization_withMinimalRequiredFields() {
        // Given
        let contextData = WideEventContextData(name: "test-context")

        // When
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: contextData
        )

        // Then
        XCTAssertEqual(eventData.options, .all)
        XCTAssertEqual(eventData.trigger, .manualFire)
        XCTAssertNil(eventData.overallDuration)
        XCTAssertNil(eventData.scope)
        XCTAssertNil(eventData.source)
        XCTAssertNil(eventData.path)
        XCTAssertNil(eventData.includedDomains)
    }

    func testInitialization_withAllIOSFields() {
        // Given
        let contextData = WideEventContextData(name: "test-context")
        let base = Date()

        // When
        let eventData = DataClearingWideEventData(
            options: .tab,
            trigger: .manualFire,
            overallDuration: WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(2.5)),
            scope: .tab,
            source: .browsing,
            contextData: contextData
        )

        // Then
        XCTAssertEqual(eventData.options, .tab)
        XCTAssertEqual(eventData.trigger, .manualFire)
        XCTAssertEqual(eventData.scope, .tab)
        XCTAssertEqual(eventData.source, .browsing)
        XCTAssertNotNil(eventData.overallDuration)
        XCTAssertNil(eventData.path)
        XCTAssertNil(eventData.includedDomains)
    }

    func testInitialization_withAllMacOSFields() {
        // Given
        let contextData = WideEventContextData(name: "test-context")
        let base = Date()

        // When
        let eventData = DataClearingWideEventData(
            options: .currentWindow,
            trigger: .manual,
            overallDuration: WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(3.5)),
            path: .burnEntity,
            includedDomains: "History,TabsAndWindows",
            contextData: contextData
        )

        // Then
        XCTAssertEqual(eventData.options, .currentWindow)
        XCTAssertEqual(eventData.trigger, .manual)
        XCTAssertEqual(eventData.path, .burnEntity)
        XCTAssertEqual(eventData.includedDomains, "History,TabsAndWindows")
        XCTAssertNotNil(eventData.overallDuration)
        XCTAssertNil(eventData.scope)
        XCTAssertNil(eventData.source)
    }

    // MARK: - B. JSON Parameters - Basic Fields

    func testJSONParameters_includesRequiredFields() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.options"] as? String, "all")
        XCTAssertEqual(params["feature.data.ext.trigger"] as? String, "manualFire")
    }

    func testJSONParameters_includesOverallDuration() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(2.5)
        )

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.overall_latency_ms"] as? Int, 2500)
    }

    func testJSONParameters_includesIOSOnlyFields() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .tab,
            trigger: .manualFire,
            scope: .tab,
            source: .browsing,
            contextData: WideEventContextData(name: "test-context")
        )

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.scope"] as? String, "tab")
        XCTAssertEqual(params["feature.data.ext.source"] as? String, "browsing")
    }

    func testJSONParameters_includesMacOSOnlyFields() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .currentTab,
            trigger: .manual,
            path: .burnAll,
            includedDomains: "History,CookiesAndSiteData",
            contextData: WideEventContextData(name: "test-context")
        )

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.path"] as? String, "burnAll")
        XCTAssertEqual(params["feature.data.ext.included_domains"] as? String, "History,CookiesAndSiteData")
    }

    func testJSONParameters_excludesNilOptionalFields() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertNil(params["feature.data.ext.overall_latency_ms"])
        XCTAssertNil(params["feature.data.ext.scope"])
        XCTAssertNil(params["feature.data.ext.source"])
        XCTAssertNil(params["feature.data.ext.path"])
        XCTAssertNil(params["feature.data.ext.included_domains"])
    }

    // MARK: - C. JSON Parameters - Per-Action Fields

    func testJSONParameters_includesActionLatency() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        eventData.clearTabsDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(0.5)
        )

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.clear_tabs_latency_ms"] as? Int, 500)
    }

    func testJSONParameters_includesActionStatus() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        eventData.clearTabsStatus = .success

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.clear_tabs_status"] as? String, "SUCCESS")
    }

    func testJSONParameters_includesActionError_topLevelOnly() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let error = NSError(domain: "TestDomain", code: 42, userInfo: nil)
        eventData.clearTabsError = WideEventErrorData(error: error, description: "Test error")

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.clear_tabs_error.domain"] as? String, "TestDomain")
        XCTAssertEqual(params["feature.data.ext.clear_tabs_error.code"] as? Int, 42)
        XCTAssertEqual(params["feature.data.ext.clear_tabs_error.description"] as? String, "Test error")
    }

    func testJSONParameters_includesActionError_withSingleUnderlyingError() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let underlyingError = NSError(domain: "UnderlyingDomain", code: 100, userInfo: nil)
        let topError = NSError(domain: "TopDomain", code: 200, userInfo: [
            NSUnderlyingErrorKey: underlyingError
        ])
        eventData.clearAllHistoryError = WideEventErrorData(error: topError)

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.clear_all_history_error.domain"] as? String, "TopDomain")
        XCTAssertEqual(params["feature.data.ext.clear_all_history_error.code"] as? Int, 200)
        XCTAssertEqual(params["feature.data.ext.clear_all_history_error.underlying_domain"] as? String, "UnderlyingDomain")
        XCTAssertEqual(params["feature.data.ext.clear_all_history_error.underlying_code"] as? Int, 100)
    }

    func testJSONParameters_includesActionError_withMultipleUnderlyingErrors() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let underlyingError2 = NSError(domain: "Domain2", code: 2, userInfo: [:])
        let underlyingError1 = NSError(domain: "Domain1", code: 1, userInfo: [
            NSUnderlyingErrorKey: underlyingError2
        ])
        let topError = NSError(domain: "TopDomain", code: 0, userInfo: [
            NSUnderlyingErrorKey: underlyingError1
        ])
        eventData.cancelAllDownloadsError = WideEventErrorData(error: topError)

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.cancel_all_downloads_error.domain"] as? String, "TopDomain")
        XCTAssertEqual(params["feature.data.ext.cancel_all_downloads_error.code"] as? Int, 0)
        XCTAssertEqual(params["feature.data.ext.cancel_all_downloads_error.underlying_domain"] as? String, "Domain1")
        XCTAssertEqual(params["feature.data.ext.cancel_all_downloads_error.underlying_code"] as? Int, 1)
        XCTAssertEqual(params["feature.data.ext.cancel_all_downloads_error.underlying_domain2"] as? String, "Domain2")
        XCTAssertEqual(params["feature.data.ext.cancel_all_downloads_error.underlying_code2"] as? Int, 2)
    }

    func testJSONParameters_excludesNilActionFields() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )

        // When
        let params = eventData.jsonParameters()

        // Then - verify no action fields are included when nil
        for action in DataClearingWideEventData.Action.allCases {
            XCTAssertNil(params["feature.data.ext.\(action.rawValue)_latency_ms"])
            XCTAssertNil(params["feature.data.ext.\(action.rawValue)_status"])
            XCTAssertNil(params["feature.data.ext.\(action.rawValue)_error.domain"])
        }
    }

    // MARK: - D. JSON Parameters - Complete Flow Scenarios

    func testJSONParameters_completeSuccessfulFlow_withMultipleActions() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )

        let base = Date()
        eventData.overallDuration = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(5.0))

        // Set up multiple successful actions
        eventData.clearTabsDuration = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(0.5))
        eventData.clearTabsStatus = .success

        eventData.clearAllHistoryDuration = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(2.0))
        eventData.clearAllHistoryStatus = .success

        eventData.clearFaviconCacheDuration = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(1.0))
        eventData.clearFaviconCacheStatus = .success

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.overall_latency_ms"] as? Int, 5000)
        XCTAssertEqual(params["feature.data.ext.clear_tabs_latency_ms"] as? Int, 500)
        XCTAssertEqual(params["feature.data.ext.clear_tabs_status"] as? String, "SUCCESS")
        XCTAssertEqual(params["feature.data.ext.clear_all_history_latency_ms"] as? Int, 2000)
        XCTAssertEqual(params["feature.data.ext.clear_all_history_status"] as? String, "SUCCESS")
        XCTAssertEqual(params["feature.data.ext.clear_favicon_cache_latency_ms"] as? Int, 1000)
        XCTAssertEqual(params["feature.data.ext.clear_favicon_cache_status"] as? String, "SUCCESS")
    }

    func testJSONParameters_partiallyFailedFlow_withMixedStatuses() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .allData,
            trigger: .manual,
            contextData: WideEventContextData(name: "test-context")
        )

        let base = Date()
        eventData.overallDuration = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(3.5))

        // Success
        eventData.clearTabsStatus = .success
        eventData.clearTabsDuration = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(0.3))

        // Failure with error
        eventData.clearAllHistoryStatus = .failure
        eventData.clearAllHistoryDuration = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(1.5))
        let historyError = NSError(domain: "HistoryError", code: 1, userInfo: nil)
        eventData.clearAllHistoryError = WideEventErrorData(error: historyError, description: "Failed to clear history")

        // Success
        eventData.clearPrivacyStatsStatus = .success
        eventData.clearPrivacyStatsDuration = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(0.1))

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.clear_tabs_status"] as? String, "SUCCESS")
        XCTAssertEqual(params["feature.data.ext.clear_all_history_status"] as? String, "FAILURE")
        XCTAssertEqual(params["feature.data.ext.clear_all_history_error.domain"] as? String, "HistoryError")
        XCTAssertEqual(params["feature.data.ext.clear_all_history_error.code"] as? Int, 1)
        XCTAssertEqual(params["feature.data.ext.clear_all_history_error.description"] as? String, "Failed to clear history")
        XCTAssertEqual(params["feature.data.ext.clear_privacy_stats_status"] as? String, "SUCCESS")
    }

    // MARK: - E. Action KeyPath Tests

    func testActionDurationPath_returnsCorrectKeyPath_forSharedActions() {
        // Given
        var eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        let interval = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(1.0))

        // When & Then - Test a few shared actions
        eventData[keyPath: DataClearingWideEventData.Action.clearTabs.durationPath] = interval
        XCTAssertEqual(eventData.clearTabsDuration?.intValue(.noBucketing), 1000)

        eventData[keyPath: DataClearingWideEventData.Action.clearAllHistory.durationPath] = interval
        XCTAssertEqual(eventData.clearAllHistoryDuration?.intValue(.noBucketing), 1000)

        eventData[keyPath: DataClearingWideEventData.Action.clearFaviconCache.durationPath] = interval
        XCTAssertEqual(eventData.clearFaviconCacheDuration?.intValue(.noBucketing), 1000)
    }

    func testActionDurationPath_returnsCorrectKeyPath_forIOSOnlyActions() {
        // Given
        var eventData = DataClearingWideEventData(
            options: .tab,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        let interval = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(0.5))

        // When & Then
        eventData[keyPath: DataClearingWideEventData.Action.clearURLCaches.durationPath] = interval
        XCTAssertEqual(eventData.clearURLCachesDuration?.intValue(.noBucketing), 500)

        eventData[keyPath: DataClearingWideEventData.Action.removeAllContainersAfterDelay.durationPath] = interval
        XCTAssertEqual(eventData.removeAllContainersAfterDelayDuration?.intValue(.noBucketing), 500)
    }

    func testActionDurationPath_returnsCorrectKeyPath_forMacOSOnlyActions() {
        // Given
        var eventData = DataClearingWideEventData(
            options: .currentTab,
            trigger: .manual,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date(timeIntervalSince1970: 0)
        let interval = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(0.35))

        // When & Then
        eventData[keyPath: DataClearingWideEventData.Action.clearVisitedLinks.durationPath] = interval
        XCTAssertEqual(eventData.clearVisitedLinksDuration?.intValue(.noBucketing), 350)

        eventData[keyPath: DataClearingWideEventData.Action.clearLastSessionState.durationPath] = interval
        XCTAssertEqual(eventData.clearLastSessionStateDuration?.intValue(.noBucketing), 350)
    }

    func testActionStatusPath_returnsCorrectKeyPath() {
        // Given
        var eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )

        // When & Then
        eventData[keyPath: DataClearingWideEventData.Action.clearTabs.statusPath] = .success
        XCTAssertEqual(eventData.clearTabsStatus, .success)

        eventData[keyPath: DataClearingWideEventData.Action.clearAllHistory.statusPath] = .failure
        XCTAssertEqual(eventData.clearAllHistoryStatus, .failure)
    }

    func testActionErrorPath_returnsCorrectKeyPath() {
        // Given
        var eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let error = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let errorData = WideEventErrorData(error: error)

        // When & Then
        eventData[keyPath: DataClearingWideEventData.Action.clearTabs.errorPath] = errorData
        XCTAssertEqual(eventData.clearTabsError?.domain, "TestDomain")

        eventData[keyPath: DataClearingWideEventData.Action.clearPrivacyStats.errorPath] = errorData
        XCTAssertEqual(eventData.clearPrivacyStatsError?.domain, "TestDomain")
    }

    func testAllActionKeyPaths_areAccessible() {
        // Given
        var eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        let interval = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(1.0))
        let error = WideEventErrorData(error: NSError(domain: "TestDomain", code: 1, userInfo: nil))

        // When & Then - verify all actions have accessible keypaths
        for action in DataClearingWideEventData.Action.allCases {
            // This should not crash
            eventData[keyPath: action.durationPath] = interval
            eventData[keyPath: action.statusPath] = .success
            eventData[keyPath: action.errorPath] = error

            XCTAssertNotNil(eventData[keyPath: action.durationPath])
            XCTAssertNotNil(eventData[keyPath: action.statusPath])
            XCTAssertNotNil(eventData[keyPath: action.errorPath])
        }
    }

    // MARK: - F. Enum Raw Value Tests

    func testOptionsEnum_rawValues_matchSpec() {
        // iOS options
        XCTAssertEqual(DataClearingWideEventData.Options.tab.rawValue, "tab")
        XCTAssertEqual(DataClearingWideEventData.Options.data.rawValue, "data")
        XCTAssertEqual(DataClearingWideEventData.Options.aiChats.rawValue, "aichats")
        XCTAssertEqual(DataClearingWideEventData.Options.all.rawValue, "all")

        // macOS options
        XCTAssertEqual(DataClearingWideEventData.Options.currentTab.rawValue, "currentTab")
        XCTAssertEqual(DataClearingWideEventData.Options.currentWindow.rawValue, "currentWindow")
        XCTAssertEqual(DataClearingWideEventData.Options.allData.rawValue, "allData")
    }

    func testTriggerEnum_rawValues_matchSpec() {
        // iOS triggers
        XCTAssertEqual(DataClearingWideEventData.Trigger.manualFire.rawValue, "manualFire")
        XCTAssertEqual(DataClearingWideEventData.Trigger.autoClearOnLaunch.rawValue, "autoClearOnLaunch")
        XCTAssertEqual(DataClearingWideEventData.Trigger.autoClearOnForeground.rawValue, "autoClearOnForeground")

        // macOS triggers
        XCTAssertEqual(DataClearingWideEventData.Trigger.manual.rawValue, "manual")
        XCTAssertEqual(DataClearingWideEventData.Trigger.autoClear.rawValue, "autoClear")
    }

    func testScopeEnum_rawValues_matchSpec() {
        XCTAssertEqual(DataClearingWideEventData.Scope.tab.rawValue, "tab")
        XCTAssertEqual(DataClearingWideEventData.Scope.all.rawValue, "all")
    }

    func testSourceEnum_rawValues_matchSpec() {
        XCTAssertEqual(DataClearingWideEventData.Source.browsing.rawValue, "browsing")
        XCTAssertEqual(DataClearingWideEventData.Source.tabSwitcher.rawValue, "tabSwitcher")
        XCTAssertEqual(DataClearingWideEventData.Source.settings.rawValue, "settings")
        XCTAssertEqual(DataClearingWideEventData.Source.quickFire.rawValue, "quickFire")
        XCTAssertEqual(DataClearingWideEventData.Source.deeplink.rawValue, "deeplink")
        XCTAssertEqual(DataClearingWideEventData.Source.autoClear.rawValue, "autoClear")
    }

    func testPathEnum_rawValues_matchSpec() {
        XCTAssertEqual(DataClearingWideEventData.Path.burnEntity.rawValue, "burnEntity")
        XCTAssertEqual(DataClearingWideEventData.Path.burnAll.rawValue, "burnAll")
        XCTAssertEqual(DataClearingWideEventData.Path.burnVisits.rawValue, "burnVisits")
    }

    func testActionStatusEnum_rawValues_matchSpec() {
        XCTAssertEqual(DataClearingWideEventData.ActionStatus.success.rawValue, "SUCCESS")
        XCTAssertEqual(DataClearingWideEventData.ActionStatus.failure.rawValue, "FAILURE")
    }

    func testStatusReasonEnum_rawValues_matchSpec() {
        XCTAssertEqual(DataClearingWideEventData.StatusReason.partialData.rawValue, "partial_data")
        XCTAssertEqual(DataClearingWideEventData.StatusReason.timeout.rawValue, "timeout")
    }

    func testActionEnum_rawValues_matchSpec() {
        // Shared actions
        XCTAssertEqual(DataClearingWideEventData.Action.clearTabs.rawValue, "clear_tabs")
        XCTAssertEqual(DataClearingWideEventData.Action.clearSafelyRemovableWebsiteData.rawValue, "clear_website_data.clear_safely_removable_website_data")
        XCTAssertEqual(DataClearingWideEventData.Action.clearAllHistory.rawValue, "clear_all_history")

        // iOS-only actions
        XCTAssertEqual(DataClearingWideEventData.Action.clearURLCaches.rawValue, "clear_url_caches")
        XCTAssertEqual(DataClearingWideEventData.Action.removeAllContainersAfterDelay.rawValue, "clear_website_data.remove_all_containers_after_delay")

        // macOS-only actions
        XCTAssertEqual(DataClearingWideEventData.Action.clearVisitedLinks.rawValue, "clear_visited_links")
        XCTAssertEqual(DataClearingWideEventData.Action.clearLastSessionState.rawValue, "clear_last_session_state")
        XCTAssertEqual(DataClearingWideEventData.Action.clearRemoveResourceLoadStatisticsDatabase.rawValue, "clear_website_data.clear_remove_resource_load_statistics_database")
    }

    // MARK: - G. Completion Decision Tests

    func testCompletionDecision_noOverallDurationStart_returnsPartialData() async {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )

        // When
        let decision = await eventData.completionDecision(for: .appLaunch)

        // Then
        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: DataClearingWideEventData.StatusReason.partialData.rawValue))
        case .keepPending:
            XCTFail("Expected completion with partial data")
        }
    }

    func testCompletionDecision_intervalAlreadyCompleted_returnsPartialData() async {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let start = Date()
        eventData.overallDuration = WideEvent.MeasuredInterval(start: start, end: start.addingTimeInterval(2.0))

        // When
        let decision = await eventData.completionDecision(for: .appLaunch)

        // Then
        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: DataClearingWideEventData.StatusReason.partialData.rawValue))
        case .keepPending:
            XCTFail("Expected completion with partial data")
        }
    }

    func testCompletionDecision_clearingTimeoutExceeded_returnsTimeout() async {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let start = Date().addingTimeInterval(-DataClearingWideEventData.clearingTimeout - 1)
        eventData.overallDuration = WideEvent.MeasuredInterval(start: start, end: nil)

        // When
        let decision = await eventData.completionDecision(for: .appLaunch)

        // Then
        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: DataClearingWideEventData.StatusReason.timeout.rawValue))
        case .keepPending:
            XCTFail("Expected completion with timeout")
        }
    }

    func testCompletionDecision_withinTimeout_returnsKeepPending() async {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let start = Date().addingTimeInterval(-DataClearingWideEventData.clearingTimeout + 60)
        eventData.overallDuration = WideEvent.MeasuredInterval(start: start, end: nil)

        // When
        let decision = await eventData.completionDecision(for: .appLaunch)

        // Then
        switch decision {
        case .keepPending:
            break
        case .complete:
            XCTFail("Expected keep pending")
        }
    }

    // MARK: - H. Edge Cases

    func testDurationFormatting_roundsTo10msPrecision() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        // Duration with fractional milliseconds (1234.567ms → rounds to 1230ms)
        eventData.clearTabsDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.234567)
        )

        // When
        let params = eventData.jsonParameters()

        // Then - verify duration is rounded to nearest 10ms
        XCTAssertEqual(params["feature.data.ext.clear_tabs_latency_ms"] as? Int, 1230)
    }

    func testDurationFormatting_roundsVariousValues() {
        // Validate rounding behavior while avoiding 5ms boundaries.
        // `durationMilliseconds` truncates from TimeInterval, so tie values can be unstable.
        let testCases: [(inputMs: Int, expected: Int)] = [
            (12, 10),      // 12ms → 10ms (1.2 → 1)
            (18, 20),      // 18ms → 20ms (1.8 → 2)
            (23, 20),      // 23ms → 20ms (2.3 → 2)
            (27, 30),      // 27ms → 30ms (2.7 → 3)
            (33, 30),      // 33ms → 30ms (3.3 → 3)
            (37, 40),      // 37ms → 40ms (3.7 → 4)
            (43, 40),      // 43ms → 40ms (4.3 → 4)
            (47, 50),      // 47ms → 50ms (4.7 → 5)
            (53, 50),      // 53ms → 50ms (5.3 → 5)
            (57, 60),      // 57ms → 60ms (5.7 → 6)
            (123, 120),    // 123ms → 120ms (12.3 → 12)
            (128, 130),    // 128ms → 130ms (12.8 → 13)
            (1234, 1230),  // 1234ms → 1230ms (123.4 → 123)
            (2567, 2570),  // 2567ms → 2570ms (256.7 → 257)
        ]

        for (inputMs, expected) in testCases {
            let eventData = DataClearingWideEventData(
                options: .all,
                trigger: .manualFire,
                contextData: WideEventContextData(name: "test-context")
            )
            // Build an interval from a millisecond value
            let base = Date()
            eventData.clearTabsDuration = WideEvent.MeasuredInterval(
                start: base,
                end: base.addingTimeInterval(Double(inputMs) / 1000.0)
            )

            let params = eventData.jsonParameters()
            XCTAssertEqual(params["feature.data.ext.clear_tabs_latency_ms"] as? Int, expected,
                          "Input \(inputMs)ms should round to \(expected)ms")
        }
    }

    func testDurationFormatting_capsAt10Seconds() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        // Duration of 25.678 seconds (25678ms → rounds to 25680ms → caps to 10000ms)
        eventData.clearTabsDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(25.678)
        )

        // When
        let params = eventData.jsonParameters()

        // Then - verify duration is capped at 10000ms
        XCTAssertEqual(params["feature.data.ext.clear_tabs_latency_ms"] as? Int, 10000)
    }

    func testDurationFormatting_appliesToOverallLatency() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        // Duration of 5.678 seconds (5678ms → rounds to 5680ms)
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(5.678)
        )

        // When
        let params = eventData.jsonParameters()

        // Then - verify overall latency is also processed
        XCTAssertEqual(params["feature.data.ext.overall_latency_ms"] as? Int, 5680)
    }

    func testDurationFormatting_overallLatencyCappedAt10Seconds() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        // Duration of 30 seconds → caps to 10000ms
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(30.0)
        )

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.overall_latency_ms"] as? Int, 10000)
    }

    func testDurationFormatting_exactlyAtCap() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        // Duration of exactly 10 seconds → should equal 10000ms (not capped)
        eventData.clearTabsDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(10.0)
        )

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.clear_tabs_latency_ms"] as? Int, 10000)
    }

    func testDurationFormatting_handlesZero() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        // Zero duration
        eventData.clearTabsDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base
        )

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.clear_tabs_latency_ms"] as? Int, 0)
    }

    func testMetadata_valuesMatchSpec() {
        // Then
        XCTAssertEqual(DataClearingWideEventData.metadata.pixelName, "data_clearing")
        XCTAssertEqual(DataClearingWideEventData.metadata.featureName, "data-clearing")
        #if os(iOS)
        XCTAssertEqual(DataClearingWideEventData.metadata.type, "ios-data-clearing")
        #elseif os(macOS)
        XCTAssertEqual(DataClearingWideEventData.metadata.type, "macos-data-clearing")
        #endif
        XCTAssertEqual(DataClearingWideEventData.metadata.version, "1.0.0")
    }

    func testClearingTimeout_is15Minutes() {
        // Then
        XCTAssertEqual(DataClearingWideEventData.clearingTimeout, .minutes(15))
    }

    func testJSONParameters_withErrorDescription_includesDescription() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let error = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        eventData.clearTabsError = WideEventErrorData(error: error, description: "Custom error description")

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.clear_tabs_error.description"] as? String, "Custom error description")
    }

    func testJSONParameters_withoutErrorDescription_excludesDescription() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        let error = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        eventData.clearTabsError = WideEventErrorData(error: error)

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertNil(params["feature.data.ext.clear_tabs_error.description"])
    }

    func testJSONParameters_withStartOnlyDuration_excludesDuration() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        eventData.clearTabsDuration = WideEvent.MeasuredInterval(start: Date(), end: nil)

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertNil(params["feature.data.ext.clear_tabs_latency_ms"])
    }

    func testJSONParameters_withEndOnlyDuration_excludesDuration() {
        // Given
        let eventData = DataClearingWideEventData(
            options: .all,
            trigger: .manualFire,
            contextData: WideEventContextData(name: "test-context")
        )
        eventData.clearTabsDuration = WideEvent.MeasuredInterval(start: nil, end: Date())

        // When
        let params = eventData.jsonParameters()

        // Then
        XCTAssertNil(params["feature.data.ext.clear_tabs_latency_ms"])
    }
}
