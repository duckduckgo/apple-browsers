//
//  SyncDiagnosisHelper.swift
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

import DDGSync
import Foundation
import Macros
import Persistence
import PixelKit

extension UserDefaults: SyncDiagnosisHelper.Settings {}

struct SyncDiagnosisHelper {

    @Storage
    protocol Settings: AnyObject, KeyValueStoring {
        @Key("com.duckduckgo.app.key.debug.SyncManuallyDisabled")
        var syncManuallyDisabled: Bool? { get set }
        @Key("com.duckduckgo.app.key.debug.SyncWasDisabledUnexpectedlyPixelFired")
        var syncWasDisabledUnexpectedlyPixelFired: Bool? { get set }
    }

    private enum Const {
        static let authStatePixelParamKey = "authState"
    }

    private let userDefaults = UserDefaults.standard
    private let syncService: DDGSyncing

    private let settings: SyncDiagnosisHelper.Settings

    init(syncService: DDGSyncing, settings: SyncDiagnosisHelper.Settings = UserDefaults.standard) {
        self.syncService = syncService
        self.settings = settings
    }

// Non-user-initiated deactivation
// For events to help understand the impact of https://app.asana.com/0/1201493110486074/1208538487332133/f

    func didManuallyDisableSync() {
        settings.syncManuallyDisabled = true
    }

    func diagnoseAccountStatus() {
        if syncService.account == nil {
            // Nil value means sync was never on in the first place. So don't fire in this case.
            if settings.syncManuallyDisabled == false,
               !(settings.syncWasDisabledUnexpectedlyPixelFired ?? false) {
                PixelKit.fire(
                    DebugEvent(GeneralPixel.syncDebugWasDisabledUnexpectedly),
                    frequency: .dailyAndCount,
                    withAdditionalParameters: [Const.authStatePixelParamKey: syncService.authState.rawValue]
                )
                settings.syncWasDisabledUnexpectedlyPixelFired = true
            }
        } else {
            settings.syncManuallyDisabled = false
            settings.syncWasDisabledUnexpectedlyPixelFired = false
        }
    }

}
