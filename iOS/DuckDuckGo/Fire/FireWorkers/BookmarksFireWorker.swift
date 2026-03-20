//
//  BookmarksFireWorker.swift
//  DuckDuckGo
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

import DDGSync
import Bookmarks

struct BookmarksFireWorker: FireExecutorWorker {

    private let syncService: DDGSyncing
    private weak var bookmarksDatabaseCleaner: BookmarkDatabaseCleaning?
    private let dataClearingWideEventService: DataClearingWideEventService?

    init(syncService: DDGSyncing,
         bookmarksDatabaseCleaner: BookmarkDatabaseCleaning?,
         dataClearingWideEventService: DataClearingWideEventService?) {
        self.syncService = syncService
        self.bookmarksDatabaseCleaner = bookmarksDatabaseCleaner
        self.dataClearingWideEventService = dataClearingWideEventService
    }

    @MainActor
    func burnNormalModeData() async {
        if syncService.authState == .inactive {
            dataClearingWideEventService?.start(.clearBookmarkDatabase)
            bookmarksDatabaseCleaner?.cleanUpDatabaseNow()
            dataClearingWideEventService?.update(.clearBookmarkDatabase, result: .success(()))
        }
    }

    @MainActor
    func burnFireModeData() async {
        // Bookmark database cleanup is a global maintenance task, not scoped to browsing mode
    }

    @MainActor
    func burnTabData(tabViewModel: TabViewModel, domains: [String]) async {
        // Bookmark database cleanup is a global maintenance task, not scoped to individual tabs
    }
}
