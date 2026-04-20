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
import PrivacyConfig
import TrackerRadarKit

/// Classifies raw C-S-S resource observations into DetectedRequest using native TrackerResolver.
///
/// C-S-S sends pre-block `{url, resourceType, potentiallyBlocked, pageUrl}` signals.
/// `potentiallyBlocked` reflects JS-side heuristics but may diverge from native rule evaluation
/// (e.g. `options.domains` matching). The mapper therefore computes its own `potentiallyBlocked`
/// from `contentBlockingEnabled` and the native tracker allowlist rather than passing through
/// the JS value, ensuring native-authoritative classification.
///
/// Classification uses a multi-TDS loop:
/// 1. Try each supplementary TDS (CTL, ad-attribution) with the ad-click vendor —
///    if any returns blocked, use it immediately.
/// 2. Fall back to the main TDS without vendor.
/// 3. If no tracker found, synthesize a third-party request when cross-site.
public struct TrackerProtectionEventMapper {

    private let tld: TLD
    private let mainTrackerData: TrackerData
    private let supplementaryTrackerData: [TrackerData]
    private let unprotectedSites: [String]
    private let tempList: [String]
    private let contentBlockingEnabled: Bool
    /// Pre-compiled allowlist: domain → [(regex, domains)] for O(1) lookup + match without
    /// per-call NSRegularExpression compilation.
    private let compiledAllowlist: [String: [(regex: NSRegularExpression, domains: [String])]]

    public init(tld: TLD,
                mainTrackerData: TrackerData,
                supplementaryTrackerData: [TrackerData] = [],
                unprotectedSites: [String],
                tempList: [String],
                contentBlockingEnabled: Bool,
                trackerAllowlist: PrivacyConfigurationData.TrackerAllowlistData = [:]) {
        self.tld = tld
        self.mainTrackerData = mainTrackerData
        self.supplementaryTrackerData = supplementaryTrackerData
        self.unprotectedSites = unprotectedSites
        self.tempList = tempList
        self.contentBlockingEnabled = contentBlockingEnabled
        self.compiledAllowlist = Self.compileAllowlist(trackerAllowlist)
    }

    /// Convenience init matching the old single-resolver API.
    public init(tld: TLD, trackerResolver: TrackerResolver, privacyConfig: PrivacyConfiguration) {
        self.tld = tld
        self.mainTrackerData = trackerResolver.tds
        self.supplementaryTrackerData = []
        self.unprotectedSites = trackerResolver.unprotectedSites
        self.tempList = trackerResolver.tempList
        self.contentBlockingEnabled = privacyConfig.isEnabled(featureKey: .contentBlocking)
        self.compiledAllowlist = Self.compileAllowlist(privacyConfig.trackerAllowlist.entries)
    }

    /// Pre-compile all allowlist regex patterns at init time to avoid per-call compilation.
    private static func compileAllowlist(
        _ allowlist: PrivacyConfigurationData.TrackerAllowlistData
    ) -> [String: [(regex: NSRegularExpression, domains: [String])]] {
        var compiled: [String: [(regex: NSRegularExpression, domains: [String])]] = [:]
        for (domain, entries) in allowlist {
            compiled[domain] = entries.compactMap { entry in
                guard let regex = try? NSRegularExpression(pattern: entry.rule, options: []) else { return nil }
                return (regex: regex, domains: entry.domains)
            }
        }
        return compiled
    }

    // MARK: - ResourceObservation classification

    /// Classify a raw resource observation using the multi-TDS loop that mirrors the legacy pipeline.
    ///
    /// Returns `nil` for same-site observations. Content rules only block
    /// third-party loads (`load-type: ["third-party"]`), so a same-site
    /// tracker is never actually blocked by WebKit. The old pipeline's
    /// `ContentBlockerRulesUserScript` suppressed these via `isFirstParty`
    /// guards before reporting to the delegate.
    public func classifyResource(_ observation: TrackerProtectionSubfeature.ResourceObservation,
                                 adClickAttributionVendor: String? = nil) -> DetectedRequest? {
        guard !isSameSiteObservation(observation) else { return nil }
        return classifyUrl(observation.url,
                           pageUrlString: observation.pageUrl,
                           resourceType: observation.resourceType,
                           potentiallyBlocked: contentBlockingEnabled,
                           adClickAttributionVendor: adClickAttributionVendor)
    }

    // MARK: - SurrogateInjection mapping

    /// Map a surrogate injection signal to a DetectedRequest.
    /// Surrogates are only injected for blocked requests, so `potentiallyBlocked` is always
    /// derived from `contentBlockingEnabled`.
    public func classifySurrogate(_ surrogate: TrackerProtectionSubfeature.SurrogateInjection,
                                  adClickAttributionVendor: String? = nil) -> DetectedRequest? {
        return classifyUrl(surrogate.url,
                           pageUrlString: surrogate.pageUrl,
                           resourceType: "script",
                           potentiallyBlocked: contentBlockingEnabled,
                           adClickAttributionVendor: adClickAttributionVendor)
    }

