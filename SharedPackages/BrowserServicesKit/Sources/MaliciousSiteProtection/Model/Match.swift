//
//  Match.swift
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

public struct Match: Codable, Hashable {
    var hostname: String
    var url: String
    var regex: String
    var hash: String
    let category: String?

    public init(hostname: String, url: String, regex: String, hash: String, category: String?) {
        self.hostname = hostname
        self.url = url
        self.regex = regex
        self.hash = hash
        self.category = category
    }
}
