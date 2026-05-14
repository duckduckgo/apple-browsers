//
//  WebExtensionInternalSiteHandling.swift
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

import WebKit

/// Data source protocol for providing web extension context lookups.
@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionInternalSiteHandlerDataSource: AnyObject {
    func webExtensionContext(for url: URL) -> WKWebExtensionContext?
}

/// Protocol for handling internal extension site requests.
/// Platform-specific implementations handle URL loading for extension pages.
@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionInternalSiteHandling: AnyObject {
    var dataSource: (any WebExtensionInternalSiteHandlerDataSource)? { get set }
}
