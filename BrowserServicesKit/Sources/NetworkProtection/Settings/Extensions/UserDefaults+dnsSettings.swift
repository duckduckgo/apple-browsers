//
//  UserDefaults+dnsSettings.swift
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

import Combine
import Foundation

extension UserDefaults {
    final class StorableDNSSettings: NSObject, Codable {
        let usesCustomDNS: Bool
        let dnsServers: [String]
        let isBlockRiskyDomainsOn: Bool

        init(usesCustomDNS: Bool = false, dnsServers: [String] = [], isBlockRiskyDomainsOn: Bool = false) {
            self.usesCustomDNS = usesCustomDNS
            self.dnsServers = dnsServers
            self.isBlockRiskyDomainsOn = isBlockRiskyDomainsOn
        }

        private enum CodingKeys: String, CodingKey {
            case usesCustomDNS, dnsServers, isBlockRiskyDomainsOn
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.usesCustomDNS = try container.decodeIfPresent(Bool.self, forKey: .usesCustomDNS) ?? false
            self.dnsServers = try container.decodeIfPresent([String].self, forKey: .dnsServers) ?? []
            self.isBlockRiskyDomainsOn = try container.decodeIfPresent(Bool.self, forKey: .isBlockRiskyDomainsOn) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(usesCustomDNS, forKey: .usesCustomDNS)
            try container.encode(dnsServers, forKey: .dnsServers)
            try container.encode(isBlockRiskyDomainsOn, forKey: .isBlockRiskyDomainsOn)
        }
    }

    private var dnsSettingKey: String {
        "dnsSettingStorageValue"
    }

    private static func dnsSettingsFromStorageValue(_ value: StorableDNSSettings) -> NetworkProtectionDNSSettings {
        guard value.usesCustomDNS, !value.dnsServers.isEmpty else { return .ddg(blockRiskyDomains: value.isBlockRiskyDomainsOn) }
        return .custom(value.dnsServers)
    }

    @objc
    dynamic var dnsSettingStorageValue: StorableDNSSettings {
        get {
            guard let data = data(forKey: dnsSettingKey) else { return StorableDNSSettings() }
            return (try? JSONDecoder().decode(StorableDNSSettings.self, from: data)) ?? StorableDNSSettings()
        }

        set {
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, forKey: dnsSettingKey)
            }
        }
    }

    var didBlockRiskyDomainsDefaultToTrue: Bool {
        get {
            return bool(forKey: "didBlockRiskyDomainsDefaultToTrue")
        }
        set {
            set(newValue, forKey: "didBlockRiskyDomainsDefaultToTrue")
        }
    }

    var isBlockRiskyDomainsOn: Bool {
        dnsSettingStorageValue.isBlockRiskyDomainsOn
    }

    var customDnsServers: [String] {
        dnsSettingStorageValue.dnsServers
    }

    var dnsSettings: NetworkProtectionDNSSettings {
        get {
            Self.dnsSettingsFromStorageValue(dnsSettingStorageValue)
        }

        set {
            switch newValue {
            case .ddg(let isBlockRiskyDomainsOn):
                let dnsServers = dnsSettingStorageValue.dnsServers
                dnsSettingStorageValue = StorableDNSSettings(dnsServers: dnsServers, isBlockRiskyDomainsOn: isBlockRiskyDomainsOn)
            case .custom(let dnsServers):
                let hosts = dnsServers.compactMap(\.toIPv4Host)
                let isBlockRiskyDomainsOn = dnsSettingStorageValue.isBlockRiskyDomainsOn
                if hosts.isEmpty {
                    dnsSettingStorageValue = StorableDNSSettings(isBlockRiskyDomainsOn: isBlockRiskyDomainsOn)
                } else {
                    dnsSettingStorageValue = StorableDNSSettings(usesCustomDNS: true, dnsServers: hosts, isBlockRiskyDomainsOn: isBlockRiskyDomainsOn)
                }
            }
        }
    }

    var dnsSettingsPublisher: AnyPublisher<NetworkProtectionDNSSettings, Never> {
        publisher(for: \.dnsSettingStorageValue)
            .map(Self.dnsSettingsFromStorageValue(_:))
            .eraseToAnyPublisher()
    }

    func resetDNSSettings() {
        dnsSettings = .ddg(blockRiskyDomains: isBlockRiskyDomainsOn)
    }
}
