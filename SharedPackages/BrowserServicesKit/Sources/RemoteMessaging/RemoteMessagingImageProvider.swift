//
//  RemoteMessagingImageProvider.swift
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

public protocol RemoteMessagingImageDataProviding {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: RemoteMessagingImageDataProviding {}

public actor RemoteMessagingImageLoader: RemoteMessagingImageLoading {

    /// The default URLCache for Remote Messaging image loading.
    /// Uses a small cache (1MB memory, 5MB disk) dedicated to RMF images.
    public static let defaultCache: URLCache = {
        let cacheDirectory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("RemoteMessageImages")
        return URLCache(memoryCapacity: 1 * 1024 * 1024,
                             diskCapacity: 5 * 1024 * 1024,
                             directory: cacheDirectory)
    }()

    /// The default data provider for Remote Messaging image loading.
    public static let defaultDataProvider: RemoteMessagingImageDataProviding = {
        let config = URLSessionConfiguration.default
        config.urlCache = defaultCache
        return URLSession(configuration: config)
    }()

    private let dataProvider: RemoteMessagingImageDataProviding
    private let cache: URLCache?
    private var pendingLoads: [URL: Task<RemoteMessagingImage, Error>] = [:]

    public init(dataProvider: RemoteMessagingImageDataProviding, cache: URLCache? = nil) {
        self.dataProvider = dataProvider
        self.cache = cache
    }

    public nonisolated func prefetch(_ urls: [URL]) {
        for url in urls {
            Task { [weak self] in _ = try? await self?.loadImage(from: url) }
        }
    }

    public nonisolated func cachedImage(for url: URL) -> RemoteMessagingImage? {
        let request = URLRequest(url: url)
        guard let cached = cache?.cachedResponse(for: request),
              let image = RemoteMessagingImage(data: cached.data) else {
            return nil
        }
        return image
    }

    public func loadImage(from url: URL) async throws -> RemoteMessagingImage {
        if let pending = pendingLoads[url] {
            return try await pending.value
        }

        let task = Task { [cache] in
            defer { pendingLoads[url] = nil }

            let request = URLRequest(url: url)

            if let cached = cache?.cachedResponse(for: request),
               let image = RemoteMessagingImage(data: cached.data) {
                return image
            }

            let (data, response) = try await dataProvider.data(from: url)
            try validateResponse(response)

            if let cache {
                let cachedResponse = CachedURLResponse(response: response, data: data, storagePolicy: .allowed)
                cache.storeCachedResponse(cachedResponse, for: request)
            }

            guard let image = RemoteMessagingImage(data: data) else {
                throw RemoteMessagingImageLoadingError.invalidImageData
            }
            return image
        }

        pendingLoads[url] = task
        return try await task.value
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              http.mimeType?.hasPrefix("image/") == true else {
            throw RemoteMessagingImageLoadingError.invalidResponse
        }
    }
}
