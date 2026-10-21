//
//  FavoritesDebugView.swift
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

import SwiftUI
import Bookmarks
import CoreData
import Persistence
import Combine

struct FavoritesDebugView: View {

    @StateObject private var model: FavoritesDebugViewModel
    @State private var customCount = "5"
    @State private var showingRemoveConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""

    init(bookmarksDatabase: CoreDataDatabase, favoritesDisplayMode: FavoritesDisplayMode) {
        _model = StateObject(wrappedValue: FavoritesDebugViewModel(bookmarksDatabase: bookmarksDatabase,
                                                                 favoritesDisplayMode: favoritesDisplayMode))
    }

    var body: some View {
        List {
            Section {
                Button("Add 5 Favorites") {
                    perform { try model.addFavorites(count: 5) }
                }
                Button("Add 30 Favorites") {
                    perform { try model.addFavorites(count: 30) }
                }
                TextField("Number of favorites", text: $customCount)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Number of favorites")
                Button("Add Custom Count") {
                    guard let count = Int(customCount) else { return }
                    perform { try model.addFavorites(count: count) }
                }
                .disabled(!FavoritesDebugViewModel.allowedCounts.contains(Int(customCount) ?? 0))
            } header: {
                Text("Add Favorites")
            } footer: {
                Text("Adds example.com bookmarks to your current favorites. Enter a count from 1 to 1,000. Changes can sync to your other devices.")
            }

            Section {
                Button("Remove All Favorites", role: .destructive) {
                    showingRemoveConfirmation = true
                }
                .disabled(model.favoritesCount == 0)
            } footer: {
                Text("Removes favorite status from all favorites in your current display mode. Bookmarks are kept.")
            }
        }
        .navigationTitle("\(model.favoritesCount) Favorites")
        .alert("Remove All Favorites?", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove All", role: .destructive) {
                perform { try model.removeAllFavorites() }
            }
        } message: {
            Text("Bookmarks will be kept. This change can sync to your other devices.")
        }
        .alert("Favorites Update Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

@MainActor
final class FavoritesDebugViewModel: ObservableObject {

    static let allowedCounts = 1...1_000

    @Published private(set) var favoritesCount: Int

    private let context: NSManagedObjectContext
    private let favoritesDisplayMode: FavoritesDisplayMode
    private var saveObserver: AnyCancellable?

    init(bookmarksDatabase: CoreDataDatabase, favoritesDisplayMode: FavoritesDisplayMode) {
        context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
        self.favoritesDisplayMode = favoritesDisplayMode
        favoritesCount = BookmarkUtils.numberOfFavorites(for: favoritesDisplayMode, in: context)
        saveObserver = NotificationCenter.default.publisher(for: NSManagedObjectContext.didSaveObjectsNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let otherContext = notification.object as? NSManagedObjectContext,
                      otherContext != context,
                      otherContext.persistentStoreCoordinator == context.persistentStoreCoordinator else { return }
                context.mergeChanges(fromContextDidSave: notification)
                context.refreshAllObjects()
                favoritesCount = BookmarkUtils.numberOfFavorites(for: favoritesDisplayMode, in: context)
            }
    }

    func addFavorites(count: Int) throws {
        guard Self.allowedCounts.contains(count) else {
            throw OperationError.invalidCount
        }

        try saveChanges {
            guard let root = BookmarkUtils.fetchRootFolder(context) else {
                throw OperationError.missingFolders
            }
            let folders = BookmarkUtils.fetchFavoritesFolders(for: favoritesDisplayMode, in: context)
            guard folders.count == 2 else {
                throw OperationError.missingFolders
            }

            let batchID = UUID().uuidString
            for index in 1...count {
                let bookmark = BookmarkEntity.makeBookmark(title: "Test Favorite \(index)",
                                                           url: "https://example.com/favorites-debug/\(batchID)/\(index)",
                                                           parent: root,
                                                           context: context)
                bookmark.addToFavorites(folders: folders)
            }
        }
    }

    func removeAllFavorites() throws {
        try saveChanges {
            guard let folder = BookmarkUtils.fetchFavoritesFolder(withUUID: favoritesDisplayMode.displayedFolder.rawValue, in: context) else {
                throw OperationError.missingFolders
            }
            for favorite in folder.favoritesArray {
                favorite.removeFromFavorites(with: favoritesDisplayMode)
            }
        }
    }

    private func saveChanges(_ changes: () throws -> Void) throws {
        do {
            try changes()
            try context.save()
            favoritesCount = BookmarkUtils.numberOfFavorites(for: favoritesDisplayMode, in: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private enum OperationError: LocalizedError {
        case invalidCount
        case missingFolders

        var errorDescription: String? {
            switch self {
            case .invalidCount:
                return "Enter a count from 1 to 1,000."
            case .missingFolders:
                return "The bookmarks or favorites folders could not be loaded."
            }
        }
    }
}
