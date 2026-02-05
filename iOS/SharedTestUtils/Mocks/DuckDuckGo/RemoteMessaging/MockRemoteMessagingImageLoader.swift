//
//  MockRemoteMessagingImageLoader.swift
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

import Foundation
import RemoteMessaging
import UIKit

public final class MockRemoteMessagingImageLoader: RemoteMessagingImageLoading {

    // MARK: - Cached Image
    public var cachedImageToReturn: UIImage?
    public var cachedImageCalledWithUrl: URL?

    // MARK: - Load Image
    public var imageToReturn: UIImage?
    public var errorToThrow: Error?
    public var loadImageCalledWithUrl: URL?
    public var loadImageCallCount = 0

    // MARK: - Prefetch
    public var prefetchedURLs: [URL] = []

    public init() {}

    public func prefetch(_ urls: [URL]) {
        prefetchedURLs.append(contentsOf: urls)
    }

    public func cachedImage(for url: URL) -> RemoteMessagingImage? {
        cachedImageCalledWithUrl = url
        return cachedImageToReturn
    }

    public func loadImage(from url: URL) async throws -> RemoteMessagingImage {
        loadImageCallCount += 1
        loadImageCalledWithUrl = url
        if let error = errorToThrow {
            throw error
        }
        guard let image = imageToReturn else {
            throw RemoteMessagingImageLoadingError.invalidImageData
        }
        return image
    }
}
