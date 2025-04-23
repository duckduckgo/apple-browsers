//
//  AIChatUserAgentProviding.swift
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

#if os(iOS)
import Foundation

/// A protocol for generating a user agent string based on a given URL.
public protocol AIChatUserAgentProviding {

    /// Returns a user agent string for the specified URL.
    ///
    /// - Parameter url: An optional URL to customize the user agent. If `nil`, a default
    ///                  user agent should be returned.
    /// - Returns: A `String` representing the user agent for the given URL.
    func userAgent(url: URL?) -> String
}
#endif
