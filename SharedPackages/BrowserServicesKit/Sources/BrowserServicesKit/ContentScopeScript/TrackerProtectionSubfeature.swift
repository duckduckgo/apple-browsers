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
import ContentBlocking
import Foundation
import os.log
import TrackerRadarKit
import UserScript
import WebKit

public enum TrackerBlockingReason: String {
    case firstParty = "first party"
    case ruleException = "matched rule - exception"
    case defaultIgnore = "default ignore"
    case matchedRuleIgnore = "matched rule - ignore"
    case defaultBlock = "default block"
    case surrogate = "matched rule - surrogate"
    case matchedRuleBlock = "matched rule - block"
    case noMatch = "no match"
    case unprotectedDomain
    case thirdPartyRequest
    case thirdPartyRequestOwnedByFirstParty

    var allowReason: AllowReason {
        switch self {
        case .firstParty, .thirdPartyRequestOwnedByFirstParty:
            return .ownedByFirstParty
        case .ruleException, .defaultIgnore, .matchedRuleIgnore:
            return .ruleException
        case .unprotectedDomain:
            return .protectionDisabled
        case .defaultBlock, .surrogate, .matchedRuleBlock, .noMatch, .thirdPartyRequest:
            return .otherThirdPartyRequest
        }
    }

    var isFirstParty: Bool {
        self == .firstParty
    }

    var isThirdPartyRequest: Bool {
        switch self {
        case .noMatch, .thirdPartyRequest, .thirdPartyRequestOwnedByFirstParty:
            return true
        default:
            return false
        }
    }
}

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

    /// Called when the current C-S-S bridge emits a fully classified tracker event.
    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didDetectTracker tracker: TrackerProtectionSubfeature.TrackerDetection)

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

    /// Classified tracker detection notification from the current C-S-S bridge.
    public struct TrackerDetection: Decodable {
        public let url: String
        public let blocked: Bool
        public let reason: TrackerBlockingReason?
        public let isSurrogate: Bool
        public let pageUrl: String
        public let entityName: String?
        public let ownerName: String?
        public let category: String?
        public let prevalence: Double?
        public let isAllowlisted: Bool?

        enum CodingKeys: String, CodingKey {
            case url
            case blocked
            case reason
            case isSurrogate
            case pageUrl
            case entityName
            case ownerName
            case category
            case prevalence
            case isAllowlisted
        }

        public init(url: String,
                    blocked: Bool,
                    reason: TrackerBlockingReason?,
                    isSurrogate: Bool,
                    pageUrl: String,
                    entityName: String?,
                    ownerName: String?,
                    category: String?,
                    prevalence: Double?,
                    isAllowlisted: Bool?) {
            self.url = url
            self.blocked = blocked
            self.reason = reason
            self.isSurrogate = isSurrogate
            self.pageUrl = pageUrl
            self.entityName = entityName
            self.ownerName = ownerName
            self.category = category
            self.prevalence = prevalence
            self.isAllowlisted = isAllowlisted
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decode(String.self, forKey: .url)
            blocked = try container.decode(Bool.self, forKey: .blocked)
            if let rawReason = try container.decodeIfPresent(String.self, forKey: .reason) {
                reason = TrackerBlockingReason(rawValue: rawReason)
            } else {
                reason = nil
            }
            isSurrogate = try container.decode(Bool.self, forKey: .isSurrogate)
            pageUrl = try container.decode(String.self, forKey: .pageUrl)
            entityName = try container.decodeIfPresent(String.self, forKey: .entityName)
            ownerName = try container.decodeIfPresent(String.self, forKey: .ownerName)
            category = try container.decodeIfPresent(String.self, forKey: .category)
            prevalence = try container.decodeIfPresent(Double.self, forKey: .prevalence)
            isAllowlisted = try container.decodeIfPresent(Bool.self, forKey: .isAllowlisted)
        }
    }

    // MARK: - Properties

    public static let featureNameValue = "trackerProtection"

    public let messageOriginPolicy: MessageOriginPolicy = .all
    public let featureName: String = TrackerProtectionSubfeature.featureNameValue
    public weak var broker: UserScriptMessageBroker?
    public weak var delegate: TrackerProtectionSubfeatureDelegate?
    public var currentAdClickAttributionVendor: String?
    public var currentAdClickAttributionAllowlistHosts: [String] = []
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
        case trackerDetected
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .resourceObserved:
            return { [weak self] in try await self?.handleResourceObserved(params: $0, original: $1) }
        case .surrogateInjected:
            return { [weak self] in try await self?.handleSurrogateInjected(params: $0, original: $1) }
        case .trackerDetected:
            return { [weak self] in try await self?.handleTrackerDetected(params: $0, original: $1) }
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
