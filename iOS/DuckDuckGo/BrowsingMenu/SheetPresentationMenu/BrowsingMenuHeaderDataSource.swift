//
//  BrowsingMenuHeaderDataSource.swift
//  DuckDuckGo
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

import Foundation
import UIKit

enum HeaderIconType: Equatable {
    case aiChat
    case easterEgg(URL)
    case favicon(UIImage)
    case globe
}

final class BrowsingMenuHeaderDataSource: ObservableObject {
    @Published private(set) var isHeaderVisible: Bool = false
    @Published private(set) var title: String?
    @Published private(set) var displayURL: String?
    @Published private(set) var iconType: HeaderIconType = .globe

    /// Tracks the current URL to detect changes for favicon clearing
    private var currentURL: URL?

    func update(forAITab title: String) {
        self.isHeaderVisible = true
        self.title = title
        self.displayURL = nil
        self.iconType = .aiChat
        self.currentURL = nil
    }

    func update(title: String?, url: URL?, easterEggLogoURL: URL?) {
        self.isHeaderVisible = true
        self.title = title
        self.displayURL = url?.host

        if let easterEggLogoURL {
            self.iconType = .easterEgg(easterEggLogoURL)
        } else {
            // Reset to globe when URL changes, favicon will be updated async
            if self.currentURL != url {
                self.iconType = .globe
            }
        }
        self.currentURL = url
    }

    func update(favicon: UIImage) {
        self.iconType = .favicon(favicon)
    }

    func reset() {
        isHeaderVisible = false
        title = nil
        displayURL = nil
        iconType = .globe
        currentURL = nil
    }
}
