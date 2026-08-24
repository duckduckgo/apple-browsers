//
//  MainResourceDataProviding.swift
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
import WebKitExtensions

/// Read access to the bytes of the document a web view is displaying.
///
/// A seam AIChat owns so document context extraction can be unit-tested without a real web view.
/// The production conformance is `WKWebView`, backed by the WebKitExtensions main-resource reader.
public protocol MainResourceDataProviding: AnyObject {
    @MainActor func mainResourceData(timeout: TimeInterval) async -> Data?
}

public extension MainResourceDataProviding {
    @MainActor func mainResourceData() async -> Data? {
        await mainResourceData(timeout: 5)
    }
}

extension WKWebView: MainResourceDataProviding {}
