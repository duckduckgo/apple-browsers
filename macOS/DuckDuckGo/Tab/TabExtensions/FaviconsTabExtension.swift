//
//  FaviconsTabExtension.swift
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

import Combine
import Foundation
import Navigation
import UserScript
import WebKit

protocol FaviconUserScriptProvider {
    var faviconScript: FaviconUserScript { get }
}
extension UserScripts: FaviconUserScriptProvider {}

/**
 * This Tab Extension is responsible for updating the Tab instance with the most recent favicon.
 *
 * It manages a `FaviconUserScript` instance, connects `FaviconManager` to it to handle favicon
 * updates, and emits updated favicon via a published variable. The respective `Tab` instance
 * listens to that publisher updates and sets the favicon for the tab.
 */
final class FaviconsTabExtension {
    let faviconManagement: FaviconManagement
    private var cancellables = Set<AnyCancellable>()
    private weak var faviconUserScript: FaviconUserScript?
    private var content: Tab.TabContent?
    private var faviconHandlingTask: Task<Void, Never>? {
        willSet {
            faviconHandlingTask?.cancel()
        }
    }
    @Published private(set) var favicon: NSImage?

    init(
        scriptsPublisher: some Publisher<some FaviconUserScriptProvider, Never>,
        contentPublisher: some Publisher<Tab.TabContent, Never>,
        faviconManagement: FaviconManagement? = nil
    ) {
        self.faviconManagement = faviconManagement ?? NSApp.delegateTyped.faviconManager

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.faviconUserScript = scripts.faviconScript
                self?.faviconUserScript?.delegate = self
            }
        }.store(in: &cancellables)

        contentPublisher.sink { [weak self] content in
            self?.content = content
        }
        .store(in: &cancellables)

        // Re-resolve cached favicon once the favicon cache finishes loading.
        // Tab.swift triggers `loadCachedFavicon` when the URL is set (e.g. for
        // pinned tabs during state restoration), but at that moment the cache
        // may not be loaded yet — `loadCachedFavicon` early-returns on
        // `isCacheLoaded == false`. Without this subscription pinned tabs
        // would render with the LetterView placeholder until something else
        // re-triggered favicon resolution.
        self.faviconManagement.faviconsLoadedPublisher
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.content != nil else { return }
                    // This is a cache refresh, not a navigation – only upgrade to a decoded image, never clear.
                    // pass nil as `oldValue` since there's no navigation - no previous content to compare to.
                    self.loadCachedFavicon(oldValue: nil, isBurner: false, error: nil, clearStaleFaviconOnHostChange: false)
                }
            }
            .store(in: &cancellables)

        // Favicon images decode lazily off the main thread on a cache miss
        // (see FaviconImageCache.get). The decode posts `.faviconCacheUpdated`
        // once the image lands, so re-resolve the tab favicon then — otherwise
        // the first display of a not-yet-decoded favicon would keep the
        // placeholder until the next navigation re-triggered resolution.
        NotificationCenter.default.publisher(for: .faviconCacheUpdated)
            .sink { [weak self] notification in
                let updatedHosts = notification.faviconsCacheUpdate?.hosts
                Task { @MainActor in
                    guard let self, let content = self.content else { return }
                    // only action cache updates for the current tab's host
                    if let updatedHosts, let host = content.urlForWebView?.host,
                       !updatedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) || $0.hasSuffix("." + host) }) {
                        return
                    }
                    // Refresh, not navigation: only upgrade to a decoded image, never clear.
                    self.loadCachedFavicon(oldValue: nil, isBurner: false, error: nil, clearStaleFaviconOnHostChange: false)
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func loadCachedFavicon(oldValue: TabContent? = nil, isBurner: Bool, error: Error? = nil) {
        loadCachedFavicon(oldValue: oldValue, isBurner: isBurner, error: error, clearStaleFaviconOnHostChange: true)
    }

    /// - Parameter clearStaleFaviconOnHostChange: When `true` (navigation), the favicon is cleared if
    ///   the cache has no image for the new host, so a previous site's icon isn't left behind. When
    ///   `false` (a cache-update / cache-loaded *refresh*, where `oldValue` is always `nil`), the
    ///   favicon is only upgraded once a decoded image is available and is never cleared. Clearing on a
    ///   refresh blanked the favicon to the LetterView placeholder during the lazy off-main decode
    ///   window (`getCachedFavicon(…)?.image` is `nil` while decoding), which made favicons blink
    ///   between placeholder and image as `.faviconCacheUpdated` fired repeatedly.
    @MainActor
    private func loadCachedFavicon(oldValue: TabContent?, isBurner: Bool, error: Error?, clearStaleFaviconOnHostChange: Bool) {
        guard let content, content.isExternalUrl, let url = content.urlForWebView, error == nil else {
            // Load default Favicon for SpecialURL(s) such as newtab
            favicon = content?.displayedFavicon(error: error, isBurner: isBurner)
            return
        }

        guard faviconManagement.isCacheLoaded else { return }

        if let cachedFavicon = faviconManagement.getCachedFavicon(forUrlOrAnySubdomain: url, sizeCategory: .small, fallBackToSmaller: false)?.image {
            if cachedFavicon != favicon {
                favicon = cachedFavicon
            }
        } else if clearStaleFaviconOnHostChange, oldValue?.urlForWebView?.host != url.host {
            // If the domain matches the previous value, just keep the same favicon
            favicon = nil
        }
    }

    deinit {
        faviconHandlingTask?.cancel()
    }
}

extension FaviconsTabExtension: FaviconUserScriptDelegate {
    @MainActor
    func faviconUserScript(_ faviconUserScript: FaviconUserScript, didFindFaviconLinks faviconLinks: [FaviconUserScript.FaviconLink], for documentUrl: URL, in webView: WKWebView?) {
        guard documentUrl != .error, documentUrl == content?.urlForWebView else { return }
        // old task cancelled in setter
        faviconHandlingTask = Task { [weak self, faviconManagement] in
            if let favicon = await faviconManagement.handleFaviconLinks(faviconLinks, documentUrl: documentUrl, webView: webView),
               !Task.isCancelled, let self, documentUrl == content?.urlForWebView {
                self.favicon = favicon.image
            }
        }
    }
}

protocol FaviconsTabExtensionProtocol: AnyObject {
    @MainActor
    func loadCachedFavicon(oldValue: TabContent?, isBurner: Bool, error: Error?)

    var faviconPublisher: AnyPublisher<NSImage?, Never> { get }
}

extension FaviconsTabExtension: FaviconsTabExtensionProtocol, TabExtension {
    func getPublicProtocol() -> FaviconsTabExtensionProtocol { self }

    var faviconPublisher: AnyPublisher<NSImage?, Never> {
        $favicon.dropFirst().eraseToAnyPublisher()
    }
}

extension TabExtensions {
    var favicons: FaviconsTabExtensionProtocol? {
        resolve(FaviconsTabExtension.self)
    }
}
