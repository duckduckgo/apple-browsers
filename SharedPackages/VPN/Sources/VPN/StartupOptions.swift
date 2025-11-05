//
//  StartupOptions.swift
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
import Networking
import os.log

/// Codable representation of VPN settings that can be passed to the packet tunnel
///
public struct VPNSettingsSnapshot: Codable, Equatable {
    let registrationKeyValidity: VPNSettings.RegistrationKeyValidity
    let selectedEnvironment: VPNSettings.SelectedEnvironment
    let selectedServer: VPNSettings.SelectedServer
    let selectedLocation: VPNSettings.SelectedLocation
    let dnsSettings: NetworkProtectionDNSSettings
    let excludeLocalNetworks: Bool

    /// Create a snapshot of the current VPN settings
    public init(from settings: VPNSettings) {
        self.registrationKeyValidity = settings.registrationKeyValidity
        self.selectedEnvironment = settings.selectedEnvironment
        self.selectedServer = settings.selectedServer
        self.selectedLocation = settings.selectedLocation
        self.dnsSettings = settings.dnsSettings
        self.excludeLocalNetworks = settings.excludeLocalNetworks
    }

    /// Create a snapshot with explicit values
    public init(registrationKeyValidity: VPNSettings.RegistrationKeyValidity,
                selectedEnvironment: VPNSettings.SelectedEnvironment,
                selectedServer: VPNSettings.SelectedServer,
                selectedLocation: VPNSettings.SelectedLocation,
                dnsSettings: NetworkProtectionDNSSettings,
                excludeLocalNetworks: Bool) {
        self.registrationKeyValidity = registrationKeyValidity
        self.selectedEnvironment = selectedEnvironment
        self.selectedServer = selectedServer
        self.selectedLocation = selectedLocation
        self.dnsSettings = dnsSettings
        self.excludeLocalNetworks = excludeLocalNetworks
    }

    /// Apply these settings to a VPNSettings instance
    public func applyTo(_ settings: VPNSettings) {
        settings.registrationKeyValidity = registrationKeyValidity
        settings.selectedEnvironment = selectedEnvironment
        settings.selectedServer = selectedServer
        settings.selectedLocation = selectedLocation
        settings.dnsSettings = dnsSettings
        settings.excludeLocalNetworks = excludeLocalNetworks
    }
}

/// This class handles the proper parsing of the startup options for our tunnel.
///
public struct StartupOptions {

    enum StartupMethod: CustomDebugStringConvertible {
        /// Case started up manually from the main app.
        ///
        case manualByMainApp

        /// Started up manually from a system-provided source: it can be the VPN menu, a CLI command
        /// or the list of VPNs in System Settings.
        ///
        case manualByTheSystem

        /// Started up automatically by on-demand.
        ///
        case automaticOnDemand

        var debugDescription: String {
            switch self {
            case .automaticOnDemand:
                return "automatically by On-Demand"
            case .manualByMainApp:
                return "manually by the main app"
            case .manualByTheSystem:
                return "manually by the system"
            }
        }
    }

    /// Stored options are the options that the our network extension stores / remembers.
    ///
    /// Since these options are stored, the logic can allow for
    ///
    public enum StoredOption<T: Equatable>: Equatable {
        case set(_ value: T)
        case reset
        case useExisting

        init(resetIfNil: Bool, getValue: () -> T?) {
            guard let value = getValue() else {
                if resetIfNil {
                    self = .reset
                } else {
                    self = .useExisting
                }

                return
            }

            self = .set(value)
        }

        var description: String {
            switch self {
            case .set(let value):
                return String(describing: value)
            case .reset:
                return "reset"
            case .useExisting:
                return "useExisting"
            }
        }

        // MARK: - Equatable

        public static func == (lhs: StartupOptions.StoredOption<T>, rhs: StartupOptions.StoredOption<T>) -> Bool {
            switch (lhs, rhs) {
            case (.reset, .reset):
                return true
            case (.set(let lValue), .set(let rValue)):
                return lValue == rValue
            case (.useExisting, .useExisting):
                return true
            default:
                return false
            }
        }
    }

    let startupMethod: StartupMethod
    let simulateError: Bool
    let simulateCrash: Bool
    let simulateMemoryCrash: Bool
    public let vpnSettings: StoredOption<VPNSettingsSnapshot>
#if os(macOS)
    public let isAuthV2Enabled: StoredOption<Bool>
    public let authToken: StoredOption<String>
    public let tokenContainer: StoredOption<TokenContainer>
#endif
    let enableTester: StoredOption<Bool>

