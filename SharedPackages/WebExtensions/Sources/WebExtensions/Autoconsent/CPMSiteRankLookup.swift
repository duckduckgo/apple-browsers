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
import URLPredictor

/// Coarse popularity bucket of a site, sent as the `siteRank` parameter of the CPM summary pixel.
public enum CPMSiteRank: String, CaseIterable, Sendable {
    /// The registrable domain of the site is in the bundled top 10k list.
    case top10k
    case other
}

/// Finds the `CPMSiteRank` of a top-level URL on the device, from the bundled Bloom filter of top sites.
/// The URL and its domain are only used for the lookup, and are never sent.
///
/// It gives the same result as `cpm-site-rank.js` in the DDG extension, which the embedded web extension uses:
/// - `cpm-top-sites-bloom.json` is a copy of `shared/data/bundled/cpm-top-sites-bloom.json` from duckduckgo-privacy-extension.
///   Update both files together.
/// - The registrable domain comes from the ICANN section of the Public Suffix List only, as in `tldts`.
public final class CPMSiteRankLookup: Sendable {

    struct LookupData: Sendable {
        let filter: JSBloomFilter
        let publicSuffixList: ICANNPublicSuffixList
    }

    /// Loaded on the first lookup, once for all instances that use the bundled data.
    private static let bundledData: LookupData? = {
        guard let filter = loadBundledFilter(), let publicSuffixList = loadPublicSuffixList() else { return nil }
        return LookupData(filter: filter, publicSuffixList: publicSuffixList)
    }()

    private let data: @Sendable () -> LookupData?

    /// A lookup with the bundled data. Creating it is cheap: the data is loaded on the first lookup.
    public convenience init() {
        self.init { Self.bundledData }
    }

    init(data: @escaping @Sendable () -> LookupData?) {
        self.data = data
    }

    /// - Returns: the bucket of the URL, or `nil` if the bundled data could not be loaded.
    public func siteRank(for url: URL?) -> CPMSiteRank? {
        guard let data = data() else { return nil }
        guard let host = url?.host, let domain = data.publicSuffixList.registrableDomain(of: host) else {
            return .other
        }
        return data.filter.contains(domain) ? .top10k : .other
    }

    private struct BloomFilterData: Decodable {
        let totalEntries: Int
        /// base64 encoded filter bits
        let data: String
    }

    static func loadBundledFilter() -> JSBloomFilter? {
        guard let url = Bundle.module.url(forResource: "cpm-top-sites-bloom", withExtension: "json"),
              let json = try? Data(contentsOf: url),
              let filterData = try? JSONDecoder().decode(BloomFilterData.self, from: json),
              let bits = Data(base64Encoded: filterData.data),
              let filter = JSBloomFilter(totalEntries: filterData.totalEntries, bits: [UInt8](bits)) else {
            Logger.webExtensions.error("[CPM] Cannot load the top sites filter, the summary pixel has no siteRank")
            assertionFailure("Cannot load cpm-top-sites-bloom.json")
            return nil
        }
        return filter
    }

    static func loadPublicSuffixList() -> ICANNPublicSuffixList? {
        guard let pslData = try? Classifier.getPSLData() else {
            Logger.webExtensions.error("[CPM] Cannot load the Public Suffix List, the summary pixel has no siteRank")
            assertionFailure("Cannot load the Public Suffix List")
            return nil
        }
        return ICANNPublicSuffixList(pslData: pslData)
    }
}
