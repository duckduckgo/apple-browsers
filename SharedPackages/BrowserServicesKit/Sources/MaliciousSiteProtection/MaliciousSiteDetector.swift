//
//  MaliciousSiteDetector.swift
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

import Common
import CryptoKit
import Foundation
import Networking

public protocol MaliciousSiteDetecting {
    /// Evaluates the given URL to determine its malicious category (e.g., phishing, malware).
    /// - Parameter url: The URL to evaluate.
    /// - Returns: An optional `ThreatKind` indicating the type of threat, or `.none` if no threat is detected.
    func evaluate(_ url: URL) async -> ThreatKind?
}

public typealias SupportedThreatsProvider = () -> [ThreatKind]

/// Class responsible for detecting malicious sites by evaluating URLs against local filters and an external API.
/// entry point: `func evaluate(_: URL) async -> ThreatKind?`
public final class MaliciousSiteDetector: MaliciousSiteDetecting {
    // Type aliases for easier symbol navigation in Xcode.
    typealias PhishingDetector = MaliciousSiteDetector
    typealias MalwareDetector = MaliciousSiteDetector

    private enum Constants {
        static let hashPrefixStoreLength: Int = 8
        static let hashPrefixParamLength: Int = 4
    }

    private let apiClient: APIClient.Mockable
    private let dataManager: DataManaging
    private let eventMapping: EventMapping<Event>
    private let supportedThreatsProvider: SupportedThreatsProvider

    public convenience init(apiEnvironment: APIClientEnvironment, service: APIService = DefaultAPIService(urlSession: .shared), dataManager: DataManager, eventMapping: EventMapping<Event>, supportedThreatsProvider: @escaping SupportedThreatsProvider
    ) {
        self.init(apiClient: APIClient(environment: apiEnvironment, service: service), dataManager: dataManager, eventMapping: eventMapping, supportedThreatsProvider: supportedThreatsProvider)
    }

    init(apiClient: APIClient.Mockable, dataManager: DataManaging, eventMapping: EventMapping<Event>, supportedThreatsProvider: @escaping SupportedThreatsProvider) {
        self.apiClient = apiClient
        self.dataManager = dataManager
        self.eventMapping = eventMapping
        self.supportedThreatsProvider = supportedThreatsProvider
    }

    private func checkLocalFilters(hostHash: String, canonicalUrl: URL, for threatKind: ThreatKind) async -> Bool {
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: threatKind))
        let matchesLocalFilters = filterSet[hostHash]?.contains(where: { regex in
            canonicalUrl.absoluteString.matches(pattern: regex)
        }) ?? false

        return matchesLocalFilters
    }

    private func checkApiMatches(hostHash: String, canonicalUrl: URL) async -> Match? {
        let hashPrefixParam = String(hostHash.prefix(Constants.hashPrefixParamLength))
        let matches: [Match]
        do {
            matches = try await apiClient.matches(forHashPrefix: hashPrefixParam).matches
        } catch APIRequestV2.Error.urlSession(URLError.timedOut) {
            eventMapping.fire(.matchesApiTimeout)
            return nil
        } catch {
            eventMapping.fire(.matchesApiFailure(error))
            return nil
        }

        if let match = matches.first(where: { match in
            match.hash == hostHash && canonicalUrl.absoluteString.matches(pattern: match.regex)
        }) {
            return match
        }
        return nil
    }

    /// Evaluates the given URL to determine its malicious category (e.g., phishing, malware).
    public func evaluate(_ url: URL) async -> ThreatKind? {
        guard let canonicalHost = url.canonicalHost(),
              let canonicalUrl = url.canonicalURL() else { return .none }
        let supportedThreats = supportedThreatsProvider()

        let hostHash = canonicalHost.sha256
        let hashPrefix = String(hostHash.prefix(Constants.hashPrefixStoreLength))

        // 1. Check for matching hash prefixes.
        // The hash prefix list serves as a representation of the entire database:
        // every malicious website will have a hash prefix that it collides with.
        var hashPrefixMatchingThreatKinds = [ThreatKind]()
        for threatKind in supportedThreats { // e.g., phishing, malware, etc.
            let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: threatKind))
            if hashPrefixes.contains(hashPrefix) {
                hashPrefixMatchingThreatKinds.append(threatKind)
            }
        }

        // Return no threats if no matching hash prefixes are found in the database.
        guard !hashPrefixMatchingThreatKinds.isEmpty else { return .none }

        // 2. Check local Filter Sets.
        // The filter set acts as a local cache of some database entries, containing
        // the 5000 most common threats (or those most likely to collide with daily
        // browsing behaviors, based on Clickhouse's top 10k, ranked by Netcraft's risk rating).
        for threatKind in hashPrefixMatchingThreatKinds {
            let matches = await checkLocalFilters(hostHash: hostHash, canonicalUrl: canonicalUrl, for: threatKind)
            if matches {
                await fireErrorPageShown(threatKind: threatKind, clientSideHit: true)
                return threatKind
            }
        }

        // 3. If no locally cached filters matched, we will still make a request to the API
        // to check for potential matches on our backend.
        let match = await checkApiMatches(hostHash: hostHash, canonicalUrl: canonicalUrl)
        let threatKind = match?.category.flatMap(ThreatKind.init)
        if let threatKind {
            if !supportedThreats.contains(threatKind) {
                return .none
            }
            await fireErrorPageShown(threatKind: threatKind, clientSideHit: false)
            return threatKind
        }

        return .none
    }

    private func fireErrorPageShown(threatKind: ThreatKind, clientSideHit: Bool) async {
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: threatKind))
        // Send Pixel clientSideHit parameter only if filterSet size is greater than 100
        // https://app.asana.com/0/0/1209113403594297/1209141231997704/f
        let sanitisedClientSideHit = filterSet.filters.count > 100 ? clientSideHit : nil
        eventMapping.fire(.errorPageShown(category: threatKind, clientSideHit: sanitisedClientSideHit))
    }
}
