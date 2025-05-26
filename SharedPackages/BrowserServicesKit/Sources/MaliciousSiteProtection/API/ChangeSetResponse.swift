//
//  ChangeSetResponse.swift
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

extension APIClient {

    public struct ChangeSetResponse<T: Codable & Hashable>: Codable, Equatable {
        let insert: [T]
        let delete: [T]
        let revision: Int
        let replace: Bool

        public init(insert: [T], delete: [T], revision: Int, replace: Bool) {
            self.insert = insert
            self.delete = delete
            self.revision = revision
            self.replace = replace
        }

        public var isEmpty: Bool {
            insert.isEmpty && delete.isEmpty
        }
    }

    public enum Response {
        public typealias FiltersChangeSet = ChangeSetResponse<Filter>
        public typealias HashPrefixesChangeSet = ChangeSetResponse<String>
        public typealias Matches = MatchResponse
    }

}
