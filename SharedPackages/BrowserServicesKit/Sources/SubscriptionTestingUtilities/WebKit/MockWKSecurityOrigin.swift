//
//  MockWKSecurityOrigin.swift
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

/// Mock implementation of WKSecurityOrigin for testing purposes.
/// Allows setting custom security origin properties for testing security validations.
@objc public class MockWKSecurityOrigin: WKSecurityOrigin {
    var mockProtocol: String!
    public override var `protocol`: String { mockProtocol }

    var mockHost: String!
    public override var host: String { mockHost }

    var mockPort: Int!
    public override var port: Int { mockPort }

    internal func setURL(_ url: URL) {
        self.mockProtocol = url.scheme ?? ""
        self.mockHost = url.host ?? ""
        self.mockPort = url.port ?? 0
    }

    internal func setHost(_ host: String) {
        self.mockHost = host
        self.mockProtocol = "https"
        self.mockPort = 443
    }

    /// Creates a mock security origin with the specified URL.
    ///
    /// - Parameter url: The URL to extract security origin from
    /// - Returns: A configured mock security origin
    public class func new(url: URL) -> MockWKSecurityOrigin {
        let mock = (self.perform(NSSelectorFromString("alloc")).takeUnretainedValue() as? MockWKSecurityOrigin)!
        mock.setURL(url)
        return mock
    }

    /// Creates a mock security origin with the specified host.
    ///
    /// - Parameter host: The host string
    /// - Returns: A configured mock security origin
    public class func new(host: String) -> MockWKSecurityOrigin {
        let mock = (self.perform(NSSelectorFromString("alloc")).takeUnretainedValue() as? MockWKSecurityOrigin)!
        mock.setHost(host)
        return mock
    }
}
