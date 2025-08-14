//
//  PersistentStoresConfiguration.swift
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
import Core
import Persistence

enum DatabaseError {

    case container(Error)
    case other(Error)

}

final class PersistentStoresConfiguration {

    let database = Database.shared
    let bookmarksDatabase = BookmarksDatabase.make()
    private let application: UIApplication

    init(application: UIApplication = .shared) {
        self.application = application
    }

    func configure() throws {
        try loadDatabase()
        try loadAndMigrateBookmarksDatabase()
    }

    private func loadDatabase() throws {
        var dbError: Error?
        database.loadStore { _, error in
            dbError = error
        }
        if let dbError {
            if let containerError = dbError as? CoreDataDatabase.Error,
               case .containerLocationCouldNotBePrepared(let underlyingError) = containerError {
                throw TerminationError.database(.container(underlyingError))
            } else {
                throw TerminationError.database(.other(dbError))
            }
        }
    }

    private func loadAndMigrateBookmarksDatabase() throws {
        let result = BookmarksDatabaseSetup().loadStoreAndMigrate(bookmarksDatabase: bookmarksDatabase)
        if case .failure(let error) = result {
            throw TerminationError.bookmarksDatabase(error)
        }
    }

}
