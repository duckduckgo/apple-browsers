//
//  BookmarksFileFlow.swift
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

import Bookmarks
import Core
import Persistence
import PixelKit
import UIKit
import UniformTypeIdentifiers
import WidgetKit
import os.log

@MainActor
final class BookmarksFileFlow: NSObject {
    private enum Constants {
        static let saveToFiles = "com.apple.DocumentManagerUICore.SaveToFiles"
        static let bookmarksFileName = "DuckDuckGo Bookmarks.html"
    }

    private let bookmarksDatabase: CoreDataDatabase
    private let appSettings: AppSettings

    init(bookmarksDatabase: CoreDataDatabase, appSettings: AppSettings) {
        self.bookmarksDatabase = bookmarksDatabase
        self.appSettings = appSettings
    }

    func presentDocumentPicker(from presenter: UIViewController) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.html], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }

    func importBookmarks(fromHtml html: String) {
        Task {

            let result = await BookmarksImporter(coreDataStore: bookmarksDatabase,
                                                 favoritesDisplayMode: self.appSettings.favoritesDisplayMode,
                                                 htmlContent: html)
                .parseAndSave()

            switch result {
            case .success(let summary):
                WidgetCenter.shared.reloadAllTimelines()
                DispatchQueue.main.async {
                    PixelKit.fire(Pixel.Event.bookmarkImportSuccess,
                                  options: .parameters([PixelParameters.bookmarkCount: "\(summary.successful)"]))
                    ActionMessageView.present(message: UserText.importBookmarksSuccessMessage)
                }
            case .failure(let bookmarksImportError):
                Logger.bookmarks.error("Bookmarks import error \(bookmarksImportError.localizedDescription, privacy: .public)")
                PixelKit.fire(Pixel.Event.bookmarkImportFailure)
                DispatchQueue.main.async {
                    ActionMessageView.present(message: UserText.importBookmarksFailedMessage)
                }
            }
        }
    }

    func exportHtmlFile(from presenter: UIViewController, anchor: UIView) {
        let tempFileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(Constants.bookmarksFileName)
        do {
            try BookmarksExporter(coreDataStore: bookmarksDatabase, favoritesDisplayMode: appSettings.favoritesDisplayMode)
                .exportBookmarksTo(url: tempFileUrl)
        } catch {
            Logger.general.error("bookmarks failed to export: \(error.localizedDescription, privacy: .public)")
            ActionMessageView.present(message: UserText.exportBookmarksFailedMessage)
            return
        }

        let activity = UIActivityViewController(activityItems: [tempFileUrl], applicationActivities: nil)
        activity.completionWithItemsHandler = {[weak self] (activityType: UIActivity.ActivityType?, completed: Bool, _: [Any]?, error: Error?) in
            guard error == nil else {
                // Save to Files can be cancelled while the share sheet remains open and still needs the file.
                if let error = error as NSError?, error.code == NSUserCancelledError {
                    return
                }

                PixelKit.fire(Pixel.Event.bookmarkExportFailure)
                self?.presentActionMessageView(withMessage: UserText.exportBookmarksFailedMessage)
                self?.cleanupTempFile(tempFileUrl)
                return
            }

            if completed && activityType != nil {
                if let activityTypeStr = activityType?.rawValue, activityTypeStr == Constants.saveToFiles {
                    self?.presentActionMessageView(withMessage: UserText.exportBookmarksFilesSuccessMessage)
                } else {
                    self?.presentActionMessageView(withMessage: UserText.exportBookmarksShareSuccessMessage)
                }
                PixelKit.fire(Pixel.Event.bookmarkExportSuccess)
            }

            self?.cleanupTempFile(tempFileUrl)
        }

        if let popover = activity.popoverPresentationController {
            popover.sourceView = anchor
        }
        presenter.present(activity, animated: true, completion: nil)
    }

    func cleanupTempFile(_ tempFileUrl: URL) {
        try? FileManager.default.removeItem(at: tempFileUrl)
    }

    func presentActionMessageView(withMessage message: String) {
        DispatchQueue.main.async {
            ActionMessageView.present(message: message)
        }
    }

}

extension BookmarksFileFlow: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let data = try? Data(contentsOf: url), let contents = String(data: data, encoding: .utf8) else {
            ActionMessageView.present(message: UserText.importBookmarksFailedMessage)
            return
        }
        importBookmarks(fromHtml: contents)
    }
}
