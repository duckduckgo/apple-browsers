//
//  DetectedRequest.swift
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import TrackerRadarKit

public enum BlockingState: Codable {
    case blocked
    case allowed(reason: AllowReason)
}

public enum AllowReason: String, Codable {
    case protectionDisabled
    case ownedByFirstParty
    case ruleException
    case adClickAttribution
    case otherThirdPartyRequest
}

// Populated with relevant info at the point of detection.
public struct DetectedRequest: Encodable {

    public let url: String
    public let eTLDplus1: String?
    public let state: BlockingState
    public let ownerName: String?
    public let entityName: String?
    public let category: String?
    public let prevalence: Double?
    public let pageUrl: String

    public init(url: String, eTLDplus1: String?, knownTracker: KnownTracker?, entity: Entity?, state: BlockingState, pageUrl: String) {
        self.url = url
        self.eTLDplus1 = eTLDplus1
        self.state = state
        self.ownerName = knownTracker?.owner?.ownedBy ?? knownTracker?.owner?.name
        self.entityName = entity?.displayName
        self.category = knownTracker?.category
        self.prevalence = entity?.prevalence
        self.pageUrl = pageUrl
    }

    public var domain: String? {
        guard let escapedStringURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: escapedStringURL)?.host
    }

    public var networkNameForDisplay: String {
        entityName ?? eTLDplus1 ?? url
    }

    public var isBlocked: Bool {
        state == .blocked
    }

}

extension DetectedRequest: Hashable, Equatable {

    public static func == (lhs: DetectedRequest, rhs: DetectedRequest) -> Bool {
        ((lhs.entityName != nil || rhs.entityName != nil) && lhs.entityName == rhs.entityName)
        && lhs.domain ?? "" == rhs.domain ?? ""
        && lhs.state == rhs.state
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.entityName)
        hasher.combine(self.domain)
        hasher.combine(self.state)
    }

}

extension BlockingState: Equatable, Hashable {

    public static func == (lhs: BlockingState, rhs: BlockingState) -> Bool {
        switch (lhs, rhs) {
        case (.blocked, .blocked):
            return true
        case let (.allowed(lhsReason), .allowed(rhsReason)):
            return lhsReason == rhsReason
        default:
            return false
        }
    }

}
