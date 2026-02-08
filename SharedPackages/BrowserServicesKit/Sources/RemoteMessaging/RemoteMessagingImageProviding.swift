//
//  RemoteMessagingImageProviding.swift
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

/// A cross-platform image type alias.
/// Resolves to `UIImage` on iOS and `NSImage` on macOS.
#if canImport(UIKit)
import UIKit
public typealias RemoteMessagingImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias RemoteMessagingImage = NSImage
#endif

/// Provides image loading and prefetching for Remote Messaging Framework.
public protocol RemoteMessagingImageLoading {
    /// Prefetches images in the background so they're ready when needed.
    /// Failures are silently ignored.
    /// - Parameter urls: The list of URLs to prefetch.
    func prefetch(_ urls: [URL])

    /// Synchronously checks if an image is already cached.
    /// - Parameter url: The URL of the image to check.
    /// - Returns: The cached image if available, nil otherwise.
    func cachedImage(for url: URL) -> RemoteMessagingImage?

    /// Loads an image from the given URL.
    /// - Parameter url: The URL of the image to load.
    /// - Returns: The loaded image.
    /// - Throws: `RemoteMessageImageLoadingError` if the response is invalid or data can't be decoded.
    func loadImage(from url: URL) async throws -> RemoteMessagingImage
}

/// Errors that can occur during remote message image loading.
public enum RemoteMessagingImageLoadingError: Error {
    /// The server response was not a successful HTTP status or had an invalid content type.
    case invalidResponse
    /// The downloaded data could not be decoded as an image.
    case invalidImageData
}
