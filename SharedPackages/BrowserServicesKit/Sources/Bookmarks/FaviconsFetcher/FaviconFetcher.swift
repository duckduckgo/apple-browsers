//
//  FaviconFetcher.swift
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
import LinkPresentation
import UniformTypeIdentifiers

public final class FaviconFetcher: NSObject, FaviconFetching {

    public override init() {}

    public func fetchFavicon(for url: URL) async throws -> (Data?, URL?) {
        /// DuckDuckGo Privacy Browser uses built-in functionality from Apple to fetch the highest quality favicons for bookmarks and favorites.
        /// This functionality uses a user agent that is different from other network requests made by the apps in order to find the best favicon available.
        let metadataFetcher = LPMetadataProvider()

        // Allow LinkPresentation to fail so that we can fall back to fetching hardcoded paths
        let metadata: LPLinkMetadata? = await { @MainActor in
            if #available(iOS 15.0, macOS 12.0, *) {
                var request = URLRequest(url: url)
                request.attribution = .user
                return try? await metadataFetcher.startFetchingMetadata(for: request)
            } else {
                return try? await metadataFetcher.startFetchingMetadata(for: url)
            }
        }()

        // If LinkPresentation returned metadata, try retrieving favicon data
        let imageData: Data? = await withCheckedContinuation { continuation in
            guard let iconProvider = metadata?.iconProvider else {
                continuation.resume(returning: nil)
                return
            }
            iconProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { data, _ in
                guard let data = data as? Data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }

        guard let imageData else {
            return try await lookUpHardcodedFaviconPath(for: url)
        }

        return (imageData, nil)
    }

    private func lookUpHardcodedFaviconPath(for url: URL) async throws -> (Data?, URL?) {
        guard let host = url.host else {
            return (nil, nil)
        }

        var faviconImageData: Data?
        var faviconURL: URL?

        for path in Const.hardcodedFaviconPaths {
            let potentialFaviconURL = URL(string: "\(URL.NavigationalScheme.https.separated())\(host)/\(path)")
            guard let potentialFaviconURL else {
                continue
            }
            let (data, response) = try await faviconsURLSession.data(from: potentialFaviconURL)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                faviconImageData = data
                faviconURL = potentialFaviconURL
                break
            }
        }

        return (faviconImageData, faviconURL)
    }

    enum Const {
        static let hardcodedFaviconPaths = ["apple-touch-icon.png", "favicon.ico"]
    }

    private(set) lazy var faviconsURLSession = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
}

extension FaviconFetcher: URLSessionTaskDelegate {

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        return request
    }
}
