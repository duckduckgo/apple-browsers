//
//  LoginFaviconView.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import SwiftUI
import SwiftUIExtensions

struct LoginFaviconView: View {
    let domain: String
    let generatedIconLetters: String
    let faviconManagement: FaviconManagement = NSApp.delegateTyped.faviconManager

    @State private var image: NSImage?
    /// Bumped from the `.faviconCacheUpdated` observer to re-run the loader while the placeholder is shown.
    @State private var reloadCount = 0

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32)
                    .cornerRadius(4.0)
                    .padding(.leading, 6)
            } else {
                LetterIconView(title: generatedIconLetters, font: .system(size: 32, weight: .semibold))
                    .padding(.leading, 8)
            }
        }
        // Favicon images are decoded lazily off-main, so await the decode on appear / domain change, and
        // re-resolve when this row's favicon arrives later (the `.faviconCacheUpdated` observer bumps
        // `reloadCount`). Keying the task on both cancels any in-flight load when either changes, so a
        // stale result can't overwrite a newer one; clearing first avoids flashing a recycled row's icon.
        .task(id: ReloadKey(domain: domain, reloadCount: reloadCount)) {
            image = nil
            let resolved = await faviconManagement.resolvedCachedFaviconSafeForRendering(for: domain, sizeCategory: .small)?.image
            guard !Task.isCancelled else { return }
            image = resolved
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            // Re-resolve only while the placeholder is shown and the update's affected domains include this row's.
            guard image == nil,
                  let update = notification.faviconsCacheUpdate,
                  update.hosts.contains(domain) else { return }
            reloadCount += 1
        }
    }

    private struct ReloadKey: Equatable {
        let domain: String
        let reloadCount: Int
    }

}
