//
//  DataBrokerProtectionMacOSPixels.swift
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
import Common
import BrowserServicesKit
import Configuration
import PixelKit
import DataBrokerProtectionCore

public enum DataBrokerProtectionMacOSPixels {

    // Initialisation failure errors
    case mainAppSetUpFailedSecureVaultInitFailed(error: Error?)
    case backgroundAgentSetUpFailedSecureVaultInitFailed(error: Error?)

    // Backgrond Agent events
    case backgroundAgentStarted
    case backgroundAgentStartedStoppingDueToAnotherInstanceRunning

    // IPC server events
    case ipcServerProfileSavedCalledByApp
    case ipcServerProfileSavedReceivedByAgent
    case ipcServerProfileSavedXPCError(error: Error?)
    case ipcServerImmediateScansInterrupted
    case ipcServerImmediateScansFinishedWithoutError
    case ipcServerImmediateScansFinishedWithError(error: Error?)

    case ipcServerAppLaunchedCalledByApp
    case ipcServerAppLaunchedReceivedByAgent
    case ipcServerAppLaunchedXPCError(error: Error?)
    case ipcServerAppLaunchedScheduledScansBlocked
    case ipcServerAppLaunchedScheduledScansInterrupted
    case ipcServerAppLaunchedScheduledScansFinishedWithoutError
    case ipcServerAppLaunchedScheduledScansFinishedWithError(error: Error?)

    // DataBrokerProtection User Notifications
    case dataBrokerProtectionNotificationSentFirstScanComplete
    case dataBrokerProtectionNotificationOpenedFirstScanComplete
    case dataBrokerProtectionNotificationSentFirstRemoval
    case dataBrokerProtectionNotificationOpenedFirstRemoval
    case dataBrokerProtectionNotificationScheduled2WeeksCheckIn
    case dataBrokerProtectionNotificationOpened2WeeksCheckIn
    case dataBrokerProtectionNotificationSentAllRecordsRemoved
    case dataBrokerProtectionNotificationOpenedAllRecordsRemoved

    // Web UI - loading errors
    case webUILoadingStarted(environment: String)
    case webUILoadingFailed(errorCategory: String)
    case webUILoadingSuccess(environment: String)

    // Home View
    case homeViewShowNoPermissionError
    case homeViewShowWebUI
    case homeViewShowBadPathError
    case homeViewCTAMoveApplicationClicked
    case homeViewCTAGrantPermissionClicked

    // Entitlements
    case entitlementCheckValid
    case entitlementCheckInvalid
    case entitlementCheckError

    // Configuration
    case invalidPayload(Configuration)
    case errorLoadingCachedConfig(Error)
    case failedToParsePrivacyConfig(Error)
}

