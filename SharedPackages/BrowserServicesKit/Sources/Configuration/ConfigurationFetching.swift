//
//  ConfigurationFetching.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import FoundationExtensions
import Networking

public protocol ConfigurationFetching {

    @discardableResult
    func fetch(_ configuration: Configuration, isDebug: Bool) async throws -> ConfigurationFetchResult

    /// - Returns: the configurations whose data actually changed. A configuration answered with
    /// HTTP 304 is omitted, so callers can skip re-applying data they already hold.
    @discardableResult
    func fetch(all configurations: [Configuration]) async throws -> Set<Configuration>

}

public enum ConfigurationFetchResult: Equatable, Sendable {
    case updated
    case notModified
}

private typealias ConfigurationResponse = (etag: String, data: Data?)

public final class ConfigurationFetcher: ConfigurationFetching {

    public enum Error: Swift.Error {

        case apiRequest(APIRequest.Error)
        case invalidPayload

    }

    private let store: ConfigurationStoring
    private let validator: ConfigurationValidating
    private let configurationURLProvider: ConfigurationURLProviding
    private let sessionProvider: () -> URLSession

    public convenience init(store: ConfigurationStoring,
                            urlSession: @autoclosure @escaping () -> URLSession = URLSession.shared,
                            configurationURLProvider: ConfigurationURLProviding,
                            eventMapping: EventMapping<ConfigurationDebugEvents>? = nil) {
        let validator = ConfigurationValidator(eventMapping: eventMapping)
        self.init(store: store, validator: validator, sessionProvider: urlSession, configurationURLProvider: configurationURLProvider)
    }

    init(store: ConfigurationStoring,
         validator: ConfigurationValidating,
         sessionProvider: @escaping () -> URLSession,
         configurationURLProvider: ConfigurationURLProviding) {
        self.store = store
        self.validator = validator
        self.sessionProvider = sessionProvider
        self.configurationURLProvider = configurationURLProvider
    }

    /**
    Downloads and stores a single configuration specified by the Configuration enum provided in the configuration parameter.
    This function throws an error if the configuration fails to fetch or validate.

    - Parameters:
      - configuration: A Configuration enum that needs to be downloaded and stored.

    - Returns:
      Whether the configuration was updated or the server reported that it was not modified.

    - Throws:
      An error of type Error is thrown if the configuration fails to fetch or validate.
    */
    @discardableResult
    public func fetch(_ configuration: Configuration, isDebug: Bool = false) async throws -> ConfigurationFetchResult {
        let requirements: APIResponseRequirements = isDebug
            ? .requireNonEmptyData.union(.allowHTTPNotModified)
            : .default.union(.allowHTTPNotModified)
        let fetchResult = try await fetch(from: configurationURLProvider.url(for: configuration), withEtag: etag(for: configuration), requirements: requirements)
        guard let data = fetchResult.data else { return .notModified }

        try validator.validate(data, for: configuration)
        try store(fetchResult, for: configuration)
        return .updated
    }

    /**
     Downloads and stores the configurations provided in parallel using a throwing task group.
     This function throws an error if any of the configurations fail to fetch or validate.

     - Parameters:
       - configurations: An array of `Configuration` enums that need to be downloaded and stored.

     - Returns:
       The configurations whose data actually changed. Requests are made with `.all` requirements, which
       permit HTTP 304, so an unchanged configuration completes successfully with no data. Those are
       excluded from the result, letting callers skip re-applying data that is already current.

     - Throws:
       An error of type `Error` is thrown if any configuration fails to fetch or validate.

     - Important:
       This function uses a throwing task group to download and validate the configurations in parallel.
       If any of the tasks in the group throws an error, the group is cancelled and the function rethrows the error.
       So, if any configuration fails to fetch or validate, none of the configurations will be stored.
    */
    @discardableResult
    public func fetch(all configurations: [Configuration]) async throws -> Set<Configuration> {
        try await withThrowingTaskGroup(of: (Configuration, ConfigurationResponse).self) { group in
            configurations.forEach { configuration in
                group.addTask {
                    let fetchResult = try await self.fetch(from: self.configurationURLProvider.url(for: configuration), withEtag: self.etag(for: configuration), requirements: .all)
                    if let data = fetchResult.data {
                        try self.validator.validate(data, for: configuration)
                    }
                    return (configuration, fetchResult)
                }
            }

            var fetchResults = [(Configuration, ConfigurationResponse)]()
            for try await result in group {
                fetchResults.append(result)
            }

            var updatedConfigurations = Set<Configuration>()
            for (configuration, fetchResult) in fetchResults where fetchResult.data != nil {
                try self.store(fetchResult, for: configuration)
                updatedConfigurations.insert(configuration)
            }
            return updatedConfigurations
        }
    }

    private func etag(for configuration: Configuration) -> String? {
        if let etag = store.loadEtag(for: configuration), store.loadData(for: configuration) != nil {
            return etag
        }
        return store.loadEmbeddedEtag(for: configuration)
    }

    private func fetch(from url: URL, withEtag etag: String?, requirements: APIResponseRequirements) async throws -> ConfigurationResponse {
        let configuration = APIRequest.Configuration(url: url,
                                                     headers: APIRequest.Headers(etag: etag),
                                                     cachePolicy: .reloadIgnoringLocalCacheData)
        let request = APIRequest(configuration: configuration, requirements: requirements, urlSession: sessionProvider())
        let (data, response) = try await request.fetch()
        return (response.etag ?? "", data)
    }

    private func store(_ result: ConfigurationResponse, for configuration: Configuration) throws {
        if let data = result.data {
            try store.saveData(data, for: configuration)
            try store.saveEtag(result.etag, for: configuration)
        }
    }

}
