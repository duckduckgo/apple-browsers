//
//  BrokerJSONService.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Subscription
import ZIPFoundation

public protocol BrokerJSONETagStoring {
    func loadMainConfigETag() -> String?
    func saveMainConfigETag(_ etag: String)
    func loadETag(forBrokerNamed name: String) throws -> String?
}

public protocol BrokerJSONDownloading {
    func downloadBrokerJSONs() async throws
    func processBrokerJSONs()
}

public protocol BrokerJSONServiceProvider: AnyObject {

}

public final class BrokerJSONService: BrokerJSONServiceProvider, BrokerJSONETagStoring, BrokerJSONDownloading {
    enum Error: Swift.Error {
        case missingAccessToken
        case serverError
        case clientError
    }

    enum Endpoint {
        private static let baseURL = URL(string: "https://dbp.duckduckgo.com/dbp/remote/v0")!
        static var mainConfigURL: URL {
            baseURL.appending("main_config.json")
        }
        static var allBrokersURL: URL {
            if #available(macOS 13.0, iOS 16.0, *) {
                return baseURL.appending(queryItems: [
                    .init(name: "name", value: "all.zip"),
                    .init(name: "type", value: "spec")
                ])
            } else {
                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
                components.queryItems = [
                    .init(name: "name", value: "all.zip"),
                    .init(name: "type", value: "spec")
                ]
                return components.url!
            }
        }

        case mainConfig
        case allBrokers

        static func url(for endpoint: Endpoint) -> URL {
            switch endpoint {
            case .mainConfig: return Endpoint.mainConfigURL
            case .allBrokers: return Endpoint.allBrokersURL
            }
        }

        static func request(for endpoint: Endpoint, accessToken: String) -> URLRequest {
            var request = URLRequest(url: url(for: endpoint))
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            return request
        }
    }

    private static let mainConfigETagKey = "brokerJSONMainConfigETag"

    private let defaults: UserDefaults
    private let vault: any DataBrokerProtectionSecureVault
    private let accountManager: AccountManager

    init(defaults: UserDefaults, vault: any DataBrokerProtectionSecureVault, accountManager: AccountManager) {
        self.defaults = defaults
        self.vault = vault
        self.accountManager = accountManager
    }

    public func loadMainConfigETag() -> String? {
        defaults.string(forKey: Self.mainConfigETagKey)
    }

    public func saveMainConfigETag(_ etag: String) {
        defaults.set(etag, forKey: Self.mainConfigETagKey)
    }

    public func loadETag(forBrokerNamed name: String) throws -> String? {
        guard let broker = try vault.fetchBroker(with: name) else { return nil }
        return broker.eTag
    }

    public func downloadBrokerJSONs() async throws {
        guard let accessToken = accountManager.accessToken else {
            throw Error.missingAccessToken
        }

        let request = Endpoint.request(for: .allBrokers, accessToken: accessToken)
        let temporaryURL: URL

        if #available(macOS 12.0, *) {
            let (url, response) = try await URLSession.shared.download(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw Error.serverError
            }
            temporaryURL = url
        } else {
            temporaryURL = try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.downloadTask(with: request) { url, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                        continuation.resume(throwing: Error.serverError)
                        return
                    }

                    guard let url else {
                        continuation.resume(throwing: Error.clientError)
                        return
                    }

                    continuation.resume(returning: url)
                }
                task.resume()
            }
        }

        let fileManager = FileManager.default
        let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.unzipItem(at: temporaryURL, to: destinationURL)
    }

    public func processBrokerJSONs() {
        
    }
}
