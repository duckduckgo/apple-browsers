//
//  TrackerProtectionSubfeature.swift
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

import Common
import Foundation
import os.log
import UserScript
import WebKit

/// Delegate protocol for tracker protection events from C-S-S.
///
/// Replaces `ContentBlockerRulesUserScriptDelegate` and `SurrogatesUserScriptDelegate`
/// for the C-S-S tracker protection integration.
@MainActor
public protocol TrackerProtectionSubfeatureDelegate: AnyObject {

    /// Called when a tracker is detected (blocked or allowed).
    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didDetectTracker tracker: TrackerProtectionSubfeature.TrackerDetection)

    /// Called when a surrogate is injected for a blocked tracker.
    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didInjectSurrogate surrogate: TrackerProtectionSubfeature.SurrogateInjection)

    /// Whether tracker processing should proceed (e.g., protection might be disabled for a site).
    func trackerProtectionShouldProcessTrackers(_ subfeature: TrackerProtectionSubfeature) -> Bool
}

/// Subfeature that handles tracker detection and surrogate injection messages from C-S-S.
///
/// The JavaScript `trackerProtection` feature in C-S-S detects trackers, injects surrogates,
/// and reports results back to native via this subfeature. This replaces the legacy
/// `SurrogatesUserScript` and `ContentBlockerRulesUserScript`.
///
/// ## Usage
///
/// ```swift
/// let trackerProtection = TrackerProtectionSubfeature()
/// trackerProtection.delegate = self
/// contentScopeUserScript.registerSubfeature(delegate: trackerProtection)
/// ```
///
/// Add `TrackerProtectionSubfeature.featureNameValue` to `allowedNonisolatedFeatures`
/// when creating the `ContentScopeUserScript`.
public final class TrackerProtectionSubfeature: NSObject, Subfeature {

    // MARK: - Types

    /// Data about a detected tracker from C-S-S.
    public struct TrackerDetection: Decodable {
        public let url: String
        public let blocked: Bool
        public let reason: String?
        public let isSurrogate: Bool
        public let pageUrl: String
        public let entityName: String?
        public let ownerName: String?
        public let category: String?
        public let prevalence: Double?
        public let isAllowlisted: Bool?
    }

    /// Data about a surrogate injection from C-S-S.
    public struct SurrogateInjection: Decodable {
        public let url: String
        public let blocked: Bool
        public let reason: String?
        public let isSurrogate: Bool
        public let pageUrl: String
        public let entityName: String?
        public let ownerName: String?
    }

    // MARK: - Properties

    public static let featureNameValue = "trackerProtection"

    public let messageOriginPolicy: MessageOriginPolicy = .all
    public let featureName: String = TrackerProtectionSubfeature.featureNameValue
    public weak var broker: UserScriptMessageBroker?
    public weak var delegate: TrackerProtectionSubfeatureDelegate?

    // MARK: - Subfeature

    public override init() {
        super.init()
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    enum MessageNames: String, CaseIterable {
        case trackerDetected
        case surrogateInjected
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .trackerDetected:
            return { [weak self] in try await self?.handleTrackerDetected(params: $0, original: $1) }
        case .surrogateInjected:
            return { [weak self] in try await self?.handleSurrogateInjected(params: $0, original: $1) }
        default:
            return nil
        }
    }

    // MARK: - Handlers

    @MainActor
    private func handleTrackerDetected(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard delegate?.trackerProtectionShouldProcessTrackers(self) == true else {
            return nil
        }

        guard let detection = Self.decode(TrackerDetection.self, from: params) else {
            Logger.general.warning("TrackerProtection: Failed to decode trackerDetected params")
            return nil
        }

        delegate?.trackerProtection(self, didDetectTracker: detection)
        return nil
    }

    @MainActor
    private func handleSurrogateInjected(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard delegate?.trackerProtectionShouldProcessTrackers(self) == true else {
            return nil
        }

        guard let injection = Self.decode(SurrogateInjection.self, from: params) else {
            Logger.general.warning("TrackerProtection: Failed to decode surrogateInjected params")
            return nil
        }

        delegate?.trackerProtection(self, didInjectSurrogate: injection)
        return nil
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ type: T.Type, from params: Any) -> T? {
        guard let dict = params as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return decoded
    }
}
