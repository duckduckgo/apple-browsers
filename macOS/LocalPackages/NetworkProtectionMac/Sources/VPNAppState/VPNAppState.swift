//
//  VPNAppState.swift
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

import Combine
import Foundation

/// Container for VPN App State data.
///
/// This is meant to contain state data that's shared between the VPN apps.  If you need
/// to store VPN settings - especially if they're meant to be propagated to the extensions,
/// please refer to ``VPNSettings`` instead.
///
public final class VPNAppState {

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Resetting to Defaults

    public func resetToDefaults() {
        defaults.resetVPNIsUsingSystemExtension()
        defaults.resetIsVPNMigratedToAuthV2()
        defaults.resetVPNDontAskAgainExclusionSuggestion()
    }

    // MARK: - System Extension support

    public var isUsingSystemExtensionPublisher: AnyPublisher<Bool, Never> {
        defaults.vpnIsUsingSystemExtensionPublisher
    }

    public var isUsingSystemExtension: Bool {
        get {
            defaults.vpnIsUsingSystemExtension
        }

        set {
            defaults.vpnIsUsingSystemExtension = newValue
        }
    }

    // MARK: - AuthV2 migration support

    public var isMigratedToAuthV2: Bool {
        get {
            defaults.isVPNMigratedToAuthV2
        }

        set {
            defaults.isVPNMigratedToAuthV2 = newValue
        }
    }

    public func resetIsMigratedToAuthV2() {
        defaults.resetIsVPNMigratedToAuthV2()
    }

    // MARK: - isAuthV2Enabled

    public var isAuthV2Enabled: Bool {
        get {
            defaults.isAuthV2Enabled
        }

        set {
            defaults.isAuthV2Enabled = newValue
        }
    }

    public func resetIsAuthV2Enabled() {
        defaults.resetIsAuthV2Enabled()
    }

    // MARK: - VPN Exclusion Suggestion when turning it OFF

    public var dontAskAgainExclusionSuggestion: Bool {
        get {
            defaults.vpnDontAskAgainExclusionSuggestion
        }

        set {
            defaults.vpnDontAskAgainExclusionSuggestion = newValue
        }
    }

    public func resetDontAskAgainExclusionSuggestion() {
        defaults.resetVPNDontAskAgainExclusionSuggestion()
    }
}