    init(options: [String: Any]) {
        let startupMethod: StartupMethod = {
            if options[NetworkProtectionOptionKey.isOnDemand] as? Bool == true {
                return .automaticOnDemand
            } else if options[NetworkProtectionOptionKey.activationAttemptId] != nil {
                return .manualByMainApp
            } else {
                return .manualByTheSystem
            }
        }()

        self.startupMethod = startupMethod

        simulateError = options[NetworkProtectionOptionKey.tunnelFailureSimulation] as? Bool ?? false
        simulateCrash = options[NetworkProtectionOptionKey.tunnelFatalErrorCrashSimulation] as? Bool ?? false
        simulateMemoryCrash = options[NetworkProtectionOptionKey.tunnelMemoryCrashSimulation] as? Bool ?? false

        let resetStoredOptionsIfNil = startupMethod == .manualByMainApp
#if os(macOS)
        isAuthV2Enabled = Self.readIsAuthV2Enabled(from: options, resetIfNil: resetStoredOptionsIfNil)
        authToken = Self.readAuthToken(from: options, resetIfNil: resetStoredOptionsIfNil)
        tokenContainer = Self.readTokenContainer(from: options, resetIfNil: resetStoredOptionsIfNil)
#endif
        enableTester = Self.readEnableTester(from: options, resetIfNil: resetStoredOptionsIfNil)
        vpnSettings = Self.readVPNSettings(from: options, resetIfNil: resetStoredOptionsIfNil)
    }

    var description: String {
        var result = """
        StartupOptions:
            startupMethod: \(self.startupMethod.debugDescription),
            simulateError: \(self.simulateError.description),
            simulateCrash: \(self.simulateCrash.description),
            simulateMemoryCrash: \(self.simulateMemoryCrash.description),
            vpnSettings: \(self.vpnSettings.description),
            enableTester: \(self.enableTester),
        """
#if os(macOS)
        result += """
            isAuthV2Enabled: \(self.isAuthV2Enabled),
            authToken: \(self.authToken),
            tokenContainer: \(self.tokenContainer),
        """
#endif
        return result
    }

    // MARK: - Helpers for reading stored options

#if os(macOS)
    private static func readIsAuthV2Enabled(from options: [String: Any], resetIfNil: Bool) -> StoredOption<Bool> {
        StoredOption(resetIfNil: resetIfNil) {
            guard let isAuthV2Enabled = options[NetworkProtectionOptionKey.isAuthV2Enabled] as? Bool else {
                Logger.networkProtection.fault("`isAuthV2Enabled` is missing or invalid")
                return nil
            }

            return isAuthV2Enabled
        }
    }

    private static func readAuthToken(from options: [String: Any], resetIfNil: Bool) -> StoredOption<String> {
        StoredOption(resetIfNil: resetIfNil) {
            guard let authToken = options[NetworkProtectionOptionKey.authToken] as? String,
                  !authToken.isEmpty else {
                Logger.networkProtection.warning("`authToken` is missing or invalid")
                return nil
            }

            return authToken
        }
    }

    private static func readTokenContainer(from options: [String: Any], resetIfNil: Bool) -> StoredOption<TokenContainer> {
        StoredOption(resetIfNil: resetIfNil) {
            guard let data = options[NetworkProtectionOptionKey.tokenContainer] as? NSData,
                  let tokenContainer = try? TokenContainer(with: data) else {
                Logger.networkProtection.warning("`tokenContainer` is missing or invalid")
                return nil
            }
            return tokenContainer
        }
    }
#endif

    private static func readVPNSettings(from options: [String: Any], resetIfNil: Bool) -> StoredOption<VPNSettingsSnapshot> {
        StoredOption(resetIfNil: resetIfNil) {
            guard let data = options[NetworkProtectionOptionKey.settings] as? Data,
                  let vpnSettings = try? JSONDecoder().decode(VPNSettingsSnapshot.self, from: data) else {
                return nil
            }

            return vpnSettings
        }
    }

    private static func readEnableTester(from options: [String: Any], resetIfNil: Bool) -> StoredOption<Bool> {
        StoredOption(resetIfNil: resetIfNil) {
            guard let value = options[NetworkProtectionOptionKey.connectionTesterEnabled] as? Bool else {
                return nil
            }

            return value
        }
    }

}
