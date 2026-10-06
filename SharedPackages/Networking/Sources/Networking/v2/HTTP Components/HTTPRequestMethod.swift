//
//  HTTPRequestMethod.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

/// Represents the standard HTTP methods used in web services.
public enum HTTPRequestMethod: String {

    /// Requests data from a resource.
    case get = "GET"

    /// Submits data to a resource.
    case post = "POST"

    /// Replaces a resource or creates it.
    case put = "PUT"

    /// Deletes the specified resource.
    case delete = "DELETE"

    /// Partially updates a resource.
    case patch = "PATCH"

    /// Retrieves headers only.
    case head = "HEAD"

    /// Describes communication options.
    case options = "OPTIONS"

    /// Performs a diagnostic loop-back test.
    case trace = "TRACE"

    /// Establishes a tunnel to the server.
    case connect = "CONNECT"
}
