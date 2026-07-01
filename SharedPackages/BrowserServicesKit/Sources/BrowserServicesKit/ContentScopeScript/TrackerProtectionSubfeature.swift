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
import FoundationExtensions
import Foundation
import os.log
import TrackerRadarKit
import UserScript
import WebKit

/// Delegate protocol for tracker protection events from C-S-S.
///
/// C-S-S is a raw resource observer — native is sole classifier.
/// Raw observations are classified by `TrackerProtectionEventMapper` using `TrackerResolver`.
@MainActor
public protocol TrackerProtectionSubfeatureDelegate: AnyObject {

    /// Called when a resource is observed by C-S-S.
    /// Native classifies this via TrackerResolver to produce DetectedRequest.
    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didObserveResource observation: TrackerProtectionSubfeature.ResourceObservation)

    /// Called when a surrogate is injected by C-S-S (only when surrogateInjectionEnabled).
    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didInjectSurrogate surrogate: TrackerProtectionSubfeature.SurrogateInjection)

    /// Whether resource observation processing should proceed.
    func trackerProtectionShouldProcessTrackers(_ subfeature: TrackerProtectionSubfeature) -> Bool
}

/// Subfeature that handles resource observation and surrogate injection messages from C-S-S.
///
/// C-S-S emits raw `resourceObserved` signals with `{url, resourceType, potentiallyBlocked, pageUrl}`.
/// Native `TrackerProtectionEventMapper` classifies these via `TrackerResolver` with full TDS.
public final class TrackerProtectionSubfeature: NSObject, Subfeature {

    // MARK: - Types

    /// Raw resource observation from C-S-S. No classification — native decides.
    public struct ResourceObservation: Decodable {
        public let url: String
        public let resourceType: String
        public let potentiallyBlocked: Bool
        public let pageUrl: String

        public init(url: String, resourceType: String, potentiallyBlocked: Bool, pageUrl: String) {
            self.url = url
            self.resourceType = resourceType
            self.potentiallyBlocked = potentiallyBlocked
            self.pageUrl = pageUrl
        }
    }

    /// Surrogate injection notification from C-S-S.
    public struct SurrogateInjection: Decodable {
        public let url: String
        public let pageUrl: String
        public let surrogateName: String?

        public init(url: String, pageUrl: String, surrogateName: String?) {
            self.url = url
            self.pageUrl = pageUrl
            self.surrogateName = surrogateName
        }
    }

    // MARK: - Properties

    public static let featureNameValue = "trackerProtection"

    public let messageOriginPolicy: MessageOriginPolicy = .all
    public let featureName: String = TrackerProtectionSubfeature.featureNameValue
    public weak var broker: UserScriptMessageBroker?
    public weak var delegate: TrackerProtectionSubfeatureDelegate?
    public var currentAdClickAttributionVendor: String?
    public var currentAttributionTrackerData: TrackerData?

    // MARK: - Subfeature

    public override init() {
        super.init()
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    enum MessageNames: String, CaseIterable {
        case resourceObserved
        case surrogateInjected
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .resourceObserved:
            return { [weak self] in try await self?.handleResourceObserved(params: $0, original: $1) }
        case .surrogateInjected:
            return { [weak self] in try await self?.handleSurrogateInjected(params: $0, original: $1) }
        default:
            return nil
        }
    }

    // MARK: - Handlers

    @MainActor
    private func handleResourceObserved(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard delegate?.trackerProtectionShouldProcessTrackers(self) == true else {
            return nil
        }

        guard let observation = Self.decode(ResourceObservation.self, from: params) else {
            Logger.general.warning("TrackerProtection: Failed to decode resourceObserved params")
            return nil
        }

        delegate?.trackerProtection(self, didObserveResource: observation)
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
