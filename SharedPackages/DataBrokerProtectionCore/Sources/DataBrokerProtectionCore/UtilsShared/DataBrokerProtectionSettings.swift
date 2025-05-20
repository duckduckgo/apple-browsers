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

public protocol AppRunTypeProviding: AnyObject {
    var runType: AppVersion.AppRunType { get }
}

public final class DataBrokerProtectionSettings {
    public let defaults: UserDefaults

    public enum Keys {
        public static let runType = "dbp.environment.run-type"
        static let isAuthV2Enabled = "dbp.environment.isAuthV2Enabled"

        static let mainConfigETagKey = "dbp.mainConfigETag"
        static let serviceRootKey = "dbp.serviceRoot"
        static let lastBrokerJSONUpdateCheckTimestampKey = "dbp.lastBrokerJSONUpdateCheckTimestamp"
    }

    public enum SelectedEnvironment: String, Codable {
        case production
        case staging

        public static var `default`: SelectedEnvironment = .production
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
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

    public var isAuthV2Enabled: Bool {
        get {
            defaults.value(forKey: Keys.isAuthV2Enabled) as? Bool ?? false
        }
        set {
            defaults.setValue(newValue, forKey: Keys.isAuthV2Enabled)
        }
    }

    // MARK: - Broker JSONs

    public var mainConfigETag: String? {
        get {
            defaults.string(forKey: Keys.mainConfigETagKey)
        }
        set {
            defaults.set(newValue, forKey: Keys.mainConfigETagKey)
        }
    }

    private(set) var lastBrokerJSONUpdateCheckTimestamp: TimeInterval {
        get {
            defaults.double(forKey: Keys.lastBrokerJSONUpdateCheckTimestampKey)
        }
        set {
            defaults.set(newValue, forKey: Keys.lastBrokerJSONUpdateCheckTimestampKey)
        }
    }

    public func updateLastSuccessfulBrokerJSONUpdateCheckTimestamp(_ timestamp: TimeInterval? = nil) {
        lastBrokerJSONUpdateCheckTimestamp = timestamp ?? Date().timeIntervalSince1970
    }

    // MARK: - Service root

    public var serviceRoot: String {
        get {
            defaults.string(forKey: Keys.serviceRootKey) ?? ""
        }
        set {
            defaults.set(newValue, forKey: Keys.serviceRootKey)
        }
    }

    public var endpointURL: URL {
        switch selectedEnvironment {
        case .production:
            return URL(string: "https://dbp.duckduckgo.com")!
        case .staging:
            return serviceRoot.isEmpty
                ? URL(string: "https://dbp-staging.duckduckgo.com")!
                : URL(string: "https://dbp-staging.duckduckgo.com")!.appending(serviceRoot)
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
}

// This should never ever go to production and only exists for internal testing
#if os(iOS) && (DEBUG || ALPHA)
extension DataBrokerProtectionSettings {
    static let deviceIdentifierKey = "dbp.deviceIdentifier"
    static let defaults = UserDefaults.standard

    public static var deviceIdentifier: String {
        get {
            let id = defaults.string(forKey: deviceIdentifierKey)
            if let id = id {
                return id
            } else {
                let newID = UUID().uuidString
                self.deviceIdentifier = newID
                return newID
            }
        }
        set {
            defaults.set(newValue, forKey: deviceIdentifierKey)
        }
    }

    public static var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
#endif
