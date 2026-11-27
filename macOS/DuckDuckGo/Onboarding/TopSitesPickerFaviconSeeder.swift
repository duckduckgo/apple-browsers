//
//  TopSitesPickerFaviconSeeder.swift
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

import Bookmarks
import ContentScopeScripts
import Foundation

protocol TopSitesPickerFaviconSeederProtocol {
    /// Stores the icon the picker showed as the favicon of each site that has none yet,
    /// so a new favorite shows its logo before the user visits the site.
    @MainActor
    func seedFavicons(for sites: [OnboardingUserScript.FavoriteSite]) async
}

/// Reads the icons content-scope-scripts bundles with the onboarding page, named `<site id>.png`.
final class TopSitesPickerFaviconSeeder: TopSitesPickerFaviconSeederProtocol {
    private let faviconStore: Bookmarks.FaviconStoring
    private let iconsDirectory: URL?

    init(
        faviconStore: Bookmarks.FaviconStoring,
        iconsDirectory: URL? = ContentScopeScripts.Bundle.url(forResource: "top-sites", withExtension: nil, subdirectory: "pages/onboarding/assets/img/v4")
    ) {
        self.faviconStore = faviconStore
        self.iconsDirectory = iconsDirectory
    }

    @MainActor
    func seedFavicons(for sites: [OnboardingUserScript.FavoriteSite]) async {
        for site in sites {
            guard let host = site.url.host,
                  !faviconStore.hasFavicon(for: host),
                  let iconFileURL = bundledIconFileURL(for: site.id),
                  let iconData = try? Data(contentsOf: iconFileURL) else {
                continue
            }
            try? await faviconStore.storeFavicon(iconData, with: pageIconURL(for: site.id), for: homePageURL(for: site.url))
        }
    }

    /// A visit loads the home page as `https://host/`, so storing the icon for that URL lets the fetched favicon replace it.
    private func homePageURL(for url: URL) -> URL {
        guard url.path.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.path = "/"
        return components.url ?? url
    }

    /// The page can send any id, so only a plain name maps to a file in the icons folder.
    private func bundledIconFileURL(for siteID: String) -> URL? {
        guard let iconsDirectory, isPlainName(siteID) else { return nil }
        return iconsDirectory.appendingPathComponent(siteID).appendingPathExtension("png")
    }

    /// The URL the onboarding page loads the icon from, recorded as the favicon's source.
    private func pageIconURL(for siteID: String) -> URL {
        URL.onboarding.appendingPathComponent("assets/img/v4/top-sites/\(siteID).png")
    }

    private func isPlainName(_ siteID: String) -> Bool {
        !siteID.isEmpty && siteID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
