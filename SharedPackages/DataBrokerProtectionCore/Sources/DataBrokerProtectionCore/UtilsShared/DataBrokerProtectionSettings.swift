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
import DDGError

public protocol AppRunTypeProviding: AnyObject {
    var runType: AppVersion.AppRunType { get }
}

public final class DataBrokerProtectionSettings {
    public let defaults: UserDefaults
    #if DEBUG
    private var debugEnvironment: SelectedEnvironment?

    public convenience init(defaults: UserDefaults, debugEnvironment: SelectedEnvironment) {
        self.init(defaults: defaults)
        self.debugEnvironment = debugEnvironment
    }

    public func isolatedDebugSettingsForLaunch(arguments: [String] = ProcessInfo.processInfo.arguments,
                                               environment: [String: String] = ProcessInfo.processInfo.environment) -> DataBrokerProtectionSettings {
        guard let configuration = try? DebugModeLaunchConfiguration.parse(arguments: arguments, environment: environment) else { return self }
        return DataBrokerProtectionSettings(defaults: defaults, debugEnvironment: configuration.environment)
    }
    #endif

    public enum Keys {
        public static let runType = "dbp.environment.run-type"
        static let mainConfigETagKey = "dbp.mainConfigETag"
        static let serviceRootKey = "dbp.serviceRoot"
        static let lastBrokerJSONUpdateCheckTimestampKey = "dbp.lastBrokerJSONUpdateCheckTimestamp"
        static let lastManifestVersionsKey = "dbp.lastManifestVersions"
        static let bundleSigningKeyFingerprintKey = "dbp.bundleSigningKeyFingerprint"
        static let preferredRunDateMigrationKey = "dbp.preferredRunDateMigration"
    }

    public enum SelectedEnvironment: String, Codable {
        case production
        case staging

        public static var `default`: SelectedEnvironment = .production
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var debugTestBrokerURLs: [String]? {
#if DEBUG
        defaults.stringArray(forKey: "dbp.debug.testBrokerURLs")
#else
        nil
#endif
    }

    func allowsBrokerForDebugTesting(_ brokerURL: String) -> Bool {
        debugTestBrokerURLs?.contains(brokerURL) ?? true
    }

    // MARK: - Environment