    /// Extract the surrogate host from the injection URL.
    public func surrogateHost(from surrogate: TrackerProtectionSubfeature.SurrogateInjection) -> String? {
        return URL(string: surrogate.url)?.host
    }

    // MARK: - Classification helpers

    /// Returns true when request and page share the same eTLD+1.
    public func isSameSiteObservation(_ observation: TrackerProtectionSubfeature.ResourceObservation) -> Bool {
        let requestETLDplus1 = tld.eTLDplus1(forStringURL: observation.url)
        let pageETLDplus1 = tld.eTLDplus1(forStringURL: observation.pageUrl)
        guard let requestETLDplus1, let pageETLDplus1 else { return false }
        return requestETLDplus1 == pageETLDplus1
    }

    /// Build a DetectedRequest for a non-TDS cross-site resource (third-party request).
    /// Affiliated entities (same entity as the page) are reported as `.ownedByFirstParty`;
    /// unaffiliated cross-site resources are reported as `.otherThirdPartyRequest`.
    public func makeThirdPartyRequest(from observation: TrackerProtectionSubfeature.ResourceObservation) -> DetectedRequest? {
        guard !isSameSiteObservation(observation) else { return nil }
        let requestETLDp1 = tld.eTLDplus1(forStringURL: observation.url) ?? observation.url
        let entity = mainTrackerData.findEntity(forHost: requestETLDp1)
            ?? Entity(displayName: requestETLDp1, domains: nil, prevalence: nil)
        let mainResolver = TrackerResolver(tds: mainTrackerData,
                                           unprotectedSites: unprotectedSites,
                                           tempList: tempList,
                                           tld: tld)
        let isAffiliated = mainResolver.isPageAffiliatedWithTrackerEntity(
            pageUrlString: observation.pageUrl, trackerEntity: entity)
        let state: BlockingState = isAffiliated
            ? .allowed(reason: .ownedByFirstParty)
            : .allowed(reason: .otherThirdPartyRequest)
        return DetectedRequest(url: observation.url,
                               eTLDplus1: requestETLDp1,
                               knownTracker: nil,
                               entity: entity,
                               state: state,
                               pageUrl: observation.pageUrl)
    }

    // MARK: - Private

    /// Multi-TDS classification loop.
    ///
    /// 1. Try each supplementary TDS (CTL, ad-attribution) with ad-click vendor.
    ///    If any returns blocked, use it immediately.
    /// 2. Fall back to the main TDS without vendor.
    /// 3. Main result overwrites non-blocked supplementary candidates (by design).
    ///    This is correct because the splitter removes attribution trackers from main TDS,
    ///    so main returns nil for those URLs and the supplementary candidate survives.
    private func classifyUrl(_ urlString: String,
                             pageUrlString: String,
                             resourceType: String,
                             potentiallyBlocked: Bool,
                             adClickAttributionVendor: String?) -> DetectedRequest? {
        var candidate: DetectedRequest?

        for trackerData in supplementaryTrackerData {
            let resolver = TrackerResolver(tds: trackerData,
                                           unprotectedSites: unprotectedSites,
                                           tempList: tempList,
                                           tld: tld,
                                           adClickAttributionVendor: adClickAttributionVendor)
            if let tracker = resolver.trackerFromUrl(urlString,
                                                     pageUrlString: pageUrlString,
                                                     resourceType: resourceType,
                                                     potentiallyBlocked: potentiallyBlocked) {
                if tracker.isBlocked {
                    return applyOverrides(tracker, urlString: urlString, pageUrlString: pageUrlString)
                }
                candidate = tracker
            }
        }

        let mainResolver = TrackerResolver(tds: mainTrackerData,
                                           unprotectedSites: unprotectedSites,
                                           tempList: tempList,
                                           tld: tld)
        if let tracker = mainResolver.trackerFromUrl(urlString,
                                                     pageUrlString: pageUrlString,
                                                     resourceType: resourceType,
                                                     potentiallyBlocked: potentiallyBlocked) {
            candidate = tracker
        }

        if let result = candidate, result.isBlocked {
            return applyOverrides(result, urlString: urlString, pageUrlString: pageUrlString)
        }

        return candidate
    }

    /// Chain of post-classification overrides: allowlist first, then temp-list subdomain.
    private func applyOverrides(_ request: DetectedRequest,
                                urlString: String,
                                pageUrlString: String) -> DetectedRequest {
        let afterAllowlist = applyAllowlistOverride(request, urlString: urlString, pageUrlString: pageUrlString)
        guard afterAllowlist.isBlocked else { return afterAllowlist }
        return applyTempListSubdomainOverride(afterAllowlist, pageUrlString: pageUrlString)
    }

