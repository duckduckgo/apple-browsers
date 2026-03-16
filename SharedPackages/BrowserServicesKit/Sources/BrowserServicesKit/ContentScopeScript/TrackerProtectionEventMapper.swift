//
//  TrackerProtectionEventMapper.swift
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
import ContentBlocking
import Foundation
import TrackerRadarKit

/// Shared converter for C-S-S tracker-protection events to native DetectedRequest.
/// Eliminates duplicated mapping logic between iOS TabViewController and macOS ContentBlockingTabExtension.
public struct TrackerProtectionEventMapper {

    private let tld: TLD

    public init(tld: TLD) {
        self.tld = tld
    }

    // MARK: - TrackerDetection mapping

    public func detectedRequest(from tracker: TrackerProtectionSubfeature.TrackerDetection) -> DetectedRequest {
        let reason = TrackerBlockingReason(rawValue: tracker.reason ?? "")
        let state: BlockingState = tracker.blocked ? .blocked : .allowed(reason: reason?.allowReason ?? .otherThirdPartyRequest)
        let eTLDplus1 = tld.eTLDplus1(forStringURL: tracker.url)

        return DetectedRequest(
            url: tracker.url,
            eTLDplus1: eTLDplus1,
            ownerName: tracker.ownerName,
            entityName: tracker.entityName,
            category: tracker.category,
            prevalence: tracker.prevalence,
            state: state,
            pageUrl: tracker.pageUrl
        )
    }

    // MARK: - SurrogateInjection mapping

    public func detectedRequest(from surrogate: TrackerProtectionSubfeature.SurrogateInjection) -> DetectedRequest {
        let eTLDplus1 = tld.eTLDplus1(forStringURL: surrogate.url)
        let surrogateHost = URL(string: surrogate.url)?.host ?? ""
        let entityName = surrogate.entityName ?? surrogateHost

        return DetectedRequest(
            url: surrogate.url,
            eTLDplus1: eTLDplus1,
            ownerName: surrogate.ownerName,
            entityName: entityName,
            category: nil,
            prevalence: nil,
            state: .blocked,
            pageUrl: surrogate.pageUrl
        )
    }

    // MARK: - Classification helpers

    public static func isThirdPartyRequest(_ tracker: TrackerProtectionSubfeature.TrackerDetection) -> Bool {
        return TrackerBlockingReason(rawValue: tracker.reason ?? "")?.isNonTrackerThirdPartyRequest ?? false
    }

    /// Returns true when request and page share the same eTLD+1.
    /// Same-site detections (both tracker and non-tracker) are suppressed
    /// from the privacy dashboard, matching legacy WebKit first-party behavior.
    public func isSameSiteDetection(_ tracker: TrackerProtectionSubfeature.TrackerDetection) -> Bool {
        let requestETLDplus1 = tld.eTLDplus1(forStringURL: tracker.url)
        let pageETLDplus1 = tld.eTLDplus1(forStringURL: tracker.pageUrl)

        guard let requestETLDplus1, let pageETLDplus1 else { return false }
        return requestETLDplus1 == pageETLDplus1
    }

    public func surrogateHost(from surrogate: TrackerProtectionSubfeature.SurrogateInjection) -> String? {
        return URL(string: surrogate.url)?.host
    }
}
