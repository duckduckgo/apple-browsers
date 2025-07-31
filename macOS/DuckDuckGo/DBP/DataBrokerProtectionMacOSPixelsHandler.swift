//
//  DataBrokerProtectionMacOSPixelsHandler.swift
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
import DataBrokerProtection_macOS
import PixelKit
import Common

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
            case .errorLoadingCachedConfig(let error),
                    .failedToParsePrivacyConfig(let error):
                PixelKit.fire(DebugEvent(event, error: error))
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
