//
//  URLSession+LocalModels.swift
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

public extension URLSession {

    /// A session for model downloads: no cookies, no cache, and nothing identifying the app, OS or user's languages.
    static func localModels(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        // URLSession always sends Accept-Language; an empty value is the closest to dropping it.
        configuration.httpAdditionalHeaders = ["User-Agent": "DuckDuckGo", "Accept-Language": ""]
        return URLSession(configuration: configuration)
    }
}
