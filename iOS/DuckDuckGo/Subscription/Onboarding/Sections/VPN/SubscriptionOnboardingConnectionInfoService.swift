//
//  SubscriptionOnboardingConnectionInfoService.swift
//  DuckDuckGo
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

/// The current connection's public IP and coarse geolocation, as returned by
/// `https://duckduckgo.com/connection.json`. While the VPN is off this describes the customer's real
/// (visible) connection; once the VPN is on the same endpoint reports the VPN egress connection instead.
struct SubscriptionOnboardingConnectionInfo: Decodable, Equatable {
    /// The public IPv4 address, e.g. `"31.120.130.50"`.
    let ip: String
    /// The city name, e.g. `"Madrid"`.
    let city: String
    /// The ISO 3166-1 alpha-2 country code, e.g. `"ES"`.
    let country: String
}

extension SubscriptionOnboardingConnectionInfo {
    /// A display location for the VPN info card, e.g. `"🇪🇸 Madrid, Spain"`: the country's flag emoji (via
    /// the shared ``NetworkProtectionVPNCountryLabelsModel``), the city, and the localized country name.
    /// `locale` is injectable so the country name is deterministic under test.
    func displayLocation(locale: Locale = .current) -> String {
        let flag = NetworkProtectionVPNCountryLabelsModel(country: country).emoji
        let countryName = locale.localizedString(forRegionCode: country) ?? country
        return "\(flag) \(city), \(countryName)"
    }
}

/// Fetches the current connection's public IP + geolocation. A protocol so the VPN activation view model
/// can be previewed and unit-tested without touching the network.
protocol SubscriptionOnboardingConnectionInfoService {
    func fetchConnectionInfo() async throws -> SubscriptionOnboardingConnectionInfo
}

/// Reads `https://duckduckgo.com/connection.json`, following the app's lightweight-GET convention
/// (`URLSession.shared.data(from:)` + `JSONDecoder`; see `YoutubeOembedService`).
struct DefaultSubscriptionOnboardingConnectionInfoService: SubscriptionOnboardingConnectionInfoService {
    private static let connectionInfoURL = URL(string: "https://duckduckgo.com/connection.json")!

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchConnectionInfo() async throws -> SubscriptionOnboardingConnectionInfo {
        let (data, _) = try await urlSession.data(from: Self.connectionInfoURL)
        return try JSONDecoder().decode(SubscriptionOnboardingConnectionInfo.self, from: data)
    }
}
