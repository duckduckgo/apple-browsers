//
//  MockWKWebView.swift
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

/// Mock implementation of WKWebView for testing purposes.
/// Allows setting a custom URL without requiring a full web view setup.
public class MockWKWebView: WKWebView {
    private let mockURL: URL?

    /// Creates a mock web view with an optional URL.
    ///
    /// - Parameter url: The URL to return from the `url` property
    public init(url: URL?) {
        self.mockURL = url
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var url: URL? {
        return mockURL
    }
}
