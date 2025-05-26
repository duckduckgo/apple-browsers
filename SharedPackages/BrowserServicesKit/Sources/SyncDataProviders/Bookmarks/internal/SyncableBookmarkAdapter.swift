//
//  SyncableBookmarkAdapter.swift
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

import Bookmarks
import DDGSync
import Foundation

struct SyncableBookmarkAdapter {

    let syncable: Syncable

    init(syncable: Syncable) {
        self.syncable = syncable
    }

    var uuid: String? {
        syncable.payload["id"] as? String
    }

    var isDeleted: Bool {
        syncable.isDeleted
    }

    var encryptedTitle: String? {
        syncable.payload["title"] as? String
    }

    var encryptedUrl: String? {
        let page = syncable.payload["page"] as? [String: Any]
        return page?["url"] as? String
    }

    var isFolder: Bool {
        syncable.payload["folder"] != nil
    }

    var children: [String] {
        guard let folder = syncable.payload["folder"] as? [String: Any] else {
            return []
        }

        if let folderChildrenDictionary = folder["children"] as? [String: Any],
           let currentChildren = folderChildrenDictionary["current"] as? [String] {

            return currentChildren

        } else if let children = folder["children"] as? [String] {
            return children
        }

        return []
    }
}

extension Syncable {

    enum SyncableBookmarkError: Error {
        case validationFailed
        case bookmarkEntityMissingUUID
    }

    enum BookmarkValidationConstraints {
        static let maxFolderTitleLength = 2000
        static let maxEncryptedBookmarkTitleLength = 3000
        static let maxEncryptedBookmarkURLLength = 3000
    }

    // swiftlint:disable:next cyclomatic_complexity
    init(bookmark: BookmarkEntity, encryptedUsing encrypt: (String) throws -> String) throws {
        var payload: [String: Any] = [:]
        guard let uuid = bookmark.uuid else {
            throw SyncableBookmarkError.bookmarkEntityMissingUUID
        }

        payload["id"] = uuid

        if bookmark.isPendingDeletion {
            payload["deleted"] = ""
        } else {
            if bookmark.isFolder {
                if let title = bookmark.title {
                    payload["title"] = try encrypt(String(title.prefix(BookmarkValidationConstraints.maxFolderTitleLength)))
                }

                let children: [String] = {
                    let allChildren: [BookmarkEntity]
                    if BookmarkEntity.Constants.favoriteFoldersIDs.contains(uuid) {
                        allChildren = bookmark.favorites?.array as? [BookmarkEntity] ?? []
                    } else {
                        allChildren = bookmark.children?.array as? [BookmarkEntity] ?? []
                    }
                    return allChildren.filter { $0.isPendingDeletion == false }.compactMap(\.uuid)
                }()

                let lastReceivedChildren = bookmark.lastChildrenArrayReceivedFromSync ?? []
                let insert = Array(Set(children).subtracting(lastReceivedChildren))
                let remove = Array(Set(lastReceivedChildren).subtracting(children))

                var childrenDict = [String: [String]]()
                childrenDict["current"] = children
                if !insert.isEmpty {
                    childrenDict["insert"] = insert
                }
                if !remove.isEmpty {
                    childrenDict["remove"] = remove
                }

                payload["folder"] = ["children": childrenDict]
            } else {

                if let title = bookmark.title {
                    let encryptedTitle = try encrypt(title)
                    guard encryptedTitle.count <= BookmarkValidationConstraints.maxEncryptedBookmarkTitleLength else {
                        throw SyncableBookmarkError.validationFailed
                    }
                    payload["title"] = encryptedTitle
                }
                if let url = bookmark.url {
                    let encryptedURL = try encrypt(url)
                    guard encryptedURL.count <= BookmarkValidationConstraints.maxEncryptedBookmarkURLLength else {
                        throw SyncableBookmarkError.validationFailed
                    }
                    payload["page"] = ["url": encryptedURL]
                }
            }
            if let modifiedAt = bookmark.modifiedAt {
                payload["client_last_modified"] = Self.dateFormatter.string(from: modifiedAt)
            }
        }
        self.init(jsonObject: payload)
    }

    private static var dateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }

}
