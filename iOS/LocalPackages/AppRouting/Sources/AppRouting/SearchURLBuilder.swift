//
//  SearchURLBuilder.swift
//  DuckDuckGo
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

import Common
import Foundation
import FoundationExtensions

public struct SearchURLBuilder {

    private enum Param {
        static let search = "q"
        static let source = "t"
        static let atb = "atb"
        static let vertical = "ia"
        static let verticalRewrite = "iar"
        static let verticalMaps = "iaxm"
    }

    private enum ParamValue {
        static let phoneSource = "ddg_ios"
        static let iPadSource = "ddg_ios_tablet"
        static let majorVerticals: Set<String> = ["images", "videos", "news"]
    }

    private let searchBaseURL: URL
    private let isPad: Bool
    private let atbWithVariant: () -> String?

    public var source: String {
        isPad ? ParamValue.iPadSource : ParamValue.phoneSource
    }

    public init(
        searchBaseURL: URL,
        isPad: Bool,
        atbWithVariant: @escaping () -> String? = { nil }
    ) {
        self.searchBaseURL = searchBaseURL
        self.isPad = isPad
        self.atbWithVariant = atbWithVariant
    }

    // MARK: Search

    public func makeSearchURL(text: String) -> URL? {
        makeSearchURL(text: text, additionalParameters: [])
    }

    public func makeSearchURL(query: String, forceSearchQuery: Bool = false, queryContext: URL? = nil) -> URL? {
        if !forceSearchQuery, let url = URLInputClassifier.webUrl(from: query) {
            return url
        }

        var parameters = [String: String]()
        if let queryContext,
           let searchDomain = searchBaseURL.host,
           queryContext.isPart(ofDomain: searchDomain),
           queryContext.getParameter(named: Param.search) != nil,
           queryContext.getParameter(named: Param.verticalMaps) == nil,
           let vertical = queryContext.getParameter(named: Param.vertical),
           ParamValue.majorVerticals.contains(vertical) {

            parameters[Param.verticalRewrite] = vertical
        }

        return makeSearchURL(text: query, additionalParameters: parameters)
    }

    /**
     Generates a search url with the source (t) https://duck.co/help/privacy/t
     and cohort (atb) https://duck.co/help/privacy/atb
     */
    private func makeSearchURL<C: Collection>(text: String, additionalParameters: C) -> URL
    where C.Element == (key: String, value: String) {
        // encode spaces as "+"
        var queryItem = URLQueryItem(percentEncodingName: Param.search, value: text, withAllowedCharacters: .init(charactersIn: " "))
        queryItem.value = queryItem.value?.replacingOccurrences(of: " ", with: "+")

        let searchURL = URL(string: searchBaseURL.absoluteString.dropping(suffix: "/") + "/")!
            .appending(percentEncodedQueryItem: queryItem)
            .appendingParameters(additionalParameters)
        return applyingStatsParams(to: searchURL)
    }

    public func applyingStatsParams(to url: URL) -> URL {
        var searchURL = url.removingParameters(named: [Param.source, Param.atb])
            .appendingParameter(name: Param.source,
                                value: source)

        if let atbWithVariant = atbWithVariant() {
            searchURL = searchURL.appendingParameter(name: Param.atb, value: atbWithVariant)
        }
        return searchURL
    }

    public func hasCorrectMobileStatsParams(url: URL) -> Bool {
        guard let source = url.getParameter(named: Param.source),
              source == self.source
        else { return false }
        if let atbWithVariant = atbWithVariant() {
            return atbWithVariant == url.getParameter(named: Param.atb)
        }
        return true
    }
}
