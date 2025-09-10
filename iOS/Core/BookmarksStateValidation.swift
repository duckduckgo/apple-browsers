//
//  BookmarksStateValidation.swift
//  DuckDuckGo
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
import CoreData
import Bookmarks
import Persistence

private extension BoolFileMarker.Name {
    static let hasSuccessfullyLaunchedBefore = BoolFileMarker.Name(rawValue: "app-launched-successfully")
}

public protocol BookmarksStateValidation {

    func validateInitialState(context: NSManagedObjectContext,
                              validationError: BookmarksStateValidator.ValidationError) -> Bool

    func validateBookmarksStructure(context: NSManagedObjectContext)
}

public class BookmarksStateValidator: BookmarksStateValidation {

    enum Constants {
        static let bookmarksDBIsInitialized = "bookmarksDBIsInitialized"
    }

    public enum ValidationError {
        case bookmarksStructureLost
        case bookmarksStructureNotRecovered
        case bookmarksStructureBroken
        case validatorError(Error)
    }

    let keyValueStore: KeyValueStoring
    let isSyncEnabled: Bool
    let errorHandler: (ValidationError, [String: String]?) -> Void

    public init(keyValueStore: KeyValueStoring,
                isSyncEnabled: Bool = false,
                errorHandler: @escaping (ValidationError, [String: String]?) -> Void) {
        self.keyValueStore = keyValueStore
        self.isSyncEnabled = isSyncEnabled
        self.errorHandler = errorHandler
    }

    public func validateInitialState(context: NSManagedObjectContext,
                                     validationError: ValidationError) -> Bool {
        guard keyValueStore.object(forKey: Constants.bookmarksDBIsInitialized) != nil else { return true }

        let fetch = BookmarkEntity.fetchRequest()
        do {
            let count = try context.count(for: fetch)
            if count == 0 {
                switch validationError {
                case .bookmarksStructureLost:
                    errorHandler(.bookmarksStructureLost, generateDiagnosticParameters())
                default:
                    errorHandler(validationError, nil)
                }
                return false
            }
        } catch {
            errorHandler(.validatorError(error), nil)
        }

        return true
    }

    public func validateBookmarksStructure(context: NSManagedObjectContext) {
        let isMarkedAsInitialized = keyValueStore.object(forKey: Constants.bookmarksDBIsInitialized) != nil
        if isMarkedAsInitialized == false {
            keyValueStore.set(true, forKey: Constants.bookmarksDBIsInitialized)
        }

        let rootUUIDs = [BookmarkEntity.Constants.rootFolderID,
                         FavoritesFolderID.unified.rawValue,
                         FavoritesFolderID.mobile.rawValue,
                         FavoritesFolderID.desktop.rawValue]

        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@", #keyPath(BookmarkEntity.uuid), rootUUIDs)

        do {
            let roots = try context.fetch(request)
            if roots.count != rootUUIDs.count {
                var additionalParams = [String: String]()

                for uuid in rootUUIDs {
                    additionalParams[uuid] = "\(roots.filter({ $0.uuid == uuid }).count)"
                }

                additionalParams["is-marked-as-initialized"] = isMarkedAsInitialized ? "true" : "false"

                errorHandler(.bookmarksStructureBroken, additionalParams)
            }
        } catch {
            errorHandler(.validatorError(error), nil)
        }
    }
    
    private func generateDiagnosticParameters() -> [String: String] {
        var params = [String: String]()
        
        params["sync-enabled"] = "\(isSyncEnabled)"

        // Add recent bookmark error information
        if let recentBookmarkError = getRecentBookmarkError() {
            params["recent-bookmark-error-name"] = recentBookmarkError.name
            params["recent-bookmark-error-domain"] = recentBookmarkError.domain
            params["recent-bookmark-error-code"] = "\(recentBookmarkError.code)"
        }
        
        // Check if launch marker file exists (helps distinguish restore vs corruption)
        params["launch-marker-present"] = "\(hasLaunchedSuccessfullyBefore)"
        
        return params
    }
    
    // MARK: - Diagnostic Helper Methods
        
    private var hasLaunchedSuccessfullyBefore: Bool {
        guard let marker = BoolFileMarker(name: .hasSuccessfullyLaunchedBefore) else {
            return false
        }
        return marker.isPresent
    }

    private func getRecentBookmarkError() -> (name: String, domain: String, code: Int)? {
        let bookmarkErrorKey = "BookmarksValidator.lastBookmarkError"
        let maxAgeSeconds: TimeInterval = 24 * 60 * 60 // 1 day

        // Check UserDefaults for bookmark error
        guard let errorInfo = UserDefaults.app.object(forKey: bookmarkErrorKey) as? [String: Any],
              let timestamp = errorInfo["timestamp"] as? Date,
              let name = errorInfo["bookmarkError"] as? String,
              let domain = errorInfo["domain"] as? String,
              let code = errorInfo["code"] as? Int else {
            return nil
        }

        // Check if error is recent (within 1 day)
        let secondsSinceError = Date().timeIntervalSince(timestamp)
        guard secondsSinceError <= maxAgeSeconds else {
            return nil
        }

        return (name: name, domain: domain, code: code)
    }

}
