//
//  PIRDebugEphemeralSettings.swift
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
import DataBrokerProtectionCore

/// `DataBrokerProtectionSettings` backed by a throwaway `UserDefaults` suite, so debug flows never
/// touch `UserDefaults.standard` / `UserDefaults.dbp`. The suite is removed when this object goes
/// away, so a holder must keep it alive for as long as it uses `settings`.
final class PIRDebugEphemeralSettings {

    let settings: DataBrokerProtectionSettings
    private let suiteName: String

    init(servicesEndpoint: PIRServicesEndpoint) throws {
        let suiteName = "com.duckduckgo.pir-debug.session.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw PIRDebugError.ephemeralDefaultsUnavailable
        }
        self.suiteName = suiteName
        let settings = DataBrokerProtectionSettings(defaults: defaults)
        settings.selectedEnvironment = servicesEndpoint.selectedEnvironment
        self.settings = settings
    }

    deinit {
        UserDefaults.standard.removeSuite(named: suiteName)
    }
}
