//
//  TrackerStatsSubfeature.swift
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
import WebKit
import UserScript
import os.log

/// Delegate protocol for tracker stats events
/// Replaces ContentBlockerRulesUserScriptDelegate and SurrogatesUserScriptDelegate for C-S-S integration
@MainActor
public protocol TrackerStatsSubfeatureDelegate: AnyObject {
    /// Called when a tracker is detected (blocked or allowed)
    func trackerStats(_ subfeature: TrackerStatsSubfeature,
                      didDetectTracker tracker: TrackerStatsSubfeature.TrackerDetection)

    /// Called when a surrogate is injected for a blocked tracker
    func trackerStats(_ subfeature: TrackerStatsSubfeature,
                      didInjectSurrogate surrogate: TrackerStatsSubfeature.SurrogateInjection)

    /// Check if Click-to-Load feature is enabled (for fb-sdk.js surrogate)
    func trackerStatsShouldEnableCTL(_ subfeature: TrackerStatsSubfeature) -> Bool

    /// Check if tracker processing should be enabled (e.g., protection might be disabled for site)
    func trackerStatsShouldProcessTrackers(_ subfeature: TrackerStatsSubfeature) -> Bool
}

/// Handles tracker-stats feature messages from C-S-S
///
/// This subfeature works together with SurrogatesInjectionUserScript:
/// - SurrogatesInjectionUserScript injects surrogate functions as `window.__ddgSurrogates`
/// - C-S-S tracker-stats reads from that global and executes surrogates
/// - This subfeature handles messages back from C-S-S (surrogate injection notifications, CTL checks)
public final class TrackerStatsSubfeature: Subfeature {

    // MARK: - Types

    /// Data about a detected tracker from C-S-S
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

    public struct SurrogateInjection: Decodable {
        public let url: String
        public let blocked: Bool
        public let reason: String?
        public let isSurrogate: Bool
        public let pageUrl: String
    }

    // MARK: - Properties

    public var broker: UserScriptMessageBroker?
    public weak var delegate: TrackerStatsSubfeatureDelegate?

    public var featureName: String = "trackerStats"

    public var messageOriginPolicy: MessageOriginPolicy = .all

    // MARK: - Initialization

    public init(delegate: TrackerStatsSubfeatureDelegate? = nil) {
        self.delegate = delegate
    }

    // MARK: - Subfeature

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        switch methodName {
        case "surrogateInjected":
            return handleSurrogateInjected
        case "isCTLEnabled":
            return handleIsCTLEnabled
        case "trackerDetected":
            return handleTrackerDetected
        default:
            return nil
        }
    }

    // MARK: - Handlers

    /// Handle surrogate injection notification from C-S-S
    @MainActor
    private func handleSurrogateInjected(params: Any, message: WKScriptMessage) async throws -> Encodable? {
        guard delegate?.trackerStatsShouldProcessTrackers(self) == true else {
            return nil
        }

        guard let paramsDict = params as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict),
              let injection = try? JSONDecoder().decode(SurrogateInjection.self, from: jsonData) else {
            Logger.general.warning("TrackerStats: Failed to decode surrogateInjected params")
            return nil
        }

        Logger.general.debug("TrackerStats: Surrogate injected for \(injection.url, privacy: .public)")
        delegate?.trackerStats(self, didInjectSurrogate: injection)

        return nil
    }

    /// Handle CTL enabled check from C-S-S (for fb-sdk.js surrogate)
    @MainActor
    private func handleIsCTLEnabled(params: Any, message: WKScriptMessage) async throws -> Encodable? {
        let ctlEnabled = delegate?.trackerStatsShouldEnableCTL(self) ?? false
        return ctlEnabled
    }

    /// Handle tracker detection from C-S-S (for privacy dashboard stats)
    @MainActor
    private func handleTrackerDetected(params: Any, message: WKScriptMessage) async throws -> Encodable? {
        guard delegate?.trackerStatsShouldProcessTrackers(self) == true else {
            return nil
        }

        guard let paramsDict = params as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict),
              let detection = try? JSONDecoder().decode(TrackerDetection.self, from: jsonData) else {
            Logger.general.warning("TrackerStats: Failed to decode trackerDetected params")
            return nil
        }

        Logger.general.debug("TrackerStats: Tracker detected \(detection.url, privacy: .public) blocked=\(detection.blocked)")
        delegate?.trackerStats(self, didDetectTracker: detection)

        return nil
    }
}
