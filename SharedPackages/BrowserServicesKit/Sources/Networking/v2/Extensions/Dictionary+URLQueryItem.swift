//
//  Dictionary+URLQueryItem.swift
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
import Common

extension Dictionary where Key == String, Value == String {

    /// Convert a Dictionary key:String, value:String into an array of URLQueryItem ordering alphabetically the items by key
    /// - Returns: An ordered array of URLQueryItem
    public func toURLQueryItems(allowedReservedCharacters: CharacterSet? = nil) -> [URLQueryItem] {
        return self.sorted(by: <).map {
            if let allowedReservedCharacters {
                URLQueryItem(percentEncodingName: $0.key,
                             value: $0.value,
                             withAllowedCharacters: allowedReservedCharacters)
            } else {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        }
    }
}
