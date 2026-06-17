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
import BrowserServicesKit
import SwiftUIExtensions

struct LoginFaviconView: View {
    let domain: String
    let generatedIconLetters: String
    let faviconManagement: FaviconManagement = NSApp.delegateTyped.faviconManager

    @State private var image: NSImage?
    /// helper variable to improve reloading a favicon on update while the view is on screen.
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
        // Favicon images are decoded lazily off-main. Await the decode on appear / domain change, and
        // re-resolve when a favicon for this domain becomes available later while the row is on screen
        // (bumping `reloadCount` from the `.faviconCacheUpdated` observer below). Keying the task on both
        // inputs makes SwiftUI cancel the in-flight load whenever either changes, so a stale or cancelled
        // load can't overwrite a newer one; clearing first avoids briefly showing a recycled row's
        // previous favicon (a no-op on the reload path, where we only get here while the image is nil).
        .task(id: ReloadKey(domain: domain, reloadCount: reloadCount)) {
            image = nil
            let resolved = await faviconManagement.resolvedCachedFaviconSafeForRendering(for: domain, sizeCategory: .small)?.image
            guard !Task.isCancelled else { return }
            image = resolved
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { _ in
            // Only react while we still show the placeholder; once we have an image we're done.
            guard image == nil else { return }
            reloadCount += 1
        }
    }

    private struct ReloadKey: Equatable {
        let domain: String
        let reloadCount: Int
    }

}
