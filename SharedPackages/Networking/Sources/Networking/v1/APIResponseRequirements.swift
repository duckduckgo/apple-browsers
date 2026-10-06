//
//  APIResponseRequirements.swift
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

import Foundation

public struct APIResponseRequirements: OptionSet {

    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The API response must have non-empty data.
    public static let requireNonEmptyData = APIResponseRequirements(rawValue: 1 << 0)

    /// The API response must include an ETag header.
    public static let requireETagHeader = APIResponseRequirements(rawValue: 1 << 1)

    /// Allows HTTP 304 (Not Modified) response status code.
    /// When this is set, requireNonEmptyData is not honored, since URLSession returns empty data on HTTP 304.
    public static let allowHTTPNotModified = APIResponseRequirements(rawValue: 1 << 2)

    /// The user agent is required in the HTTP headers
    public static let requireUserAgent = APIResponseRequirements(rawValue: 1 << 3)

    public static let `default`: APIResponseRequirements = [.requireNonEmptyData, .requireETagHeader]
    public static let all: APIResponseRequirements = [.requireNonEmptyData, .requireETagHeader, .allowHTTPNotModified, .requireUserAgent]

}
