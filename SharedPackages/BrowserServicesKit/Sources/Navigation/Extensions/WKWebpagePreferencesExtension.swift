//
//  WKWebpagePreferencesExtension.swift
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

extension WKWebpagePreferences {

#if _WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED

    private static let customHeaderFieldsKey = "customHeaderFields"

    public static var customHeaderFieldsSupported: Bool {
        self.instancesRespond(to: NSSelectorFromString("_" + Self.customHeaderFieldsKey))
        || self.instancesRespond(to: NSSelectorFromString(Self.customHeaderFieldsKey))
    }

    /// used to add custom request headers to `WKNavigationAction` before the request is sent
    public var customHeaderFields: [CustomHeaderFields]? {
        get {
            guard Self.customHeaderFieldsSupported else { return nil }
            return value(forKey: Self.customHeaderFieldsKey) as? [CustomHeaderFields]
        }
        set {
            guard Self.customHeaderFieldsSupported else {
                assertionFailure("custom header fields not supported")
                return
            }
            setValue(newValue as NSArray?, forKey: Self.customHeaderFieldsKey)
        }
    }

#endif

}
