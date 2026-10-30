//
//  SponsorBlockSubfeature.swift
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

import Combine
import Foundation
import os.log
import UserScript
import WebKit

/// Subfeature that handles messages from the content-scope-scripts `sponsorBlock` feature.
///
/// Register it with the isolated `ContentScopeUserScript`, since `sponsorBlock` runs in the isolated world.
public final class SponsorBlockSubfeature: NSObject, Subfeature {

    /// The feature name used for message routing. Must match the JavaScript feature name.
    public static let featureNameValue = "sponsorBlock"
    /// Bump when the `getConfig` payload changes; the page keeps understanding older versions.
    static let contractVersion = 1

    public let messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        .exact(hostname: "youtube.com"),
        .exact(hostname: "www.youtube.com"),
        .exact(hostname: "m.youtube.com"),
        // Duck Player embeds the video in a youtube-nocookie.com iframe.
        .exact(hostname: "youtube-nocookie.com"),
        .exact(hostname: "www.youtube-nocookie.com")
    ])

    public let featureName: String = SponsorBlockSubfeature.featureNameValue

    public weak var broker: UserScriptMessageBroker?

    private let segmentsProvider: SponsorBlockSegmentsProvider
    private let preferences: SponsorBlockPreferences
    private let isFeatureFlagOn: () -> Bool
    /// The page that asked for config; `onConfigChanged` is pushed back into it.
    private weak var webView: WKWebView?
    private var preferencesCancellable: AnyCancellable?

    public init(segmentsProvider: SponsorBlockSegmentsProvider = .shared,
                preferences: SponsorBlockPreferences,
                isFeatureFlagOn: @escaping () -> Bool) {
        self.segmentsProvider = segmentsProvider
        self.preferences = preferences
        self.isFeatureFlagOn = isFeatureFlagOn
        super.init()
        preferencesCancellable = preferences.updates.sink { [weak self] in self?.pushConfigChanged() }
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    /// The page is answered with no segments and `enabled: false` while either gate is off.
    private var isEnabled: Bool { isFeatureFlagOn() && preferences.isEnabled }

    /// Message names that this subfeature handles.
    enum MessageNames: String, CaseIterable {
        case getSegments
        case getConfig
    }

    /// Subscription pushed to the page when a preference changes.
    static let onConfigChanged = "onConfigChanged"

    struct GetSegmentsResponse: Encodable {
        let segments: [SponsorBlockSegmentsProvider.Segment]
    }

    struct ConfigResponse: Encodable, Equatable {
        let enabled: Bool
        let skipMode: String
        let version: Int
    }

    struct ConfigUpdate: Encodable, Equatable {
        let enabled: Bool
        let skipMode: String
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .getSegments:
            return { [weak self] in try await self?.handleGetSegments(params: $0, original: $1) }
        case .getConfig:
            return { [weak self] in try await self?.handleGetConfig(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func handleGetConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        webView = original.webView
        return ConfigResponse(enabled: isEnabled, skipMode: preferences.skipMode.rawValue, version: Self.contractVersion)
    }

    private func pushConfigChanged() {
        guard let broker, let webView else { return }
        let update = ConfigUpdate(enabled: isEnabled, skipMode: preferences.skipMode.rawValue)
        broker.push(method: Self.onConfigChanged, params: update, for: self, into: webView)
    }

    /// Rejects malformed params, but every lookup failure resolves to an empty list: the page never retries.
    private func handleGetSegments(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let query = try SponsorBlockSegmentsProvider.Query(params: params)
        guard isEnabled else { return GetSegmentsResponse(segments: []) }
        do {
            return GetSegmentsResponse(segments: try await segmentsProvider.segments(for: query))
        } catch {
            // Domain and code only: a URLError description can carry the request URL, which holds the hash prefix.
            let error = error as NSError
            Logger.sponsorBlock.error("getSegments lookup failed: \(error.domain, privacy: .public) \(error.code)")
            return GetSegmentsResponse(segments: [])
        }
    }
}
