//
//  CPMSiteRankLookup.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import os.log

/// Coarse popularity bucket of a site, sent as the `siteRank` parameter of the CPM summary pixel.
public enum CPMSiteRank: String, Sendable {
    /// The registrable domain of the site is in the bundled top 10k list.
    case top10k
    case other
}

/// Port of the embedded extension's lookup (`cpm-site-rank.js` and `shared-utils/domain-hashes.js` in
/// duckduckgo-privacy-extension), which must give the same results. `site-buckets.json` is a copy of the extension's
/// list.
public struct CPMSiteRankLookup: Sendable {

    /// Sorted 32-bit FNV-1a hashes of the top sites' registrable domains.
    struct LookupData: Sendable {
        let hashes: [UInt32]

        func contains(_ hash: UInt32) -> Bool {
            var low = 0
            var high = hashes.count - 1
            while low <= high {
                let mid = (low + high) / 2
                if hashes[mid] < hash {
                    low = mid + 1
                } else if hashes[mid] > hash {
                    high = mid - 1
                } else {
                    return true
                }
            }
            return false
        }
    }

    /// Loaded on the first lookup, once for all instances that use the bundled data.
    private static let bundledData: LookupData? = loadBundledData()

    private let data: @Sendable () -> LookupData?

    /// A lookup with the bundled data. Creating it is cheap: the data is loaded on the first lookup.
    public init() {
        self.init { Self.bundledData }
    }

    init(data: @escaping @Sendable () -> LookupData?) {
        self.data = data
    }

    /// Checks every suffix of the hostname with at least two labels, so `www.example.co.uk` matches `example.co.uk`.
    /// - Returns: the bucket of the URL, or `nil` if the bundled data could not be loaded.
    public func siteRank(for url: URL?) -> CPMSiteRank? {
        guard let data = data() else { return nil }
        guard var host = url?.host?.lowercased() else { return .other }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        let bytes = Array(host.utf8)
        let dot = UInt8(ascii: ".")
        guard let last = bytes.lastIndex(of: dot), last > 0 else { return .other }
        var start = bytes[..<last].lastIndex(of: dot) ?? -1
        while true {
            if data.contains(Self.fnv1a32(bytes[(start + 1)...])) {
                return .top10k
            }
            if start <= 0 {
                return .other
            }
            start = bytes[..<start].lastIndex(of: dot) ?? -1
        }
    }

    /// Hostnames are ASCII (IDNs are punycode), so hashing UTF-8 bytes equals hashing UTF-16 code units in the extension.
    static func fnv1a32<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        var hash: UInt32 = 0x811c9dc5
        for byte in bytes {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        return hash
    }

    /// Decodes base64 LEB128 varints of the gaps between consecutive hashes.
    /// - Returns: `nil` if the data is empty or malformed.
    static func decode(count: Int, base64: String) -> [UInt32]? {
        guard count > 0, let data = Data(base64Encoded: base64) else { return nil }
        let bytes = [UInt8](data)
        var hashes = [UInt32]()
        hashes.reserveCapacity(count)
        var position = 0
        var previous: UInt64 = 0
        for _ in 0..<count {
            var gap: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard position < bytes.count, shift <= 28 else { return nil }
                let byte = bytes[position]
                position += 1
                gap |= UInt64(byte & 0x7f) << shift
                shift += 7
                if byte & 0x80 == 0 { break }
            }
            previous += gap
            guard previous <= UInt64(UInt32.max) else { return nil }
            hashes.append(UInt32(previous))
        }
        guard position == bytes.count else { return nil }
        return hashes
    }

    struct BundledFile: Decodable {
        let count: Int
        let data: String
    }

    static func loadBundledFile() -> BundledFile? {
        guard let url = Bundle.module.url(forResource: "site-buckets", withExtension: "json"),
              let json = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BundledFile.self, from: json)
    }

    static func loadBundledData() -> LookupData? {
        guard let file = loadBundledFile(), let hashes = decode(count: file.count, base64: file.data) else {
            Logger.webExtensions.error("[CPM] Cannot load the top sites data, the summary pixel has no siteRank")
            assertionFailure("Cannot load site-buckets.json")
            return nil
        }
        return LookupData(hashes: hashes)
    }
}
