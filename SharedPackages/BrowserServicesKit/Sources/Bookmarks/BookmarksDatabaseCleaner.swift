//
//  BookmarksDatabaseCleaner.swift
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
import Combine
import Common
import CoreData
import Persistence
import os.log

public struct BookmarksCleanupError: Error {
    public let cleanupError: Error

    public static let syncActive: BookmarksCleanupError = .init(cleanupError: BookmarksCleanupCancelledError())
}

public struct BookmarksCleanupCancelledError: Error {}

public final class BookmarkDatabaseCleaner {

    public var isSyncActive: () -> Bool = { false }

    public init(
        bookmarkDatabase: CoreDataDatabase,
        errorEvents: EventMapping<BookmarksCleanupError>?,
        fetchBookmarksPendingDeletion: @escaping (NSManagedObjectContext) -> [BookmarkEntity] = BookmarkUtils.fetchBookmarksPendingDeletion
    ) {
        self.database = bookmarkDatabase
        self.errorEvents = errorEvents
        self.fetchBookmarksPendingDeletion = fetchBookmarksPendingDeletion

        cleanupCancellable = Publishers
            .Merge(
                externalTriggerSubject.map { false },
                scheduledTriggerSubject.map { true }
            )
            .receive(on: workQueue)
            .sink { [weak self] cancelIfActive in
                self?.removeBookmarksPendingDeletion(skipWhenSyncIsActive: cancelIfActive)
            }
    }

    public func scheduleRegularCleaning() {
        cancelCleaningSchedule()
        scheduleCleanupCancellable = Timer.publish(every: Const.cleanupInterval, on: .main, in: .default)
            .sink { [weak self] _ in
                self?.scheduledTriggerSubject.send()
            }
    }

    public func cancelCleaningSchedule() {
        scheduleCleanupCancellable?.cancel()
    }

    public func cleanUpDatabaseNow() {
        externalTriggerSubject.send()
    }

    func removeBookmarksPendingDeletion(skipWhenSyncIsActive: Bool = true) {
        if skipWhenSyncIsActive && isSyncActive() {
            errorEvents?.fire(.syncActive)
            return
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var saveAttemptsLeft = Const.maxContextSaveRetries

        context.performAndWait {
            var saveError: Error?

            while true {
                let bookmarksPendingDeletion = fetchBookmarksPendingDeletion(context)
                if bookmarksPendingDeletion.isEmpty {
                    Logger.bookmarks.debug("No bookmarks pending deletion")
                    break
                }

                for bookmark in bookmarksPendingDeletion {
                    context.delete(bookmark)
                }

                do {
                    try context.save()
                    Logger.bookmarks.debug("Successfully purged \(bookmarksPendingDeletion.count, privacy: .public) bookmarks")
                    break
                } catch {
                    if (error as NSError).code == NSManagedObjectMergeError {
                        context.reset()
                        saveAttemptsLeft -= 1
                        if saveAttemptsLeft == 0 {
                            saveError = error
                            break
                        }
                    } else {
                        saveError = error
                        break
                    }
                }
            }

            if let saveError {
                errorEvents?.fire(.init(cleanupError: saveError))
            }
        }
    }

    enum Const {
        static let cleanupInterval: TimeInterval = 24 * 3600
        static let maxContextSaveRetries = 5
    }

    private let errorEvents: EventMapping<BookmarksCleanupError>?
    private let database: CoreDataDatabase
    private let externalTriggerSubject = PassthroughSubject<Void, Never>()
    private let scheduledTriggerSubject = PassthroughSubject<Void, Never>()
    private let workQueue = DispatchQueue(label: "BookmarkDatabaseCleaner queue", qos: .userInitiated)

    private var cleanupCancellable: AnyCancellable?
    private var scheduleCleanupCancellable: AnyCancellable?
    private let fetchBookmarksPendingDeletion: (NSManagedObjectContext) -> [BookmarkEntity]
}
