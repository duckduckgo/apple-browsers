//
//  FaviconsHelper.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import UIKit
import Core
import Kingfisher
import Common
import FoundationExtensions
import DesignResourcesKit

struct FaviconsHelper {

    private enum FaviconError: Error {
        case missingFile
        case corruptedData
    }

    private struct Constants {
        static let duckPlayerDomain = "player"
        static let duckPlayerImageName = "DuckPlayerURLIcon"
        static let duckDuckGoImageName = "duckduckgo-favicon-128x128"
    }

    private static let tld: TLD = AppDependencyProvider.shared.storageCache.tld
    private static let sourcesProvider: FaviconSourcesProvider = DefaultFaviconSourcesProvider()
    private static let diskQueue = DispatchQueue(label: "com.duckduckgo.favicons.diskRead", qos: .userInitiated)
    private static let fakeFavicons = NSCache<NSString, UIImage>()

    static func loadFaviconSync(forDomain domain: String?,
                                usingCache cacheType: FaviconsCacheType,
                                useFakeFavicon: Bool,
                                preferredFakeFaviconLetters: String? = nil) -> (image: UIImage?, isFake: Bool) {

        // Handle special cases first
        if let customImage = customImage(for: domain) {
            return (customImage, false)
        }

        // Check cache and resource availability
        guard let cache = Favicons.Constants.caches[cacheType],
              let resource = FaviconsHelper.defaultResource(forDomain: domain, sourcesProvider: sourcesProvider) else {
            return createFallbackResult(domain: domain,
                                      useFakeFavicon: useFakeFavicon,
                                      preferredLetters: preferredFakeFaviconLetters)
        }

        // Try memory cache first
        if let cachedImage = cache.retrieveImageInMemoryCache(forKey: resource.cacheKey) {
            return (cachedImage, false)
        }

        if let image = loadFaviconFromDisk(cache: cache, cacheKey: resource.cacheKey, domain: domain) {
            return (image, false)
        }
        return createFallbackResult(domain: domain,
                                    useFakeFavicon: useFakeFavicon,
                                    preferredLetters: preferredFakeFaviconLetters)
    }

    /// Same as `loadFaviconSync`, but reads the disk cache off the main thread.
    /// Must be called on the main thread. `completion` is called on the main thread: synchronously when the favicon
    /// doesn't need a disk read (custom image, memory cache hit or no cache entry), asynchronously otherwise.
    static func loadFavicon(forDomain domain: String?,
                            usingCache cacheType: FaviconsCacheType,
                            useFakeFavicon: Bool,
                            preferredFakeFaviconLetters: String? = nil,
                            completion: @escaping (UIImage?, Bool) -> Void) {
        if let customImage = customImage(for: domain) {
            completion(customImage, false)
            return
        }

        guard let cache = Favicons.Constants.caches[cacheType],
              let resource = FaviconsHelper.defaultResource(forDomain: domain, sourcesProvider: sourcesProvider) else {
            let result = createFallbackResult(domain: domain, useFakeFavicon: useFakeFavicon, preferredLetters: preferredFakeFaviconLetters)
            completion(result.0, result.1)
            return
        }

        if let cachedImage = cache.retrieveImageInMemoryCache(forKey: resource.cacheKey) {
            completion(cachedImage, false)
            return
        }

        diskQueue.async {
            let image = loadFaviconFromDisk(cache: cache, cacheKey: resource.cacheKey, domain: domain)
            DispatchQueue.main.async {
                if let image {
                    completion(image, false)
                } else {
                    // Fake favicons are drawn with UIKit, so they have to be created on the main thread.
                    let result = createFallbackResult(domain: domain, useFakeFavicon: useFakeFavicon, preferredLetters: preferredFakeFaviconLetters)
                    completion(result.0, result.1)
                }
            }
        }
    }

    /// Reads the favicon from the disk cache and copies it into the memory cache. Safe to call off the main thread.
    private static func loadFaviconFromDisk(cache: ImageCache, cacheKey: String, domain: String?) -> UIImage? {
        do {
            let url = cache.diskStorage.cacheFileURL(forKey: cacheKey)

            guard FileManager.default.fileExists(atPath: url.path) else {
                throw FaviconError.missingFile
            }

            let data = try Data(contentsOf: url, options: [.uncached])
            guard let image = UIImage(data: data) else {
                throw FaviconError.corruptedData
            }

            // Store in memory cache with original expiry date, unless a fresher favicon got there during the read
            if cache.retrieveImageInMemoryCache(forKey: cacheKey) == nil,
               let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileModificationDate = attributes[.modificationDate] as? Date {

                cache.store(image,
                           forKey: cacheKey,
                           options: KingfisherParsedOptionsInfo([
                            .cacheMemoryOnly,
                            .diskCacheAccessExtendingExpiration(.none),
                            .memoryCacheExpiration(.date(fileModificationDate))
                           ]),
                           toDisk: false)
            }

            return image

        } catch {
            Logger.general.error("Failed to load favicon from disk for domain: \(domain ?? "unknown"), error: \(error)")
            return nil
        }
    }

