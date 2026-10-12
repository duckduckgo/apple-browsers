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
    private let isFastTrackingParameterFilterEnabled: () -> Bool

    public init(privacyManager: PrivacyConfigurationManaging,
                isFastTrackingParameterFilterEnabled: @escaping () -> Bool = { false }) {
        self.privacyManager = privacyManager
        self.isFastTrackingParameterFilterEnabled = isFastTrackingParameterFilterEnabled
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

        let trackingParams = Set(TrackingLinkSettings(fromConfig: privacyConfig).trackingParameters)

        if isFastTrackingParameterFilterEnabled() {
            guard let cleanURL = TrackingParameterFilter(trackingParameters: trackingParams).removingTrackingParameters(from: url) else {
                return url
            }
            urlParametersRemoved = true
            return cleanURL
        }

        guard var urlsComps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        guard let queryParams = urlsComps.percentEncodedQueryItems, queryParams.count > 0 else {
            return url
        }

        let preservedParams: [URLQueryItem] = queryParams.filter { param in
            if trackingParams.contains(param.name) {
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

/// Removes tracking parameters by scanning the URL's UTF-8 bytes in place.
///
/// `URLComponents` copies the whole query into separate strings, which takes seconds and hundreds of megabytes
/// on multi-megabyte URLs. This filter reads WebKit's URL string without copying it, and when it removes a
/// parameter, allocates the cleaned URL at its exact size. It removes the same items as the `URLComponents` path
/// (items split on every `&`, a name ends at the first `=`) and keeps the rest of the URL byte for byte. Unlike
/// `URLComponents`, it doesn't rewrite ports such as `:00080` or an empty `:`; WebKit's URLs never contain them.
private struct TrackingParameterFilter {

    private let trackingParameters: Set<String>
    private let nameLengths: Set<Int>

    init(trackingParameters: Set<String>) {
        self.trackingParameters = trackingParameters
        nameLengths = Set(trackingParameters.map(\.utf8.count))
    }

    /// Returns `url` without its tracking parameters, or `nil` when it has none or the cleaned URL isn't valid.
    func removingTrackingParameters(from url: URL) -> URL? {
        var string = url.relativeString
        return string.withUTF8 { bytes in
            let fragmentStart = Self.firstIndex(of: "#", in: bytes, from: 0, to: bytes.count)
            let questionMark = Self.firstIndex(of: "?", in: bytes, from: 0, to: fragmentStart)
            guard questionMark < fragmentStart else { return nil }

            var removesItems = false
            var keptItemsLength = 0
            forEachItem(in: bytes, from: questionMark + 1, to: fragmentStart) { item in
                if isTrackingItem(item, in: bytes) {
                    removesItems = true
                } else {
                    keptItemsLength += 1 + item.count // The item and the `?` or `&` before it.
                }
            }
            guard removesItems else { return nil }

            let cleanedLength = questionMark + keptItemsLength + (bytes.count - fragmentStart)
            // Only a relative URL made entirely of tracking parameters cleans to nothing. Like `URLComponents`,
            // return an empty URL.
            guard cleanedLength > 0 else { return URLComponents().url }

            let cleaned = String(unsafeUninitializedCapacity: cleanedLength) { output in
                var written = 0
                func append(_ range: Range<Int>) {
                    UnsafeMutableRawPointer(output.baseAddress! + written)
                        .copyMemory(from: bytes.baseAddress! + range.lowerBound, byteCount: range.count)
                    written += range.count
                }

                append(0..<questionMark)
                var hasKeptItems = false
                forEachItem(in: bytes, from: questionMark + 1, to: fragmentStart) { item in
                    guard !isTrackingItem(item, in: bytes) else { return }
                    output[written] = hasKeptItems ? UInt8(ascii: "&") : UInt8(ascii: "?")
                    written += 1
                    append(item)
                    hasKeptItems = true
                }
                append(fragmentStart..<bytes.count)
                return written
            }
            // `URL(string:)` rejects a few strings that CFURL accepts, such as a non-numeric port. `URLComponents`
            // can't parse those URLs either and leaves them unchanged, so `nil` keeps the same result.
            return URL(string: cleaned)
        }
    }

    private func isTrackingItem(_ item: Range<Int>, in bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        let nameEnd = Self.firstIndex(of: "=", in: bytes, from: item.lowerBound, to: item.upperBound)
        // Most names can't match on length alone, so skip creating a String for them.
        guard nameLengths.contains(nameEnd - item.lowerBound),
              let name = String(bytes: UnsafeBufferPointer(rebasing: bytes[item.lowerBound..<nameEnd]), encoding: .utf8) else {
            return false
        }
        return trackingParameters.contains(name)
    }

    private func forEachItem(in bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int, _ body: (Range<Int>) -> Void) {
        var itemStart = start
        while true {
            let itemEnd = Self.firstIndex(of: "&", in: bytes, from: itemStart, to: end)
            body(itemStart..<itemEnd)
            guard itemEnd < end else { return }
            itemStart = itemEnd + 1
        }
    }

    /// `memchr` scans much faster than a Swift loop, which matters for multi-megabyte URLs.
    private static func firstIndex(of character: Unicode.Scalar, in bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> Int {
        guard start < end, let base = bytes.baseAddress,
              let match = memchr(base + start, Int32(character.value), end - start) else { return end }
        return base.distance(to: match.assumingMemoryBound(to: UInt8.self))
    }
}
