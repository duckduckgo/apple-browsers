//
//  LinkCleaner.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public class LinkCleaner {

    public var lastAMPURLString: String?
    public var urlParametersRemoved: Bool = false

    private let privacyManager: PrivacyConfigurationManaging
    private var privacyConfig: PrivacyConfiguration { privacyManager.privacyConfig }

    public init(privacyManager: PrivacyConfigurationManaging) {
        self.privacyManager = privacyManager
    }

    public func ampFormat(matching url: URL) -> String? {
        let ampFormats = TrackingLinkSettings(fromConfig: privacyConfig).ampLinkFormats
        for format in ampFormats where url.absoluteString.matches(pattern: format) {
            return format
        }

        return nil
    }

    public func isURLExcluded(url: URL, feature: PrivacyFeature = .ampLinks) -> Bool {
        guard let host = url.host else { return true }
        guard url.scheme == "http" || url.scheme == "https" else { return true }

        return !privacyConfig.isFeature(feature, enabledForDomain: host)
    }

    public func extractCanonicalFromAMPLink(initiator: URL?, destination url: URL?) -> URL? {
        lastAMPURLString = nil
        guard privacyConfig.isEnabled(featureKey: .ampLinks) else { return nil }
        guard let url = url, !isURLExcluded(url: url) else { return nil }
        if let initiator = initiator, isURLExcluded(url: initiator) {
            return nil
        }

        guard let ampFormat = ampFormat(matching: url) else { return nil }

        do {
            let ampStr = url.absoluteString
            let regex = try NSRegularExpression(pattern: ampFormat, options: [.caseInsensitive])
            let matches = regex.matches(in: url.absoluteString,
                                        options: [],
                                        range: NSRange(ampStr.startIndex..<ampStr.endIndex,
                                                       in: ampStr))
            guard let match = matches.first else { return nil }

            let matchRange = match.range(at: 1)
            if let substrRange = Range(matchRange, in: ampStr) {
                var urlStr = String(ampStr[substrRange])
                if !urlStr.hasPrefix("http") {
                    urlStr = "https://\(urlStr)"
                }

                if let cleanUrl = URL(string: urlStr), !isURLExcluded(url: cleanUrl) {
                    lastAMPURLString = ampStr
                    return cleanUrl
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    public func cleanTrackingParameters(initiator: URL?, url: URL?) -> URL? {
        urlParametersRemoved = false
        guard privacyConfig.isEnabled(featureKey: .trackingParameters) else { return url }
        guard let url = url, !isURLExcluded(url: url, feature: .trackingParameters) else { return url }
        if let initiator = initiator, isURLExcluded(url: initiator, feature: .trackingParameters) {
            return url
        }

        guard var urlsComps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        guard let queryParams = urlsComps.percentEncodedQueryItems, queryParams.count > 0 else {
            return url
        }

        let trackingParams = TrackingLinkSettings(fromConfig: privacyConfig).trackingParameters

        let preservedParams: [URLQueryItem] = queryParams.filter { param in
            if trackingParams.contains(where: { $0 == param.name }) {
                urlParametersRemoved = true
                return false
            }

            return true
        }

        if urlParametersRemoved {
            urlsComps.percentEncodedQueryItems = preservedParams.count > 0 ? preservedParams : nil
            return urlsComps.url
        }
        return url
    }
}
