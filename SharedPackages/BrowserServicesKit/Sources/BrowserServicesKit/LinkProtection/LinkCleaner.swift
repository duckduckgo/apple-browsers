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
import PrivacyConfig

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

        let trackingParams = TrackingLinkSettings(fromConfig: privacyConfig).trackingParameters
        guard let cleanedURL = PercentEncodedQueryFilter(parameterNames: trackingParams).filter(url: url) else {
            return url
        }

        urlParametersRemoved = true
        return cleanedURL
    }
}

/// Filters a URL's encoded query without creating a `URLQueryItem` for every parameter.
/// Delimiters are parsed in their percent-encoded form so surviving query items can be copied unchanged.
private struct PercentEncodedQueryFilter {

    private enum ASCII {
        static let numberSign: UInt8 = 0x23
        static let ampersand: UInt8 = 0x26
        static let equalsSign: UInt8 = 0x3D
        static let questionMark: UInt8 = 0x3F
    }

    private struct QueryInspection {
        let preservedItemCount: Int
        let preservedItemByteCount: Int
    }

    private let parameterNames: [String]

    init(parameterNames: [String]) {
        self.parameterNames = parameterNames
    }

    func filter(url: URL) -> URL? {
        let source = url.relativeString
        let bytes = source.utf8

        let fragmentStart = bytes.firstIndex(of: ASCII.numberSign) ?? bytes.endIndex
        guard let questionMark = bytes[..<fragmentStart].firstIndex(of: ASCII.questionMark) else {
            return nil
        }

        let queryStart = bytes.index(after: questionMark)
        let queryRange = queryStart..<fragmentStart
        guard !queryRange.isEmpty,
              let inspection = inspectQuery(in: bytes, range: queryRange) else { return nil }

        let cleanedURLString = rebuildURLString(
            source,
            bytes: bytes,
            queryRange: queryRange,
            inspection: inspection
        )
        return URL(string: cleanedURLString, relativeTo: url.baseURL)
    }

    private func inspectQuery(in bytes: String.UTF8View, range: Range<String.Index>) -> QueryInspection? {
        var didRemoveParameters = false
        var preservedItemCount = 0
        var preservedItemByteCount = 0

        forEachQueryItem(in: bytes, range: range) { itemRange in
            if isTrackingParameter(in: bytes, itemRange: itemRange) {
                didRemoveParameters = true
            } else {
                preservedItemCount += 1
                preservedItemByteCount += bytes.distance(from: itemRange.lowerBound, to: itemRange.upperBound)
            }
        }

        guard didRemoveParameters else { return nil }
        return QueryInspection(
            preservedItemCount: preservedItemCount,
            preservedItemByteCount: preservedItemByteCount
        )
    }

    private func rebuildURLString(
        _ source: String,
        bytes: String.UTF8View,
        queryRange: Range<String.Index>,
        inspection: QueryInspection
    ) -> String {
        let questionMark = bytes.index(before: queryRange.lowerBound)
        let fragmentStart = queryRange.upperBound
        let prefixByteCount = bytes.distance(from: bytes.startIndex, to: questionMark)
        let fragmentByteCount = bytes.distance(from: fragmentStart, to: bytes.endIndex)
        let separatorByteCount = max(inspection.preservedItemCount - 1, 0)
        let queryByteCount = inspection.preservedItemCount > 0
            ? 1 + inspection.preservedItemByteCount + separatorByteCount
            : 0

        var result = String()
        result.reserveCapacity(prefixByteCount + queryByteCount + fragmentByteCount)
        result.append(contentsOf: source[..<questionMark])

        if inspection.preservedItemCount > 0 {
            result.append("?")
            var didAppendItem = false

            forEachQueryItem(in: bytes, range: queryRange) { itemRange in
                guard !isTrackingParameter(in: bytes, itemRange: itemRange) else {
                    return
                }

                if didAppendItem {
                    result.append("&")
                }
                result.append(contentsOf: source[itemRange])
                didAppendItem = true
            }
        }

        result.append(contentsOf: source[fragmentStart...])
        return result
    }

    private func forEachQueryItem(
        in bytes: String.UTF8View,
        range: Range<String.Index>,
        perform action: (Range<String.Index>) -> Void
    ) {
        var itemStart = range.lowerBound
        var index = range.lowerBound

        while index != range.upperBound {
            if bytes[index] == ASCII.ampersand {
                action(itemStart..<index)
                itemStart = bytes.index(after: index)
            }
            index = bytes.index(after: index)
        }

        action(itemStart..<range.upperBound)
    }

    private func isTrackingParameter(
        in bytes: String.UTF8View,
        itemRange: Range<String.Index>
    ) -> Bool {
        let nameEnd = bytes[itemRange].firstIndex(of: ASCII.equalsSign) ?? itemRange.upperBound
        let name = bytes[itemRange.lowerBound..<nameEnd]
        return parameterNames.contains { name.elementsEqual($0.utf8) }
    }
}
