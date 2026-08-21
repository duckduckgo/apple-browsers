//
//  DictionaryExtension.swift
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

public extension Dictionary where Key: Comparable {
    func toString(pairSeparator: String = ":", entrySeparator: String = ",") -> String {
        sorted(by: { $0.key < $1.key })
            .map { "\($0.key)\(pairSeparator)\($0.value)" }
            .joined(separator: entrySeparator)
    }
}
