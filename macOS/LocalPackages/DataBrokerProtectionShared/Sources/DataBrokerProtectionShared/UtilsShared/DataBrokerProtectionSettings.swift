//
//  DataBrokerProtectionSettings.swift
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
import Combine
import Common
import BrowserServicesKit
import AppKitExtensions
import NetworkProtectionProxy

public protocol VPNBypassSettingsProviding: AnyObject {
    var vpnBypassSupport: Bool { get }
    var vpnBypass: Bool { get set }
    var vpnBypassOnboardingShown: Bool { get set }
}

public protocol AppRunTypeProviding: AnyObject {
    var runType: AppVersion.AppRunType { get }
}

public final class DataBrokerProtectionSettings: VPNBypassSettingsProviding {
    public let defaults: UserDefaults
    public let proxySettings: TransparentProxySettings

    public enum Keys {
        public static let runType = "dbp.environment.run-type"
    }

    public enum SelectedEnvironment: String, Codable {
        case production
        case staging

        public static var `default`: SelectedEnvironment = .production

        public var endpointURL: URL {
            switch self {
            case .production:
                return URL(string: "https://dbp.duckduckgo.com")!
            case .staging:
                return URL(string: "https://dbp-staging.duckduckgo.com")!
            }
        }
    }

    public init(defaults: UserDefaults, proxySettings: TransparentProxySettings) {
        self.defaults = defaults
        self.proxySettings = proxySettings
    }

    // MARK: - Environment

    public var selectedEnvironment: SelectedEnvironment {
        get {
            defaults.dataBrokerProtectionSelectedEnvironment
        }

        set {
            defaults.dataBrokerProtectionSelectedEnvironment = newValue
        }
    }

    // MARK: - VPN exclusion

    public var vpnBypass: Bool {
        get {
            proxySettings[bundleId: "DBP_BACKGROUND_AGENT_BUNDLE_ID"] == .exclude
        }
        set {
            proxySettings[bundleId: "DBP_BACKGROUND_AGENT_BUNDLE_ID"] = newValue ? .exclude : nil
        }
    }

    /// This requires VPN system extension, so App Store version is not currently supported
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

    public var vpnBypassStatus: VPNBypassStatus {
        guard vpnBypassSupport else { return .unsupported }
        return vpnBypass ? .on : .off
    }

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

extension UserDefaults {
    private var selectedEnvironmentKey: String {
        "dataBrokerProtectionSelectedEnvironmentRawValue"
    }

    static let showMenuBarIconDefaultValue = false
    private var showMenuBarIconKey: String {
        "dataBrokerProtectionShowMenuBarIcon"
    }

    static let bypassOnboardingShownDefaultValue = false
    private var bypassOnboardingShownKey: String {
        "hasShownBypassOnboarding"
    }

    // MARK: - Environment

    @objc
    dynamic var dataBrokerProtectionSelectedEnvironmentRawValue: String {
        get {
            value(forKey: selectedEnvironmentKey) as? String ?? DataBrokerProtectionSettings.SelectedEnvironment.default.rawValue
        }

        set {
            set(newValue, forKey: selectedEnvironmentKey)
        }
    }

    var dataBrokerProtectionSelectedEnvironment: DataBrokerProtectionSettings.SelectedEnvironment {
        get {
            DataBrokerProtectionSettings.SelectedEnvironment(rawValue: dataBrokerProtectionSelectedEnvironmentRawValue) ?? .default
        }

        set {
            dataBrokerProtectionSelectedEnvironmentRawValue = newValue.rawValue
        }
    }

    // MARK: - VPN exclusion

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
