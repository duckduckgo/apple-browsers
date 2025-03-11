//
//  UserDefaultsBookmarkFoldersStore.swift
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
import Persistence

/// A type used to provide the IDs of folders used for saving bookmarks.
protocol BookmarkFoldersStore: AnyObject {
    /// The ID of the folder where all bookmarks from the last session were saved.
    var lastBookmarkAllTabsFolderIdUsed: String? { get set }
    /// The ID of the folder where a single bookmark was last saved.
    var lastBookmarkSingleTabFolderIdUsed: String? { get set }
}

final class UserDefaultsBookmarkFoldersStore: BookmarkFoldersStore {

    enum Keys {
        static let bookmarkAllTabsFolderUsedKey = "bookmarks.all-tabs.last-used-folder"
        static let bookmarkSingleTabFolderUsedKey = "bookmarks.single-tab.last-used-folder"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var lastBookmarkAllTabsFolderIdUsed: String? {
        get { keyValueStore.object(forKey: Keys.bookmarkAllTabsFolderUsedKey) as? String }
        set { keyValueStore.set(newValue, forKey: Keys.bookmarkAllTabsFolderUsedKey) }
    }

    var lastBookmarkSingleTabFolderIdUsed: String? {
        get { keyValueStore.object(forKey: Keys.bookmarkSingleTabFolderUsedKey) as? String }
        set { keyValueStore.set(newValue, forKey: Keys.bookmarkSingleTabFolderUsedKey) }
    }
}