    static func loadFaviconSync(forDomain domain: String?,
                                usingCache cacheType: FaviconsCacheType,
                                useFakeFavicon: Bool,
                                preferredFakeFaviconLetters: String? = nil,
                                completion: ((UIImage?, Bool) -> Void)? = nil) {
        let result = loadFaviconSync(forDomain: domain, usingCache: cacheType, useFakeFavicon: useFakeFavicon, preferredFakeFaviconLetters: preferredFakeFaviconLetters)

        completion?(result.image, result.isFake)
    }

    static func createFakeFavicon(forDomain domain: String,
                                  size: CGFloat = 192,
                                  backgroundColor: UIColor = UIColor(baseColor: .gray70),
                                  bold: Bool = true,
                                  preferredFakeFaviconLetters: String? = nil,
                                  letterCount: Int = 2) -> UIImage? {

        let cornerRadius = size * 0.125
        let imageRect = CGRect(x: 0, y: 0, width: size, height: size)
        let padding = size * 0.16
        let labelFrame = CGRect(x: padding, y: padding, width: imageRect.width - (2 * padding), height: imageRect.height - (2 * padding))

        let renderer = UIGraphicsImageRenderer(size: imageRect.size)
        let icon = renderer.image { imageContext in
            let context = imageContext.cgContext

            context.setFillColor(backgroundColor.cgColor)
            context.addPath(CGPath(roundedRect: imageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            context.fillPath()

            let label = UILabel(frame: labelFrame)
            label.numberOfLines = 1
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.1
            label.baselineAdjustment = .alignCenters
            label.font = bold ? UIFont.boldAppFont(ofSize: size) : UIFont.appFont(ofSize: size)
            label.textColor = UIColor.white
            label.textAlignment = .center

            if let prefferedPrefix = preferredFakeFaviconLetters?.droppingWwwPrefix().prefix(letterCount).capitalized {
                label.text = prefferedPrefix
            } else {
                label.text = String(tld.eTLDplus1(domain)?.prefix(letterCount) ?? "#").capitalized
            }

            context.translateBy(x: padding, y: padding)

            label.layer.draw(in: context)
        }
         
        return icon.withRenderingMode(.alwaysOriginal)
    }

    // this function is now static and outside of Favicons, otherwise there is a circular dependency between
    // Favicons and NotFoundCachingDownloader
    public static func defaultResource(forDomain domain: String?, sourcesProvider: FaviconSourcesProvider) -> KF.ImageResource? {
        guard let domain = domain,
              let source = sourcesProvider.mainSource(forDomain: domain) else { return nil }

        let key = FaviconHasher.createHash(ofDomain: domain)
        return KF.ImageResource(downloadURL: source, cacheKey: key)
    }

    private static func createFallbackResult(domain: String?,
                                             useFakeFavicon: Bool,
                                             preferredLetters: String?) -> (UIImage?, Bool) {
        guard useFakeFavicon,
              let domain = domain else {
            return (nil, false)
        }

        if let fakeFavicon = cachedFakeFavicon(forDomain: domain, preferredFakeFaviconLetters: preferredLetters) {
            return (fakeFavicon, true)
        }

        let fakeFavicon = createFakeFavicon(forDomain: domain,
                                           backgroundColor: UIColor.forDomain(domain),
                                           preferredFakeFaviconLetters: preferredLetters)
        if let fakeFavicon {
            fakeFavicons.setObject(fakeFavicon, forKey: fakeFaviconKey(domain: domain, preferredLetters: preferredLetters))
        }
        return (fakeFavicon, true)
    }

    /// Fake favicon previously generated for this domain, if any. Rendering one is expensive, so they're kept in memory.
    static func cachedFakeFavicon(forDomain domain: String, preferredFakeFaviconLetters: String?) -> UIImage? {
        fakeFavicons.object(forKey: fakeFaviconKey(domain: domain, preferredLetters: preferredFakeFaviconLetters))
    }

    private static func fakeFaviconKey(domain: String, preferredLetters: String?) -> NSString {
        "\(domain)|\(preferredLetters ?? "")" as NSString
    }

    private static func customImage(for domain: String?) -> UIImage? {
        let imageName: String
        if URL.isDuckDuckGo(domain: domain) {
            imageName = Constants.duckDuckGoImageName
        } else if domain == Constants.duckPlayerDomain {
            imageName = Constants.duckPlayerImageName
        } else {
            return nil
        }

        let image = UIImage(named: imageName)
        image?.accessibilityIdentifier = imageName
        return image
    }

}
