//
//  BookmarksDebugViewController.swift
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

import UIKit
import SwiftUI
import Core
import Combine
import Persistence
import Bookmarks
import CoreData

class BookmarksDebugViewController: UIHostingController<BookmarksDebugRootView> {

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: BookmarksDebugRootView())
    }

}

struct BookmarksDebugRootView: View {

    @StateObject private var model: BookmarksDebugViewModel
    @State private var showingDestructiveAlert = false
    @State private var showingConvertAlert = false

    init(bookmarksDatabase: CoreDataDatabase? = nil) {
        _model = StateObject(wrappedValue: bookmarksDatabase.map(BookmarksDebugViewModel.init(database:)) ?? BookmarksDebugViewModel())
    }

    @ViewBuilder func toolsSection() -> some View {
        Section {
            SettingsCellView(label: "Make Favorites", subtitle: "Convert all bookmarks to favorites. Restart the app after running this.", action: {
                showingConvertAlert = true
            }, isButton: true)
        } header: {
            Text(verbatim: "Tools")
        }
    }

    @ViewBuilder func itemsSection() -> some View {
        Section {
            ForEach(model.bookmarks, id: \.id) { entry in
                VStack(alignment: .leading) {
                    Text(entry.title ?? "empty!")
                        .font(.system(size: 16))
                    Text("Is unified fav: " + (entry.isFavorite(on: .unified) ? "true" : "false") )
                        .font(.system(size: 12))
                    Text("Is mobile fav: " + (entry.isFavorite(on: .mobile) ? "true" : "false") )
                        .font(.system(size: 12))
                    Text("Is desktop fav: " + (entry.isFavorite(on: .desktop) ? "true" : "false") )
                        .font(.system(size: 12))
                    ForEach(model.bookmarkAttributes, id: \.self) { attr in
                        Text(entry.formattedValue(for: attr))
                            .font(.system(size: 12))
                    }
                }
            }
        } header: {
            Text(verbatim: "Bookmarks")
        }
    }

    var body: some View {
        List {

            toolsSection()

            itemsSection()
        }
        .navigationTitle("\(model.bookmarks.count) Bookmarks")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingDestructiveAlert = true
                } label: {
                    Text(verbatim: "Delete All")
                }
                .accessibilityIdentifier("Debug.Bookmarks.DeleteAll")
            }
        }
        .alert(Text(verbatim: "Operation Complete"), isPresented: $model.showingOperationComplete) {
            Button(role: .cancel) {

            } label: {
                Text(verbatim: "Done")
            }
            .accessibilityIdentifier("Debug.Bookmarks.ResetComplete")
        } message: {
            Text(model.operationCompleteMessage)
        }
        .alert(Text(verbatim: "Confirm"), isPresented: $showingConvertAlert) {
            Button(role: .cancel) { } label: { Text(verbatim: "Cancel") }
            Button(role: .destructive) {
                model.convertAllBookmarksToFavorites()
            } label: {
                Text(verbatim: "Convert")
            }
        } message: {
            Text(verbatim: "Are you sure you want to convert all bookmarks to favorites?")
        }
        .alert(Text(verbatim: "Confirm Delete"), isPresented: $showingDestructiveAlert) {
            Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
            Button(role: .destructive) {
                model.deleteAll()
            } label: {
                Text(verbatim: "Delete")
            }
            .accessibilityIdentifier("Debug.Bookmarks.ConfirmDelete")
        } message: {
            Text(verbatim: "Are you sure you want to delete all bookmarks? This action cannot be undone.")
        }
    }

}

extension BookmarkEntity {

    func formattedValue(for key: String) -> String {
        key + ": \'" + String(describing: value(forKey: key)) + "'"
    }
}

class BookmarksDebugViewModel: ObservableObject {

    @Published var showingOperationComplete = false
    @Published var operationCompleteMessage = ""
    @Published var bookmarks = [BookmarkEntity]()
    let bookmarkAttributes: [String]

    let database: CoreDataDatabase
    let context: NSManagedObjectContext

    convenience init() {
        let database = BookmarksDatabase.make()
        database.loadStore()
        self.init(database: database)
    }

    init(database: CoreDataDatabase) {
        self.database = database

        context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        bookmarkAttributes = Array(BookmarkEntity.entity(in: context).attributesByName.keys)

        fetch()
    }

    func convertAllBookmarksToFavorites() {
        let fetchRequest = BookmarkEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(BookmarkEntity.title),
                                                         ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false
        let bookmarks = (try? context.fetch(fetchRequest)) ?? []
        bookmarks.forEach { bookmark in
            if !bookmark.isFolder {
                bookmark.addToFavorites(with: .displayNative(.mobile), in: context)
            }
        }

        do {
            try context.save()
            operationCompleteMessage = "Success - please restart the app"
        } catch {
            operationCompleteMessage = error.localizedDescription
            Logger.bookmarks.error("Error converting to bookmarks: \(error.localizedDescription, privacy: .public)")
        }
        showingOperationComplete = true
    }

    func fetch() {

        let fetchRequest = BookmarkEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(BookmarkEntity.title),
                                                         ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false
        bookmarks = (try? context.fetch(fetchRequest)) ?? []
    }

    func deleteAll() {
        deleteAllBookmarksAndFavorites { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success:
                    self.fetch()
                    self.operationCompleteMessage = "Bookmarks deleted"
                    self.showingOperationComplete = true
                case .failure(let error):
                    assertionFailure("Failed to delete bookmarks: \(error)")
                }
            }
        }
    }

    private func deleteAllBookmarksAndFavorites(completion: @escaping (Result<Void, Error>) -> Void) {
        context.perform { [weak self] in
            guard let context = self?.context else { return }

            let maximumAttempts = 2
            for attempt in 0..<maximumAttempts {
                do {
                    let fetchRequest = BookmarkEntity.fetchRequest()
                    let systemFolderIDs = BookmarkEntity.Constants.favoriteFoldersIDs
                        .union([BookmarkEntity.Constants.rootFolderID])
                    fetchRequest.predicate = NSPredicate(
                        format: "NOT %K IN %@",
                        #keyPath(BookmarkEntity.uuid),
                        systemFolderIDs)
                    try context.fetch(fetchRequest).forEach(context.delete)
                    try context.save()
                    completion(.success(()))
                    return
                } catch {
                    let error = error as NSError
                    let isMergeConflict = error.code == NSManagedObjectMergeError || error.code == NSManagedObjectConstraintMergeError
                    guard isMergeConflict, attempt + 1 < maximumAttempts else {
                        completion(.failure(error))
                        return
                    }
                    context.reset()
                }
            }
        }
    }

}