extension DataBrokerProtectionMacOSPixels: PixelKitEvent {
    public var name: String {
        switch self {

        case .mainAppSetUpFailedSecureVaultInitFailed: return "m_mac_dbp_main-app_set-up-failed_secure-vault-init-failed"
        case .backgroundAgentSetUpFailedSecureVaultInitFailed: return "m_mac_dbp_background-agent_set-up-failed_secure-vault-init-failed"

        case .backgroundAgentStarted: return "m_mac_dbp_background-agent_started"
        case .backgroundAgentStartedStoppingDueToAnotherInstanceRunning: return "m_mac_dbp_background-agent_started_stopping-due-to-another-instance-running"

            // IPC Server Pixels
        case .ipcServerProfileSavedCalledByApp: return "m_mac_dbp_ipc-server_profile-saved_called-by-app"
        case .ipcServerProfileSavedReceivedByAgent: return "m_mac_dbp_ipc-server_profile-saved_received-by-agent"
        case .ipcServerProfileSavedXPCError: return "m_mac_dbp_ipc-server_profile-saved_xpc-error"
        case .ipcServerImmediateScansInterrupted: return "m_mac_dbp_ipc-server_immediate-scans_interrupted"
        case .ipcServerImmediateScansFinishedWithoutError: return "m_mac_dbp_ipc-server_immediate-scans_finished_without-error"
        case .ipcServerImmediateScansFinishedWithError: return "m_mac_dbp_ipc-server_immediate-scans_finished_with-error"

        case .ipcServerAppLaunchedCalledByApp: return "m_mac_dbp_ipc-server_app-launched_called-by-app"
        case .ipcServerAppLaunchedReceivedByAgent: return "m_mac_dbp_ipc-server_app-launched_received-by-agent"
        case .ipcServerAppLaunchedXPCError: return "m_mac_dbp_ipc-server_app-launched_xpc-error"
        case .ipcServerAppLaunchedScheduledScansBlocked: return "m_mac_dbp_ipc-server_app-launched_scheduled-scans_blocked"
        case .ipcServerAppLaunchedScheduledScansInterrupted: return "m_mac_dbp_ipc-server_app-launched_scheduled-scans_interrupted"
        case .ipcServerAppLaunchedScheduledScansFinishedWithoutError: return "m_mac_dbp_ipc-server_app-launched_scheduled-scans_finished_without-error"
        case .ipcServerAppLaunchedScheduledScansFinishedWithError: return "m_mac_dbp_ipc-server_app-launched_scheduled-scans_finished_with-error"

            // User Notifications
        case .dataBrokerProtectionNotificationSentFirstScanComplete:
            return "m_mac_dbp_notification_sent_first_scan_complete"
        case .dataBrokerProtectionNotificationOpenedFirstScanComplete:
            return "m_mac_dbp_notification_opened_first_scan_complete"
        case .dataBrokerProtectionNotificationSentFirstRemoval:
            return "m_mac_dbp_notification_sent_first_removal"
        case .dataBrokerProtectionNotificationOpenedFirstRemoval:
            return "m_mac_dbp_notification_opened_first_removal"
        case .dataBrokerProtectionNotificationScheduled2WeeksCheckIn:
            return "m_mac_dbp_notification_scheduled_2_weeks_check_in"
        case .dataBrokerProtectionNotificationOpened2WeeksCheckIn:
            return "m_mac_dbp_notification_opened_2_weeks_check_in"
        case .dataBrokerProtectionNotificationSentAllRecordsRemoved:
            return "m_mac_dbp_notification_sent_all_records_removed"
        case .dataBrokerProtectionNotificationOpenedAllRecordsRemoved:
            return "m_mac_dbp_notification_opened_all_records_removed"

        case .webUILoadingStarted: return "m_mac_dbp_web_ui_loading_started"
        case .webUILoadingSuccess: return "m_mac_dbp_web_ui_loading_success"
        case .webUILoadingFailed: return "m_mac_dbp_web_ui_loading_failed"

            // Home View
        case .homeViewShowNoPermissionError: return "m_mac_dbp_home_view_show-no-permission-error"
        case .homeViewShowWebUI: return "m_mac_dbp_home_view_show-web-ui"
        case .homeViewShowBadPathError: return "m_mac_dbp_home_view_show-bad-path-error"
        case .homeViewCTAMoveApplicationClicked: return "m_mac_dbp_home_view-cta-move-application-clicked"
        case .homeViewCTAGrantPermissionClicked: return "m_mac_dbp_home_view-cta-grant-permission-clicked"

            // Entitlements
        case .entitlementCheckValid: return "m_mac_dbp_macos_entitlement_valid"
        case .entitlementCheckInvalid: return "m_mac_dbp_macos_entitlement_invalid"
        case .entitlementCheckError: return "m_mac_dbp_macos_entitlement_error"

            // Configuration
        case .invalidPayload(let configuration): return "m_mac_dbp_\(configuration.rawValue)_invalid_payload".lowercased()
        case .errorLoadingCachedConfig: return "m_mac_dbp_configuration_error_loading_cached_config"
        case .failedToParsePrivacyConfig: return "m_mac_dbp_configuration_failed_to_parse"

        }
    }

    public var params: [String: String]? {
        parameters
    }

