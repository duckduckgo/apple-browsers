//
//  WKBackForwardListItemExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

extension WKBackForwardListItem {

    // sometimes WKBackForwardListItem returns wrong or outdated title
    private static let tabTitleKey = UnsafeRawPointer(bitPattern: "tabTitleKey".hashValue)!
    var tabTitle: String? {
        get {
            objc_getAssociatedObject(self, Self.tabTitleKey) as? String
        }
        set {
            objc_setAssociatedObject(self, Self.tabTitleKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // `url` is imported as non-optional but WebKit's implementation returns nil
    // for null/invalid underlying URLs, trapping the unconditional NSURL→URL bridge.
    // Read via KVC to keep the optional and use a conditional bridge.
    var safeURL: URL? {
        (self as NSObject).value(forKey: "URL") as? URL
    }

}
