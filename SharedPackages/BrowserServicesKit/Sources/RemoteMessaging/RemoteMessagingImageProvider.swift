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

fileprivate extension URLSession {
    static let remoteMessageImageSession: URLSession = {
        let cacheDirectory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("RemoteMessageImages")
        let cache = URLCache(memoryCapacity: 1 * 1024 * 1024,
                             diskCapacity: 5 * 1024 * 1024,
                             directory: cacheDirectory)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        return URLSession(configuration: config)
    }()
}

public actor RemoteMessagingImageLoader: RemoteMessagingImageLoading {
    private let dataProvider: RemoteMessagingImageDataProviding
    private var pendingLoads: [URL: Task<RemoteMessagingImage, Error>] = [:]

    init(dataProvider: RemoteMessagingImageDataProviding) {
        self.dataProvider = dataProvider
    }

    nonisolated func prefetch(_ urls: [URL]) {
        for url in urls {
            Task { [weak self] in _ = try? await self?.loadImage(from: url) }
        }
    }

    func loadImage(from url: URL) async throws -> RemoteMessagingImage {
        if let pending = pendingLoads[url] {
            return try await pending.value
        }

        let task = Task {
            defer { pendingLoads[url] = nil }

            let (data, response) = try await dataProvider.data(from: url)
            try validateResponse(response)

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