    public var parameters: [String: String]? {
        switch self {
        case .webUILoadingStarted(let environment):
            return [DataBrokerProtectionSharedPixels.Consts.environmentKey: environment]
        case .webUILoadingSuccess(let environment):
            return [DataBrokerProtectionSharedPixels.Consts.environmentKey: environment]
        case .webUILoadingFailed(let error):
            return [DataBrokerProtectionSharedPixels.Consts.errorCategoryKey: error]
        case .mainAppSetUpFailedSecureVaultInitFailed,
                .backgroundAgentSetUpFailedSecureVaultInitFailed,

                .backgroundAgentStarted,
                .backgroundAgentStartedStoppingDueToAnotherInstanceRunning,
                .dataBrokerProtectionNotificationSentFirstScanComplete,
                .dataBrokerProtectionNotificationOpenedFirstScanComplete,
                .dataBrokerProtectionNotificationSentFirstRemoval,
                .dataBrokerProtectionNotificationOpenedFirstRemoval,
                .dataBrokerProtectionNotificationScheduled2WeeksCheckIn,
                .dataBrokerProtectionNotificationOpened2WeeksCheckIn,
                .dataBrokerProtectionNotificationSentAllRecordsRemoved,
                .dataBrokerProtectionNotificationOpenedAllRecordsRemoved,

                .homeViewShowNoPermissionError,
                .homeViewShowWebUI,
                .homeViewShowBadPathError,
                .homeViewCTAMoveApplicationClicked,
                .homeViewCTAGrantPermissionClicked,

                .entitlementCheckValid,
                .entitlementCheckInvalid,
                .entitlementCheckError,

                .invalidPayload,
                .failedToParsePrivacyConfig:
            return [:]
        case .ipcServerProfileSavedCalledByApp,
                .ipcServerProfileSavedReceivedByAgent,
                .ipcServerProfileSavedXPCError,
                .ipcServerImmediateScansInterrupted,
                .ipcServerImmediateScansFinishedWithoutError,
                .ipcServerImmediateScansFinishedWithError,
                .ipcServerAppLaunchedCalledByApp,
                .ipcServerAppLaunchedReceivedByAgent,
                .ipcServerAppLaunchedXPCError,
                .ipcServerAppLaunchedScheduledScansBlocked,
                .ipcServerAppLaunchedScheduledScansInterrupted,
                .ipcServerAppLaunchedScheduledScansFinishedWithoutError,
                .ipcServerAppLaunchedScheduledScansFinishedWithError:
            return [DataBrokerProtectionSharedPixels.Consts.bundleIDParamKey: Bundle.main.bundleIdentifier ?? "nil"]
        case .errorLoadingCachedConfig(let error):
            return [DataBrokerProtectionSharedPixels.Consts.errorDomainKey: (error as NSError).domain]
        }
    }
}

public class DataBrokerProtectionMacOSPixelsHandler: EventMapping<DataBrokerProtectionMacOSPixels> {

    public init() {
        super.init { event, _, _, _ in
            switch event {
            case .mainAppSetUpFailedSecureVaultInitFailed(error: let error),
                    .backgroundAgentSetUpFailedSecureVaultInitFailed(error: let error),

                    .ipcServerProfileSavedXPCError(error: let error),
                    .ipcServerImmediateScansFinishedWithError(error: let error),
                    .ipcServerAppLaunchedXPCError(error: let error),
                    .ipcServerAppLaunchedScheduledScansFinishedWithError(error: let error):
                PixelKit.fire(DebugEvent(event, error: error), frequency: .legacyDailyAndCount, includeAppVersionParameter: true)
            case .errorLoadingCachedConfig(let error),
                    .failedToParsePrivacyConfig(let error):
                PixelKit.fire(DebugEvent(event, error: error))
            case .ipcServerProfileSavedCalledByApp,
                    .ipcServerProfileSavedReceivedByAgent,
                    .ipcServerImmediateScansInterrupted,
                    .ipcServerImmediateScansFinishedWithoutError,
                    .ipcServerAppLaunchedCalledByApp,
                    .ipcServerAppLaunchedReceivedByAgent,
                    .ipcServerAppLaunchedScheduledScansBlocked,
                    .ipcServerAppLaunchedScheduledScansInterrupted,
                    .ipcServerAppLaunchedScheduledScansFinishedWithoutError:
                PixelKit.fire(event, frequency: .legacyDailyAndCount, includeAppVersionParameter: true)
            case .backgroundAgentStarted,
                    .backgroundAgentStartedStoppingDueToAnotherInstanceRunning,
                    .dataBrokerProtectionNotificationSentFirstScanComplete,
                    .dataBrokerProtectionNotificationOpenedFirstScanComplete,
                    .dataBrokerProtectionNotificationSentFirstRemoval,
                    .dataBrokerProtectionNotificationOpenedFirstRemoval,
                    .dataBrokerProtectionNotificationScheduled2WeeksCheckIn,
                    .dataBrokerProtectionNotificationOpened2WeeksCheckIn,
                    .dataBrokerProtectionNotificationSentAllRecordsRemoved,
                    .dataBrokerProtectionNotificationOpenedAllRecordsRemoved,
                    .webUILoadingFailed,
                    .webUILoadingStarted,
                    .webUILoadingSuccess,
                    .invalidPayload:
                PixelKit.fire(event)

            case .homeViewShowNoPermissionError,
                    .homeViewShowWebUI,
                    .homeViewShowBadPathError,
                    .homeViewCTAMoveApplicationClicked,
                    .homeViewCTAGrantPermissionClicked,
                    .entitlementCheckValid,
                    .entitlementCheckInvalid,
                    .entitlementCheckError:
                PixelKit.fire(event, frequency: .legacyDailyAndCount)

            }
        }
    }

    override init(mapping: @escaping EventMapping<DataBrokerProtectionMacOSPixels>.Mapping) {
        fatalError("Use init()")
    }
}
