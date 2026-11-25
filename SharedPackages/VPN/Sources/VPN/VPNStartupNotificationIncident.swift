//
//  VPNStartupNotificationIncident.swift
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

#if os(macOS)
import Foundation
import NetworkExtension

/// Read through the owning tunnel session; never through another user's defaults domain.
public struct VPNStartupNotificationIncident: Codable, RawRepresentable, Equatable {
    public static let profileIdentifierKey = "com.duckduckgo.vpn.notificationProfileIdentifier"
    public let identifier: UUID
    public let profileIdentifier: String
    private let legacyProviderIdentifier: String?

    init(identifier: UUID = UUID(), profileIdentifier: String, legacyProviderIdentifier: String? = nil) {
        self.identifier = identifier
        self.profileIdentifier = profileIdentifier
        self.legacyProviderIdentifier = legacyProviderIdentifier
    }

    public init?(rawValue: Data) {
        guard let value = try? JSONDecoder().decode(Self.self, from: rawValue) else { return nil }
        self = value
    }

    public var rawValue: Data {
        // This model contains only strings and a UUID.
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    private static let disconnectErrorKey = "com.duckduckgo.vpn.startupNotification"

    func attached(to error: Error) -> NSError {
        let original = error.sanitizedForXPC() as NSError
        var info = original.userInfo
        info[Self.disconnectErrorKey] = rawValue
        return NSError(domain: original.domain, code: original.code, userInfo: info)
    }

    static func fromDisconnectError(_ error: Error, provider: String) -> Self? {
        let error = error as NSError
        let reason = XPCErrorSanitizer.originalDomainAndCode(of: error)
        guard reason.domain == PacketTunnelProvider.TunnelError.errorDomain,
              let code = PacketTunnelProvider.TunnelError.Code(rawValue: reason.code),
              code == .startingTunnelWithoutAuthToken || code == .reconnectBlocked,
              let data = error.userInfo[disconnectErrorKey] as? Data,
              let incident = Self(rawValue: data), incident.profileIdentifier == provider else { return nil }
        return incident
    }

    /// Record acceptance in the menu user's defaults so a denied or failed submission can be retried.
    @MainActor
    public func presentIfNeeded(in defaults: UserDefaults, submit: (UUID) async throws -> Bool) async rethrows {
        // Old profiles use the provider bundle ID until the next setup. Treat their automatic
        // retries, including the save that migrates the profile, as one delivery.
        let key = "com.duckduckgo.vpn.presentedStartupNotification." + (legacyProviderIdentifier ?? profileIdentifier)
        let receipt = legacyProviderIdentifier ?? identifier.uuidString
        guard defaults.string(forKey: key) != receipt else { return }
        if try await submit(identifier) { defaults.set(receipt, forKey: key) }
    }
}

public extension NETunnelProviderSession {
    func pendingStartupNotification() async throws -> VPNStartupNotificationIncident? {
        guard let configuration = manager.protocolConfiguration as? NETunnelProviderProtocol,
              let provider = configuration.providerBundleIdentifier else { return nil }
        guard let profileIdentifier = configuration.providerConfiguration?[VPNStartupNotificationIncident.profileIdentifierKey] as? String else {
            guard #available(macOS 13, *), status != .connected, status != .reasserting else { return nil }
            do {
                try await fetchLastDisconnectError()
                return nil
            } catch {
                return VPNStartupNotificationIncident.fromDisconnectError(error, provider: provider)
            }
        }
        let incident: VPNStartupNotificationIncident? = try await sendProviderMessage(.request(.pendingStartupNotification), timeout: 5)
        return incident?.profileIdentifier == profileIdentifier ? incident : nil
    }
}

extension NETunnelProviderProtocol {
    /// Older profiles have no UUID. Only migrate one when the configuration the OS supplied is unambiguous.
    func notificationProfile(in managers: [NETunnelProviderManager], identifier: String?) -> NETunnelProviderManager? {
        guard let providerBundleIdentifier else { return nil }
        let matching = managers.filter { manager in
            guard let candidate = manager.protocolConfiguration as? NETunnelProviderProtocol,
                  candidate.providerBundleIdentifier == providerBundleIdentifier else { return false }
            if let identifier {
                return candidate.providerConfiguration?[VPNStartupNotificationIncident.profileIdentifierKey] as? String == identifier
            }
            return candidate.serverAddress == serverAddress &&
                NSDictionary(dictionary: candidate.providerConfiguration ?? [:]).isEqual(to: providerConfiguration ?? [:])
        }
        return matching.count == 1 ? matching[0] : nil
    }
}

struct VPNStartupNotificationStore {
    private static let keyPrefix = "com.duckduckgo.vpn.pendingStartupNotification."
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func pending(profileIdentifier: String) -> VPNStartupNotificationIncident? {
        guard !defaults.suppressEntitlementMessaging else { return nil }
        return defaults.data(forKey: key(profileIdentifier)).flatMap(VPNStartupNotificationIncident.init(rawValue:))
    }

    /// Keeps one incident per profile until a successful connection resets that failed episode.
    func recordIfNeeded(profileIdentifier: String, legacyProviderIdentifier: String? = nil) {
        guard !defaults.suppressEntitlementMessaging, pending(profileIdentifier: profileIdentifier) == nil else { return }
        let incident = VPNStartupNotificationIncident(profileIdentifier: profileIdentifier, legacyProviderIdentifier: legacyProviderIdentifier)
        defaults.set(incident.rawValue, forKey: key(profileIdentifier))
    }

    func reset(profileIdentifier: String) {
        defaults.removeObject(forKey: key(profileIdentifier))
    }

    func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(_ profileIdentifier: String) -> String {
        Self.keyPrefix + profileIdentifier
    }
}
#endif