    public var selectedEnvironment: SelectedEnvironment {
        get {
            #if DEBUG
            if let debugEnvironment { return debugEnvironment }
            #endif
            return defaults.dataBrokerProtectionSelectedEnvironment
        }

        set {
            defaults.dataBrokerProtectionSelectedEnvironment = newValue
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

    public private(set) var lastBrokerJSONUpdateCheckTimestamp: TimeInterval {
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

    /// The last `manifest_version` accepted for each signing key, keyed by key ID.
    /// It's per key because a compromised key could sign a huge `manifest_version`, and a single value would then reject
    /// every manifest from the replacement key.
    public var lastManifestVersions: [String: Int] {
        get {
            defaults.dictionary(forKey: Keys.lastManifestVersionsKey) as? [String: Int] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: Keys.lastManifestVersionsKey)
        }
    }

    public var bundleSigningKeyFingerprint: String? {
        get {
            defaults.string(forKey: Keys.bundleSigningKeyFingerprintKey)
        }
        set {
            defaults.set(newValue, forKey: Keys.bundleSigningKeyFingerprintKey)
        }
    }

    public func resetBrokerDeliveryData() {
        mainConfigETag = nil
        updateLastSuccessfulBrokerJSONUpdateCheckTimestamp(Date.distantPast.timeIntervalSince1970)
    }

    // MARK: - Preferred run date migration

    public var hasPerformedPreferredRunDateMigration: Bool {
        get {
            defaults.bool(forKey: Keys.preferredRunDateMigrationKey)
        }
        set {
            defaults.set(newValue, forKey: Keys.preferredRunDateMigrationKey)
        }
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

    private static let productionEndpointURL = URL(string: "https://dbp.duckduckgo.com")!

    public var isProductionEndpoint: Bool {
        endpointURL == Self.productionEndpointURL
    }

    public var endpointURL: URL {
#if DEBUG
        let hasAbsoluteServiceRoot = serviceRoot.hasPrefix("http://") || serviceRoot.hasPrefix("https://")
        if debugEnvironment == nil, hasAbsoluteServiceRoot,
           let override = URL(string: serviceRoot) {
            return override
        }
#endif

        switch selectedEnvironment {
        case .production:
            return Self.productionEndpointURL
        case .staging:
            #if DEBUG
            if debugEnvironment != nil { return URL(string: "https://dbp-staging.duckduckgo.com")! }
            #endif
            return serviceRoot.isEmpty
                ? URL(string: "https://dbp-staging.duckduckgo.com")!
                : URL(string: "https://dbp-staging.duckduckgo.com")!.appending(serviceRoot)
        }
    }
}

#if DEBUG
/// Nonsecret launch settings can cross LaunchServices through arguments when environment inheritance is unavailable.
public struct DebugModeLaunchConfiguration {
    public enum ConfigurationError: String, DDGError {
        case invalidInstanceID, invalidPort, invalidEnvironment, serverNotRequested

        public static var errorDomain: String { "com.duckduckgo.pir.debug-launch-configuration" }

        public var errorCode: Int {
            switch self {
            case .invalidInstanceID: return 0
            case .invalidPort: return 1
            case .invalidEnvironment: return 2
            case .serverNotRequested: return 3
            }
        }

        public var description: String {
            switch self {
            case .invalidInstanceID: return "PIR debug launch requires a UUID instance ID."
            case .invalidPort: return "PIR debug launch requires a valid port."
            case .invalidEnvironment: return "PIR debug launch requires production or staging."
            case .serverNotRequested: return "PIR debug launch did not request the debug server."
            }
        }
    }

    public let instanceID: String
    public let port: UInt16
    public let environment: DataBrokerProtectionSettings.SelectedEnvironment

    /// Selection happens before parsing so malformed standalone launches cannot start the normal agent.
    public static func isRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                                   environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let argumentMarkers = ["-pirDebugServer", "-pirDebugPort", "-pirDebugInstanceID", "-pirDebugEnvironment"]
        let environmentMarkers = ["PIR_DEBUG_SERVER", "PIR_DEBUG_PORT", "PIR_DEBUG_INSTANCE_ID", "PIR_DEBUG_ENVIRONMENT"]
        return argumentMarkers.contains(where: arguments.contains) || environmentMarkers.contains { environment[$0] != nil }
    }

    public static func parse(arguments: [String] = ProcessInfo.processInfo.arguments,
                             environment: [String: String] = ProcessInfo.processInfo.environment) throws -> DebugModeLaunchConfiguration? {
        guard isRequested(arguments: arguments, environment: environment) else { return nil }
        func value(argument: String, environmentKey: String) -> String? {
            guard let index = arguments.lastIndex(of: "-\(argument)") else { return environment[environmentKey] }
            let nextIndex = arguments.index(after: index)
            return nextIndex < arguments.endIndex ? arguments[nextIndex] : nil
        }
        guard let instance = value(argument: "pirDebugInstanceID", environmentKey: "PIR_DEBUG_INSTANCE_ID"),
              UUID(uuidString: instance) != nil else { throw ConfigurationError.invalidInstanceID }
        guard let rawPort = value(argument: "pirDebugPort", environmentKey: "PIR_DEBUG_PORT"),
              let port = UInt16(rawPort), port > 0 else { throw ConfigurationError.invalidPort }
        guard let rawEnvironment = value(argument: "pirDebugEnvironment", environmentKey: "PIR_DEBUG_ENVIRONMENT"),
              let selected = DataBrokerProtectionSettings.SelectedEnvironment(rawValue: rawEnvironment) else {
            throw ConfigurationError.invalidEnvironment
        }
        guard value(argument: "pirDebugServer", environmentKey: "PIR_DEBUG_SERVER") == "true" else {
            throw ConfigurationError.serverNotRequested
        }
        return DebugModeLaunchConfiguration(instanceID: instance, port: port, environment: selected)
    }
}
#endif

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
