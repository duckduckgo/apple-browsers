//
//  WKBackForwardListItemExtension.swift
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
import WebKit

public extension WKBackForwardListItem {

    /// Safe Optional `url: URL` getter:
    /// `WKBackForwardListItem.url` is imported as non-optional, but WebKit's
    /// implementation can return nil for null or invalid underlying URLs,
    /// trapping Swift's unconditional `NSURL` → `URL` bridge. Reading via the
    /// getter selector keeps the value optional so the conditional `as? URL`
    /// cast safely returns nil instead of crashing.
    /// See: https://app.asana.com/1/137249556945/project/1201037661562251/task/1214602405943382
    var safeURL: URL? {
        self.perform(#selector(getter: WKBackForwardListItem.url))?.takeUnretainedValue() as? URL
    }

}
