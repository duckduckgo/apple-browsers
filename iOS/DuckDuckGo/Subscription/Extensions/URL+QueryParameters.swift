//
//  URL+QueryParameters.swift
//  DuckDuckGo
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

extension URL {
    
    enum QueryParameterKeys {
        static let preventBackNavigation = "preventBackNavigation"
    }
    
    enum QueryParameterValues {
        static let trueValue = "true"
    }
    
    /// Checks if the URL contains a specific query parameter with the given name and value.
    func hasQueryParameter(name: String, value: String) -> Bool {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return false
        }
        
        return queryItems.contains { $0.name == name && $0.value == value }
    }
    
    /// Returns true if the URL contains the query parameter `preventBackNavigation=true`.
    var shouldPreventBackNavigation: Bool {
        return hasQueryParameter(name: QueryParameterKeys.preventBackNavigation,
                                value: QueryParameterValues.trueValue)
    }
}
