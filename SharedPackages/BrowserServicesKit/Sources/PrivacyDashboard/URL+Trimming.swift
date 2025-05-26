//
//  URL+Trimming.swift
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

extension URL {

    /// To limit privacy risk, site URL is trimmed to not include query and fragment
    /// - Returns: The original URL without query items and fragment
    public func trimmingQueryItemsAndFragment() -> URL {

        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return self
        }
        components.queryItems = nil
        components.fragment = nil

        guard let result = components.url else {
            return self
        }
        return result
    }

    /// To limit privacy risk, site URL is trimmed to include only schema, subdomain and domain
    /// - Returns: The original URL without query items, fragment and path
    public func privacySanitised() -> URL {

        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return self
        }
        components.queryItems = nil
        components.fragment = nil
        components.path = ""

        guard let result = components.url else {
            return self
        }
        return result
    }

}
