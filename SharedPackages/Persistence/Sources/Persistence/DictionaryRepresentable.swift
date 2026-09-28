//
//  DictionaryRepresentable.swift
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

/// Something that can be represented as a Dictionary
public protocol DictionaryRepresentable {

    /// Convenience method to return a Dictionary representation of this metadata.
    /// - Returns: A Dictionary object containing the object representation
    func dictionaryRepresentation() -> [String: Any]
}

extension UserDefaults: DictionaryRepresentable { }
