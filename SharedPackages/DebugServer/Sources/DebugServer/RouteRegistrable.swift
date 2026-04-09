//
//  RouteRegistrable.swift
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

/// A closure that handles an HTTP request and returns a response.
public typealias RouteHandler = @Sendable (HTTPRequest) throws -> HTTPResponse

/// Provides route registration capabilities.
public protocol RouteRegistrable: AnyObject {

    /// Registers a handler for the given method and path.
    ///
    /// - Parameters:
    ///   - path: The URL path to match (e.g., "/api/chats").
    ///   - method: The HTTP method to match.
    ///   - handler: A closure invoked when a matching request is received.
    func addRoute(_ path: String, method: HTTPMethod, handler: @escaping RouteHandler)

    /// Registers a handler for requests whose path starts with the given prefix.
    ///
    /// Prefix routes are checked only when no exact route matches.
    ///
    /// - Parameters:
    ///   - pathPrefix: The URL path prefix to match (e.g., "/api/chats/").
    ///   - method: The HTTP method to match.
    ///   - handler: A closure invoked when a matching request is received.
    func addPrefixRoute(_ pathPrefix: String, method: HTTPMethod, handler: @escaping RouteHandler)

    /// Registers a static HTML response for the given path (GET only).
    ///
    /// - Parameters:
    ///   - path: The URL path to match.
    ///   - htmlString: The HTML content to serve.
    func addStaticRoute(_ path: String, htmlString: String)
}
