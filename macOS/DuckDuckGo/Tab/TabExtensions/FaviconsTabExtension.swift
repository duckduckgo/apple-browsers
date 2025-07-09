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
    }

    @MainActor
    func handleFavicon(oldValue: TabContent? = nil, error: Error? = nil) {
        guard let content, content.isUrl, let url = content.urlForWebView, error == nil else {
            favicon = nil
            return
        }

        guard faviconManagement.isCacheLoaded else { return }

        if let cachedFavicon = faviconManagement.getCachedFavicon(for: url, sizeCategory: .small)?.image {
            if cachedFavicon != favicon {
                favicon = cachedFavicon
            }
        } else if oldValue?.urlForWebView?.host != url.host {
            // If the domain matches the previous value, just keep the same favicon
            favicon = nil
        }
    }
}

extension FaviconsTabExtension: FaviconUserScriptDelegate {
    @MainActor
    func faviconUserScript(_ faviconUserScript: FaviconUserScript, didFindFaviconLinks faviconLinks: [FaviconUserScript.FaviconLink], for documentUrl: URL) async {
        guard documentUrl != .error,
              documentUrl == content?.urlForWebView,
              let favicon = await faviconManagement.handleFaviconLinks(faviconLinks, documentUrl: documentUrl)
        else {
            return
        }
        self.favicon = favicon.image
    }
}

extension FaviconsTabExtension: NavigationResponder {
}

protocol FaviconsTabExtensionProtocol: AnyObject, NavigationResponder {
    @MainActor
    func handleFavicon(oldValue: TabContent?, error: Error?)

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
