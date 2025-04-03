//
//  SuggestionLoading.swift
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

public protocol SuggestionLoading: AnyObject {

    func getSuggestions(query: String,
                        usingDataSource dataSource: SuggestionLoadingDataSource,
                        completion: @escaping (SuggestionResult?, Error?) -> Void)

}

public class SuggestionLoader: SuggestionLoading {

    static let remoteSuggestionsUrl = URL(string: "https://duckduckgo.com/ac/")!
    static let searchParameter = "q"
    static let isNavParameter = "is_nav"

    public enum SuggestionLoaderError: Error {
        case noDataSource
        case parsingFailed
        case failedToProcessData
    }

    private let urlFactory: (String) -> URL?
    private let isUrlIgnored: (URL) -> Bool

    public init(urlFactory: @escaping (String) -> URL?, isUrlIgnored: @escaping (URL) -> Bool) {
        self.urlFactory = urlFactory
        self.isUrlIgnored = isUrlIgnored
    }

    public func getSuggestions(query: String,
                               usingDataSource dataSource: SuggestionLoadingDataSource,
                               completion: @escaping (SuggestionResult?, Error?) -> Void) {

        if query.isEmpty {
            completion(.empty, nil)
            return
        }

        // 1) Getting all necessary data
        let bookmarks = dataSource.bookmarks(for: self)
        let history = dataSource.history(for: self)
        let internalPages = dataSource.internalPages(for: self)
        let openTabs = dataSource.openTabs(for: self)
        var apiResult: APIResult?
        var apiError: Error?

        let url = urlFactory(query)

        let group = DispatchGroup()
        if url == nil || url!.isRoot && url!.path.last != "/" {
            group.enter()
            dataSource.suggestionLoading(self,
                                         suggestionDataFromUrl: Self.remoteSuggestionsUrl,
                                         withParameters: [ Self.searchParameter: query,
                                                           Self.isNavParameter: "1", // Enables is_nav in the JSON response
                                                         ]) { data, error in
                defer { group.leave() }
                guard let data = data else {
                    apiError = error
                    return
                }
                guard let result = try? JSONDecoder().decode(APIResult.self, from: data) else {
                    apiError = SuggestionLoaderError.parsingFailed
                    return
                }
                apiResult = result
            }
        } else {
            apiResult = nil
        }

        // 2) Processing it
        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self else { return }
            let processor = SuggestionProcessing(platform: dataSource.platform, isUrlIgnored: isUrlIgnored)
            let result = processor.result(for: query,
                                          from: history,
                                          bookmarks: bookmarks,
                                          internalPages: internalPages,
                                          openTabs: openTabs,
                                          apiResult: apiResult)
            DispatchQueue.main.async {
                if let result = result {
                    completion(result, apiError)
                } else {
                    completion(nil, SuggestionLoaderError.failedToProcessData)
                }
            }
        }
    }
}

public protocol SuggestionLoadingDataSource: AnyObject {

    var platform: Platform { get }

    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Bookmark]

    func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion]

    func internalPages(for suggestionLoading: SuggestionLoading) -> [InternalPage]

    func openTabs(for suggestionLoading: SuggestionLoading) -> [BrowserTab]

    func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                           suggestionDataFromUrl url: URL,
                           withParameters parameters: [String: String],
                           completion: @escaping (Data?, Error?) -> Void)

}
