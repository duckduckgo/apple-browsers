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

    public static let defaultSearchBaseURL: URL = SearchURLDefaults.searchBaseURL(environment: ProcessInfo.processInfo.environment)

    private enum Parameter {
        static let attribution = "atb"
        static let query = "q"
        static let source = "t"
        static let vertical = "ia"
        static let verticalMaps = "iaxm"
        static let verticalRewrite = "iar"
    }

    private enum ParameterValue {
        static let phoneSource = "ddg_ios"
        static let tabletSource = "ddg_ios_tablet"
        static let majorVerticals: Set<String> = ["images", "videos", "news"]
    }

    private let searchBaseURL: URL
    private let isPad: Bool
    private let atbProvider: () -> String?

    public var source: String {
        isPad ? ParameterValue.tabletSource : ParameterValue.phoneSource
    }

    public init(
        searchBaseURL: URL = SearchURLBuilder.defaultSearchBaseURL,
        isPad: Bool,
        atbProvider: @escaping () -> String? = { nil }
    ) {
        self.searchBaseURL = searchBaseURL
        self.isPad = isPad
        self.atbProvider = atbProvider
    }

    public func makeSearchURL(query: String, forceSearchQuery: Bool = false, queryContext: URL? = nil) -> URL? {
        if !forceSearchQuery, let url = URLInputClassifier.webURL(from: query) {
            return url
        }

        var parameters = [String: String]()
        if let vertical = verticalRewrite(from: queryContext) {
            parameters[Parameter.verticalRewrite] = vertical
        }

        return makeSearchURL(text: query, additionalParameters: parameters)
    }

    public func applyingSourceAndAttributionParameters(to url: URL) -> URL {
        var searchURL = url.removingParameters(named: [Parameter.source, Parameter.attribution])
            .appendingParameter(name: Parameter.source, value: source)

        if let attribution = atbProvider() {
            searchURL = searchURL.appendingParameter(name: Parameter.attribution, value: attribution)
        }
        return searchURL
    }

    public func hasExpectedSourceAndAttributionParameters(in url: URL) -> Bool {
        guard url.getParameter(named: Parameter.source) == source else { return false }
        if let attribution = atbProvider() {
            return url.getParameter(named: Parameter.attribution) == attribution
        }
        return true
    }

    private func verticalRewrite(from queryContext: URL?) -> String? {
        guard let queryContext,
              isSearchURL(queryContext),
              queryContext.getParameter(named: Parameter.verticalMaps) == nil,
              let vertical = queryContext.getParameter(named: Parameter.vertical),
              ParameterValue.majorVerticals.contains(vertical) else {
            return nil
        }
        return vertical
    }

    private func isSearchURL(_ url: URL) -> Bool {
        guard let searchDomain = searchBaseURL.host else { return false }
        return url.isPart(ofDomain: searchDomain) && url.getParameter(named: Parameter.query) != nil
    }

    private func makeSearchURL<C: Collection>(text: String, additionalParameters: C) -> URL
    where C.Element == (key: String, value: String) {
        var queryItem = URLQueryItem(percentEncodingName: Parameter.query, value: text, withAllowedCharacters: .init(charactersIn: " "))
        queryItem.value = queryItem.value?.replacingOccurrences(of: " ", with: "+")

        let baseURLString = searchBaseURL.absoluteString.dropping(suffix: "/") + "/"
        let normalizedBaseURL = URL(string: baseURLString)!
        let searchURL = normalizedBaseURL
            .appending(percentEncodedQueryItem: queryItem)
            .appendingParameters(additionalParameters)
        return applyingSourceAndAttributionParameters(to: searchURL)
    }
}

enum SearchURLDefaults {

    static func searchBaseURL(environment: [String: String]) -> URL {
        let baseURLString = environment["BASE_URL", default: "https://duckduckgo.com"]
        return URL(string: baseURLString)!
    }
}
