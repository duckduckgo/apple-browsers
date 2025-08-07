//
//  DaxEasterEggImageManager.swift
//  DuckDuckGo
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
import UIKit
import Kingfisher

/// Protocol for handling Dax Easter Egg image loading and caching operations.
///
/// This manager provides optimized caching for dynamic DuckDuckGo images with proper
/// storage limits and cleanup to prevent excessive disk usage.
public protocol DaxEasterEggImageManaging: AnyObject {
    /// Retrieves the best available image for full-screen presentation.
    /// Checks memory cache first, then disk cache, falls back to current display image.
    ///
    /// - Parameters:
    ///   - url: The logo URL
    ///   - fallbackImage: Image to use if high-res version unavailable
    ///   - completion: Called with the best available image
    func getBestImageForFullScreen(url: URL, fallbackImage: UIImage?, completion: @escaping (UIImage?) -> Void)
    
    /// Checks if a high-resolution image is immediately available in memory cache
    ///
    /// - Parameter url: The logo URL to check
    /// - Returns: High-res image if cached in memory, nil otherwise
    func getHighResImageFromMemoryCache(for url: URL) -> UIImage?
    
    /// Preloads a full-resolution image in the background for smoother animations.
    /// Uses dedicated Dax Easter Egg cache with size limits and expiry.
    ///
    /// - Parameter url: The image URL to preload
    func preloadFullResolutionImage(for url: URL)
    
    /// Clears expired images from disk cache to prevent storage bloat
    func clearExpiredImages()
}

/// Manager that handles loading and caching of dynamic Dax Easter Egg images.
///
/// This class provides optimized caching specifically for DuckDuckGo dynamic images
/// with proper storage limits, expiry policies, and cleanup to prevent storage bloat.
/// Uses a dedicated cache separate from other app images.
///
/// **Key Features:**
/// - Dedicated cache with size limits (50MB disk, 20 images in memory)
/// - 7-day expiry policy matching Favicons behavior
/// - Background preloading for smooth animations
/// - Automatic cleanup of expired images
/// - Storage excluded from device backups
public class DaxEasterEggImageManager: DaxEasterEggImageManaging {
    
    /// Dedicated cache for Dax Easter Egg images with size limits and expiry
    private lazy var imageCache: ImageCache = {
        let cache = ImageCache(name: "DaxEasterEggImages")
        
        // Disk storage limits (50MB max, similar to favicon limits)
        cache.diskStorage.config.sizeLimit = 50 * 1024 * 1024 // 50MB
        
        // Memory storage limits (20 logos max)
        cache.memoryStorage.config.countLimit = 20
        
        // Exclude from device backups (like Favicons)
        var cacheURL = cache.diskStorage.directoryURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? cacheURL.setResourceValues(resourceValues)
        
        return cache
    }()
    
    /// Options for Dax Easter Egg image caching with expiry policy
    private var cacheOptions: KingfisherOptionsInfo {
        return [
            .targetCache(imageCache),
            .diskCacheExpiration(.days(7)) // Match Favicons 7-day expiry
        ]
    }
    
    public init() {}
    
    public func getBestImageForFullScreen(url: URL, fallbackImage: UIImage?, completion: @escaping (UIImage?) -> Void) {
        let resource = KF.ImageResource(downloadURL: url)
        
        // Check memory cache first for full-res image
        if let cachedImage = imageCache.retrieveImageInMemoryCache(forKey: resource.cacheKey) {
            completion(cachedImage)
            return
        }
        
        // Try disk cache with dedicated image cache
        imageCache.retrieveImage(forKey: resource.cacheKey, options: [.onlyFromCache]) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value):
                    completion(value.image)
                case .failure:
                    completion(fallbackImage)
                }
            }
        }
    }
    
    public func getHighResImageFromMemoryCache(for url: URL) -> UIImage? {
        let resource = KF.ImageResource(downloadURL: url)
        return imageCache.retrieveImageInMemoryCache(forKey: resource.cacheKey)
    }
    
    public func preloadFullResolutionImage(for url: URL) {
        let resource = KF.ImageResource(downloadURL: url)
        
        // Only preload if not already in memory
        guard imageCache.retrieveImageInMemoryCache(forKey: resource.cacheKey) == nil else {
            return
        }
        
        // Preload in background using dedicated cache with expiry
        KingfisherManager.shared.retrieveImage(with: resource, options: cacheOptions) { _ in
            // Background preload, no need to handle result
        }
    }
    
    public func clearExpiredImages() {
        imageCache.cleanExpiredDiskCache()
    }
}
