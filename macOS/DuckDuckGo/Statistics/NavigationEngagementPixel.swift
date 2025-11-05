//
//  NavigationEngagementPixel.swift
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

import Foundation
import PixelKit

/**
 * This enum keeps pixels related to navigation bar engagement.
 */
enum NavigationEngagementPixel {

    /**
     * Event Trigger: User navigated to URL.
     *
     * > Related links:
     * [Privacy Triage]()
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/task/1210638013987333/comment/1210650613141238?focus=true)
     */
    case navigateToURL(source: URLSource)

    /**
     * Event Trigger: User navigated to bookmark.
     *
     * > Related links:
     * [Privacy Triage]()
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/task/1210638013987333/comment/1210650613141238?focus=true)
     */
    case navigateToBookmark(source: BookmarkSource, isFavorite: Bool)

    enum BookmarkSource: String {
        case listInterface = "source-list-interface"
        case menu = "source-menu"
        case newTabPage = "source-new-tab"
    }

    enum URLSource: String {
        case addressBar = "source-address-bar"
        case newTabPage = "source-new-tab"
        case suggestion = "source-suggestion"
    }
}

extension NavigationEngagementPixel: PixelKitEvent {

    var name: String {
        switch self {
        case .navigateToURL(let source):
            return "navigation_url_\(source.rawValue)"
        case .navigateToBookmark(let source, let isFavorite):
            if isFavorite {
                return "navigation_favorite_\(source.rawValue)"
            } else {
                return "navigation_bookmark_\(source.rawValue)"
            }
        }
    }

    var frequency: PixelKit.Frequency {
        .standard
    }

    var parameters: [String: String]? {
        nil
    }

}
