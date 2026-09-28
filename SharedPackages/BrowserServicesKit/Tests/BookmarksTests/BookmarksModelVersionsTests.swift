//
//  BookmarksModelVersionsTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import CoreData
import Persistence
import XCTest
@testable import Bookmarks

/// Entity version hashes of every shipped schema version, as compiled by `momc` from the former
/// `BookmarksModel.xcdatamodeld`. A mismatch means a shipped version was changed and existing stores
/// would no longer match it — add a new version instead.
final class BookmarksModelVersionsTests: XCTestCase {

    func testEveryVersionMatchesShippedVersionHashes() {
        let expected = [
            "w3rZsxoc4/ryWBZERHF6cwMX3uBO+kGR0xCG0hefnCA=",
            "mdZQkw9+SEQQIH/u3RKbQvXnrP+Dq2qb9huabYi904I=",
            "aYt2S+tyoryQIXq5pnDZDZzhZjtxwV9nXMv7Ruf/dqU=",
            "aghslUTArcZnTjexos1Lx+3NlN4iTGH8YDhkhEy1+PY=",
            "hPB8BH05EI1mbfnQivcosxlzg72mmP6/O5CZfbT9WSk=",
            "Quf/0Veorgn141DBxufsMhpB6TCps849R2Hc+UeF+5w=",
        ]
        let versions = [BookmarksModel.v1, BookmarksModel.v2, BookmarksModel.v3, BookmarksModel.v4, BookmarksModel.v5, BookmarksModel.v6]

        for (index, (version, hash)) in zip(versions, expected).enumerated() {
            let model = NSManagedObjectModel(entities: version())
            XCTAssertEqual(model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }, ["BookmarkEntity": hash],
                           "BookmarksModel v\(index + 1)")
        }
    }

    func testCurrentModelIsLatestVersionBoundToManagedObjectSubclass() {
        let current = VersionedManagedObjectModel.bookmarks.current

        XCTAssertEqual(current.entityVersionHashesByName, NSManagedObjectModel(entities: BookmarksModel.v6()).entityVersionHashesByName)
        XCTAssertEqual(current.entitiesByName["BookmarkEntity"]?.managedObjectClassName, NSStringFromClass(BookmarkEntity.self))
    }
}