    /// If the tracker is blocked but the native allowlist says it should be allowed,
    /// re-classify as `.allowed(reason: .ruleException)`.
    private func applyAllowlistOverride(_ request: DetectedRequest,
                                        urlString: String,
                                        pageUrlString: String) -> DetectedRequest {
        guard request.isBlocked,
              isTrackerAllowlisted(urlString, pageUrlString: pageUrlString)
        else { return request }

        return DetectedRequest(url: request.url,
                               eTLDplus1: request.eTLDplus1,
                               ownerName: request.ownerName,
                               entityName: request.entityName,
                               category: request.category,
                               prevalence: request.prevalence,
                               state: .allowed(reason: .ruleException),
                               pageUrl: request.pageUrl)
    }

    /// Mirrors the tracker allowlist matching from WKContentRuleList generation:
    /// the request URL must match a rule pattern, and the page host must be in the
    /// rule's domain list (or the domain list contains `<all>`).
    private func isTrackerAllowlisted(_ urlString: String, pageUrlString: String) -> Bool {
        guard !compiledAllowlist.isEmpty,
              let requestURL = URL(string: urlString),
              let requestHost = requestURL.host,
              let pageHost = URL(string: pageUrlString)?.host
        else { return false }

        // Build a normalized URL string for rule matching: strip port, query, and
        // semicolon-delimited parameters — mirroring WKContentRuleList generation behavior.
        let normalizedForMatching = normalizeURLForAllowlistMatching(requestURL)

        // Walk up the request host's domain parts to find a matching allowlist entry,
        // mirroring the subdomain fallback used by C-S-S and content rule generation.
        var domainParts = requestHost.split(separator: ".").map(String.init)
        while domainParts.count > 1 {
            let domain = domainParts.joined(separator: ".")
            if let entries = compiledAllowlist[domain] {
                for entry in entries {
                    guard entry.regex.firstMatch(in: normalizedForMatching, options: [],
                                                 range: NSRange(normalizedForMatching.startIndex..., in: normalizedForMatching)) != nil
                    else { continue }

                    if entry.domains.contains("<all>") { return true }

                    // Walk up the page host's domain parts to match entry domains.
                    var pageParts = pageHost.split(separator: ".").map(String.init)
                    while pageParts.count > 1 {
                        if entry.domains.contains(pageParts.joined(separator: ".")) {
                            return true
                        }
                        pageParts.removeFirst()
                    }
                }
            }
            domainParts.removeFirst()
        }
        return false
    }

    /// Strips port, query string, and semicolon parameters from a URL for allowlist
    /// rule matching, producing `scheme://host/path` with no trailing artifacts.
    private func normalizeURLForAllowlistMatching(_ url: URL) -> String {
        let scheme = url.scheme ?? "https"
        guard let host = url.host else { return url.absoluteString }
        var path = url.path
        // Strip semicolon-delimited parameters (e.g. /videos.js;a=123&b=abc → /videos.js)
        if let semicolonRange = path.range(of: ";") {
            path = String(path[..<semicolonRange.lowerBound])
        }
        return "\(scheme)://\(host)\(path)"
    }

    /// TrackerResolver uses exact string matching for tempList, which misses subdomains.
    /// Content rules (WKContentRuleList) use `if-domain` with subdomain coverage, so a page on
    /// sub.example.com is correctly unblocked when example.com is in the temp list.
    /// This override restores parity by walking up the page host's domain parts.
    ///
    /// Locally-unprotected sites (unprotectedSites) intentionally remain exact-host only.
    private func applyTempListSubdomainOverride(_ request: DetectedRequest,
                                                pageUrlString: String) -> DetectedRequest {
        guard request.isBlocked,
              isPageOnTempListWithSubdomains(pageUrlString)
        else { return request }

        return DetectedRequest(url: request.url,
                               eTLDplus1: request.eTLDplus1,
                               ownerName: request.ownerName,
                               entityName: request.entityName,
                               category: request.category,
                               prevalence: request.prevalence,
                               state: .allowed(reason: .protectionDisabled),
                               pageUrl: request.pageUrl)
    }

    /// Subdomain-aware temp-list matching: walks up the page host's domain parts
    /// to find a match in the temp list. For example, if tempList contains "example.com",
    /// this matches pages on sub.example.com, a.b.example.com, etc.
    private func isPageOnTempListWithSubdomains(_ pageUrlString: String) -> Bool {
        guard !tempList.isEmpty,
              let pageHost = URL(string: pageUrlString)?.host
        else { return false }

        if tempList.contains(pageHost) { return true }

        var parts = pageHost.split(separator: ".").map(String.init)
        while parts.count > 2 {
            parts.removeFirst()
            if tempList.contains(parts.joined(separator: ".")) {
                return true
            }
        }
        return false
    }
}
