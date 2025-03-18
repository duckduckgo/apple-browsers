//
//  VPNBypassFeatureProvider.swift
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

import Foundation
import NetworkProtectionProxy
import Combine
import DataBrokerProtectionShared

public final class VPNBypassFeatureProvider: VPNBypassFeatureProviding {
    private let backgroundAgentBundleId: String
    private let proxySettings: TransparentProxySettingsProviding

    public init(backgroundAgentBundleId: String, proxySettings: TransparentProxySettingsProviding) {
        self.backgroundAgentBundleId = backgroundAgentBundleId
        self.proxySettings = proxySettings
    }

    // This requires VPN system extension, so App Store version is not currently supported
    public var vpnBypassSupport: Bool {
#if APPSTORE
#if NETP_SYSTEM_EXTENSION
        return true
#else
        return false
#endif
#else
        return true
#endif
    }

    public var vpnBypassEnabled: Bool {
        proxySettings.isExcluding(appIdentifier: backgroundAgentBundleId)
    }

    public var vpnBypassOnboardingShown: Bool {
        get {
            DataBrokerProtectionSettings(defaults: .dbp).vpnBypassOnboardingShown
        }

        set {
            DataBrokerProtectionSettings(defaults: .dbp).vpnBypassOnboardingShown = newValue
        }
    }

    public var vpnBypassStatus: VPNBypassStatus {
        guard vpnBypassSupport else { return .unsupported }
        return proxySettings.isExcluding(appIdentifier: backgroundAgentBundleId) ? .on : .off
    }

    public func applyVPNBypass(_ bypass: Bool) {
        proxySettings[bundleId: backgroundAgentBundleId] = bypass ? .exclude : nil
    }
}

extension UserDefaults {
    static let bypassOnboardingShownDefaultValue = false
    private var bypassOnboardingShownKey: String {
        "hasShownBypassOnboarding"
    }

    @objc
    dynamic var dataBrokerProtectionVPNBypassOnboardingShown: Bool {
        get {
            value(forKey: bypassOnboardingShownKey) as? Bool ?? Self.bypassOnboardingShownDefaultValue
        }

        set {
            guard newValue != dataBrokerProtectionVPNBypassOnboardingShown else {
                return
            }

            set(newValue, forKey: bypassOnboardingShownKey)
        }
    }

    var dataBrokerProtectionVPNBypassOnboardingShownPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.dataBrokerProtectionVPNBypassOnboardingShown).eraseToAnyPublisher()
    }
}

extension DataBrokerProtectionSettings {
    public var vpnBypassOnboardingShownPublisher: AnyPublisher<Bool, Never> {
        defaults.dataBrokerProtectionVPNBypassOnboardingShownPublisher
    }

    public var vpnBypassOnboardingShown: Bool {
        get {
            defaults.dataBrokerProtectionVPNBypassOnboardingShown
        }

        set {
            defaults.dataBrokerProtectionVPNBypassOnboardingShown = newValue
        }
    }
}
