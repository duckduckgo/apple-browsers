//
//  NSNotificationName+Favicons.swift
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

import Foundation

extension NSNotification.Name {

    static let faviconCacheUpdated = NSNotification.Name("FaviconCacheUpdatedNotification")

}

/// Payload of `.faviconCacheUpdated`: the favicons whose image just became available in the cache.
/// Observers use it to decide whether they actually need to reload, instead of reloading unconditionally.
struct FaviconsCacheUpdate {

    fileprivate static let userInfoKey = "favicons.cacheUpdate"

    /// Favicon image URLs whose image just became available.
    let faviconURLs: Set<URL>

    /// Hosts the favicons belong to.
    let hosts: Set<String>

    init(faviconURLs: Set<URL>, documentURLs: some Sequence<URL>) {
        self.faviconURLs = faviconURLs
        self.hosts = Set(documentURLs.compactMap(\.host))
    }

}

extension Notification {

    /// The `FaviconsCacheUpdate` carried by a `.faviconCacheUpdated` notification, if present.
    var faviconsCacheUpdate: FaviconsCacheUpdate? {
        userInfo?[FaviconsCacheUpdate.userInfoKey] as? FaviconsCacheUpdate
    }

}

extension NotificationCenter {

    /// Posts `.faviconCacheUpdated` describing which favicons just became available, so observers
    /// can reload selectively.
    func postFaviconCacheUpdated(faviconURLs: Set<URL>, documentURLs: some Sequence<URL>) {
        post(name: .faviconCacheUpdated,
             object: nil,
             userInfo: [FaviconsCacheUpdate.userInfoKey: FaviconsCacheUpdate(faviconURLs: faviconURLs, documentURLs: documentURLs)])
    }

}
