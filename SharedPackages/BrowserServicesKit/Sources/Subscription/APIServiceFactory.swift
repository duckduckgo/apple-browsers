//
//  APIServiceFactory.swift
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

import Foundation
import Networking

public struct APIServiceFactory {

    /// Creates an APIService for the main app flow. This service stores cookies or use any cache.
    public static func makeAPIServiceForAuthV2(withUserAgent userAgent: String) -> APIService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        let urlSession = URLSession(configuration: configuration, delegate: SessionDelegate(), delegateQueue: nil)
        return DefaultAPIService(urlSession: urlSession, userAgent: userAgent)
    }

    /// Creates an APIService for the subscription flow. This service should not store cookies.
    public static func makeAPIServiceForSubscription(withUserAgent userAgent: String) -> APIService {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        let urlSession = URLSession(configuration: configuration, delegate: SessionDelegate(), delegateQueue: nil)
        return DefaultAPIService(urlSession: urlSession, userAgent: userAgent)
    }
}
