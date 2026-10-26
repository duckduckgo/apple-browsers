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

        return .success(decodedBookmarks.dropFirst().reduce(firstBookmarks) { $0.merging($1) })
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

}

private extension ImportedBookmarks {

    func merging(_ other: ImportedBookmarks) -> ImportedBookmarks {
        ImportedBookmarks(topLevelFolders: TopLevelFolders(
            bookmarkBar: topLevelFolders.bookmarkBar.merging(other.topLevelFolders.bookmarkBar),
            otherBookmarks: topLevelFolders.otherBookmarks.merging(other.topLevelFolders.otherBookmarks),
            syncedBookmarks: topLevelFolders.syncedBookmarks.merging(other.topLevelFolders.syncedBookmarks)
        ))
    }

}

private extension Optional where Wrapped == ImportedBookmarks.BookmarkOrFolder {

    func merging(_ other: ImportedBookmarks.BookmarkOrFolder?) -> ImportedBookmarks.BookmarkOrFolder? {
        guard let self, let other else { return self ?? other }
        return .folder(name: self.name, children: (self.children ?? []) + (other.children ?? []))
    }

}
