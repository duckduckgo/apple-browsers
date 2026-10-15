//
//  CPMDeviceState.swift
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
import WebKit

/// Conditions of the device that slow a background start down or stop it altogether. Coarse, fixed-vocabulary
/// values only; nothing identifies the device.
public struct CPMDeviceState: Equatable, Sendable {

    public enum ThermalState: String, Sendable {
        case nominal
        case fair
        case serious
        case critical
    }

    /// Low Power Mode (iOS) or Low Power mode (macOS) throttles background work.
    public var isLowPowerMode: Bool
    public var thermalState: ThermalState
    /// WebKit disables service workers in Lockdown Mode, so the CPM background cannot run at all.
    public var isLockdownMode: Bool

    public init(isLowPowerMode: Bool, thermalState: ThermalState, isLockdownMode: Bool) {
        self.isLowPowerMode = isLowPowerMode
        self.thermalState = thermalState
        self.isLockdownMode = isLockdownMode
    }

    var pixelParameters: [String: String] {
        [
            CPMMessagingDiagnostics.ParameterName.lowPowerMode: String(isLowPowerMode),
            CPMMessagingDiagnostics.ParameterName.thermalState: thermalState.rawValue,
            CPMMessagingDiagnostics.ParameterName.lockdownMode: String(isLockdownMode)
        ]
    }

    /// Reads the live values. Lockdown Mode is a system setting that only changes across a restart, so callers may
    /// keep the value they read first.
    @MainActor
    public static func current(processInfo: ProcessInfo = .processInfo) -> CPMDeviceState {
        let thermal: ThermalState
        switch processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .nominal
        }
        return CPMDeviceState(isLowPowerMode: processInfo.isLowPowerModeEnabled,
                              thermalState: thermal,
                              isLockdownMode: isLockdownModeEnabled())
    }

    /// The system setting is the default of a new set of page preferences. The package supports older systems than
    /// Lockdown Mode exposes this on, which cannot have the extension anyway.
    @MainActor
    private static func isLockdownModeEnabled() -> Bool {
        guard #available(macOS 13.0, iOS 16.0, *) else { return false }
        return WKWebpagePreferences().isLockdownModeEnabled
    }
}
