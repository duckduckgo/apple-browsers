//
//  PowerSourceProvider.swift
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
import IOKit.ps

/// Reports whether the Mac is running on battery.
struct PowerSourceProvider {

    /// Returns `nil` when macOS describes no power source, which includes desktop Macs without a battery.
    func isOnBattery() -> Bool? {
        let powerSource = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let powerSourcesList = IOPSCopyPowerSourcesList(powerSource)?.takeRetainedValue() as? [CFTypeRef]

        guard let sources = powerSourcesList, !sources.isEmpty else {
            return nil
        }

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(powerSource, source)?.takeUnretainedValue() as? [String: Any],
               let powerSourceState = description[kIOPSPowerSourceStateKey] as? String {
                return powerSourceState == kIOPSBatteryPowerValue
            }
        }

        return nil
    }
}
