//
//  ChromiumBookmarksReader.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit

final class ChromiumBookmarksReader {

    enum Constants {
        static let defaultBookmarksFileName = "Bookmarks"
        /// Chrome keeps the bookmarks of a profile signed in to a Google Account in this file,
        /// next to `Bookmarks` or instead of it.
        static let accountBookmarksFileName = "AccountBookmarks"
        static let bookmarksFileNames = [defaultBookmarksFileName, accountBookmarksFileName]
    }

    struct ImportError: DataImportError {
        enum OperationType: Int {
            case fileRead
            case decodeJson
        }

        var action: DataImportAction { .bookmarks }
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            switch type {
            case .fileRead: .noData
            case .decodeJson: .dataCorrupted
            }
        }
    }

    private let chromiumBookmarksFileURLs: [URL]

    init(chromiumDataDirectoryURL: URL, bookmarksFileNames: [String] = Constants.bookmarksFileNames) {
        self.chromiumBookmarksFileURLs = bookmarksFileNames.map { chromiumDataDirectoryURL.appendingPathComponent($0) }
    }

    /// Reads every bookmarks file and combines their roots, failing only when none of them can be read.
    func readBookmarks() -> DataImportResult<ImportedBookmarks> {
        let results = chromiumBookmarksFileURLs.map(readBookmarks(at:))
        let decodedBookmarks = results.compactMap { try? $0.get() }

        guard let firstBookmarks = decodedBookmarks.first else {
            let errors = results.compactMap { result -> ImportError? in
                guard case .failure(let error) = result else { return nil }
                return error
            }
            // A file that exists but can't be decoded says more than a missing one.
            return .failure(errors.first { $0.type == .decodeJson } ?? errors[0])
        }

        let mergedBookmarks = decodedBookmarks.dropFirst().reduce(firstBookmarks, mergeBookmarks)
        return .success(mergedBookmarks)
    }

    private func readBookmarks(at fileURL: URL) -> Result<ImportedBookmarks, ImportError> {
        var currentOperationType: ImportError.OperationType = .fileRead
        do {
            let bookmarksFileData = try Data(contentsOf: fileURL)
            currentOperationType = .decodeJson
            return .success(try JSONDecoder().decode(ImportedBookmarks.self, from: bookmarksFileData))
        } catch {
            return .failure(ImportError(type: currentOperationType, underlyingError: error))
        }
    }

    private func mergeBookmarks(_ first: ImportedBookmarks, _ second: ImportedBookmarks) -> ImportedBookmarks {
        ImportedBookmarks(topLevelFolders: .init(
            bookmarkBar: mergeFolders(first.topLevelFolders.bookmarkBar, second.topLevelFolders.bookmarkBar),
            otherBookmarks: mergeFolders(first.topLevelFolders.otherBookmarks, second.topLevelFolders.otherBookmarks),
            syncedBookmarks: mergeFolders(first.topLevelFolders.syncedBookmarks, second.topLevelFolders.syncedBookmarks)))
    }

    private func mergeFolders(_ first: ImportedBookmarks.BookmarkOrFolder?,
                              _ second: ImportedBookmarks.BookmarkOrFolder?) -> ImportedBookmarks.BookmarkOrFolder? {
        guard let first else { return second }
        guard let second else { return first }

        let combinedChildren = (first.children ?? []) + (second.children ?? [])
        return .folder(name: first.name, children: combinedChildren)
    }

}
