//
//  UIImageViewExtension.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

private final class FaviconLoadRequest {
    let domain: String?
    weak var appliedImage: UIImage?

    init(domain: String?) {
        self.domain = domain
    }
}

extension UIImageView {

    private static var faviconLoadRequestKey: UInt8 = 0

    private var faviconLoadRequest: FaviconLoadRequest? {
        get { objc_getAssociatedObject(self, UnsafeRawPointer(&Self.faviconLoadRequestKey)) as? FaviconLoadRequest }
        set { objc_setAssociatedObject(self, UnsafeRawPointer(&Self.faviconLoadRequestKey), newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// Load a favicon from the cache in to this uiview.  This will not load the favicon from the network.
    /// Disk cache reads happen off the main thread, so the image (and `completion`) may arrive asynchronously.
    func loadFavicon(forDomain domain: String?,
                     usingCache cacheType: FaviconsCacheType,
                     useFakeFavicon: Bool = true,
                     preferredFakeFaviconLetters: String? = nil,
                     completion: ((UIImage?, Bool) -> Void)? = nil) {

        func load() {
            let request = FaviconLoadRequest(domain: domain)
            // While the disk read is in flight, keep the current image only if it's this domain's favicon.
            // Otherwise (e.g. a reused cell) show nothing, or the fake favicon if one was already generated.
            let previous = faviconLoadRequest
            let isShowingThisDomainsFavicon = previous?.domain == domain && image != nil && image === previous?.appliedImage
            if !isShowingThisDomainsFavicon {
                image = nil
                if useFakeFavicon, let domain {
                    image = FaviconsHelper.cachedFakeFavicon(forDomain: domain, preferredFakeFaviconLetters: preferredFakeFaviconLetters)
                }
            }
            faviconLoadRequest = request
            let placeholder = image
            FaviconsHelper.loadFavicon(forDomain: domain,
                                       usingCache: cacheType,
                                       useFakeFavicon: useFakeFavicon,
                                       preferredFakeFaviconLetters: preferredFakeFaviconLetters) { [weak self] image, fake in
                // Drop the result if another favicon was requested, or an image was set directly, in the meantime.
                guard let self, self.faviconLoadRequest === request, self.image === placeholder else { return }
                self.image = image
                request.appliedImage = image
                completion?(image, fake)
            }
        }

        if Thread.isMainThread {
            load()
        } else {
            DispatchQueue.main.async(execute: load)
        }
    }

}
