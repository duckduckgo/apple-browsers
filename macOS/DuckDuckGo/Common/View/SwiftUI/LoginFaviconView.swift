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
    let osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion

    private var displayableFaviconImage: NSImage? {
        // Workaround for favicon rendering crashes on Ventura 13.7.8 and newer 13.x patches.
        switch (osVersion.majorVersion, osVersion.minorVersion, osVersion.patchVersion) {
        case let (13, minor, _) where minor > 7:
            return nil
        case let (13, 7, patch) where patch >= 8:
            return nil
        default:
            return faviconManagement.getCachedFavicon(for: domain, sizeCategory: .small)?.image
        }
    }

    var body: some View {
        Group {
            if let image = displayableFaviconImage {
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
    }

    var favicon: NSImage? {
        return displayableFaviconImage ?? .login
    }

}
