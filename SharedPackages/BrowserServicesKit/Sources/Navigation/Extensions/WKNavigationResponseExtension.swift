//
//  WKNavigationResponseExtension.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import WebKit

extension WKNavigationResponse {

    // associated NavigationResponse wrapper for the WKNavigationResponse
    private static let navigationResponseKey = UnsafeRawPointer(bitPattern: "navigationResponseKey".hashValue)!
    internal var navigationResponse: NavigationResponse? {
        get {
            objc_getAssociatedObject(self, Self.navigationResponseKey) as? NavigationResponse
        }
        set {
            objc_setAssociatedObject(self, Self.navigationResponseKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

}

extension WKNavigationResponsePolicy {

    static let downloadPolicy: WKNavigationResponsePolicy = {
        if #available(macOS 11.3, iOS 14.5, *) {
            return .download
        }
        return WKNavigationResponsePolicy(rawValue: Self.allow.rawValue + 1) ?? .cancel
    }()

}
