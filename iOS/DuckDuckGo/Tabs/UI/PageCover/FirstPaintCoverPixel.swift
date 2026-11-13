//
//  FirstPaintCoverPixel.swift
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

import PixelKit

enum FirstPaintCoverPixel: PixelKit.Event {

    enum Destination: String {
        case search
        case website
    }

    /// The covered load never committed, so the cover gave up and lifted on the old page.
    case commitTimeout(Destination)

    var name: String {
        switch self {
        case .commitTimeout: "search_submit_page_cover_commit_timeout"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .commitTimeout(let destination): ["destination": destination.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
