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

final class BrowsingMenuHeaderDataSource: ObservableObject {
    @Published private(set) var isHeaderVisible: Bool = false
    @Published private(set) var title: String?
    @Published private(set) var url: URL?
    @Published private(set) var favicon: UIImage?
    @Published private(set) var easterEggLogoURL: URL?

    func update(isHeaderVisible: Bool, title: String?, url: URL?, easterEggLogoURL: URL?) {
        self.isHeaderVisible = isHeaderVisible
        self.title = title
        self.easterEggLogoURL = easterEggLogoURL

        // Clear favicon when URL changes to avoid stale favicon during async load
        if self.url != url {
            self.favicon = nil
        }
        self.url = url
    }

    func update(favicon: UIImage?) {
        self.favicon = favicon
    }

    func reset() {
        isHeaderVisible = false
        title = nil
        url = nil
        favicon = nil
        easterEggLogoURL = nil
    }
}
