//
//  QueryItems.swift
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
import Common

public typealias QueryItem = Dictionary<String, String>.Element
public typealias QueryItems = [QueryItem]

extension QueryItems {

    public func toURLQueryItems(allowedReservedCharacters: CharacterSet? = nil) -> [URLQueryItem] {
        return self.map {
            if let allowedReservedCharacters {
                return URLQueryItem(percentEncodingName: $0.key,
                                    value: $0.value,
                             withAllowedCharacters: allowedReservedCharacters)
            } else {
                return URLQueryItem(name: $0.key, value: $0.value)
            }
        }
    }
}
