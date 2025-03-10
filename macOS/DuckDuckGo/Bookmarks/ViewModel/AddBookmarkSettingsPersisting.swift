//
//  AddBookmarkSettingsPersisting.swift
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
import Persistence

protocol AddBookmarkSettingsPersisting: AnyObject {
    var lastUsedFolderID: String? { get set }
}

final class UserDefaultsAddBookmarkSettingsPersistor: AddBookmarkSettingsPersisting {
    enum Keys {
        static let lastUsedFolderID = "add-bookmark.last-used-folder-id"
    }

    init(_ keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var lastUsedFolderID: String? {
        get { return keyValueStore.object(forKey: Keys.lastUsedFolderID) as? String }
        set { keyValueStore.set(newValue, forKey: Keys.lastUsedFolderID) }
    }

    private let keyValueStore: KeyValueStoring
}
