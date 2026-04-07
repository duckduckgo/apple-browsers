//
//  ImportSourceDetailViewController.swift
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

import UIKit
import SwiftUI
import SafariServices
import BrowserServicesKit
import UniformTypeIdentifiers
import Core
import Common
import Bookmarks
import DDGSync
import Persistence
import PrivacyConfig
import os.log

final class ImportSourceDetailViewController: UIViewController {

    private let source: ImportPasswordSource
    private let syncService: DDGSyncing
    private let keyValueStore: ThrowingKeyValueStoring
    private let bookmarksDatabase: CoreDataDatabase
    private let favoritesDisplayMode: FavoritesDisplayMode
    private let tld: TLD

    private lazy var importManager: DataImportManaging = DataImportManager(
        reporter: SecureVaultReporter(),
        bookmarksDatabase: bookmarksDatabase,
        favoritesDisplayMode: favoritesDisplayMode,
        tld: tld)

    init(source: ImportPasswordSource,
         syncService: DDGSyncing,
         keyValueStore: ThrowingKeyValueStoring,
         bookmarksDatabase: CoreDataDatabase,
         favoritesDisplayMode: FavoritesDisplayMode,
         tld: TLD = AppDependencyProvider.shared.storageCache.tld) {
        self.source = source
        self.syncService = syncService
        self.keyValueStore = keyValueStore
        self.bookmarksDatabase = bookmarksDatabase
        self.favoritesDisplayMode = favoritesDisplayMode
        self.tld = tld
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = source.detailTitle
        setupView()
    }

    private func setupView() {
        let detailView = ImportSourceDetailView(
            source: source,
            onPrimaryAction: { [weak self] in
                self?.handlePrimaryAction()
            },
            onUploadFile: { [weak self] in
                self?.handleUploadFile()
            })
        let hostingController = UIHostingController(rootView: detailView)
        hostingController.view.backgroundColor = .clear
        installChildViewController(hostingController)
    }

    // MARK: - Primary Action

    private func handlePrimaryAction() {
        switch source {
        case .safari:
            presentSafariExportInterstitial()
        case .syncFromDuckDuckGo:
            break
        case .passwordsApp, .chrome:
            break
        }
    }

    private func presentSafariExportInterstitial() {
        let interstitialVC = SafariExportInterstitialViewController()
        interstitialVC.onRequestExport = { [weak self] in
            self?.triggerBrowserKitImport()
        }

        if let sheet = interstitialVC.sheetPresentationController {
            sheet.detents = [.medium()]
        }

        present(interstitialVC, animated: true)
    }

    private func triggerBrowserKitImport() {
#if compiler(>=6.3)
        if #available(iOS 26.4, *) {
            SFSafariSettings.openExportBrowsingDataSettings { _ in
                Logger.autofill.debug("Safari browsing data export settings opened.")
            }
        }
#endif
    }

    // MARK: - File Upload

    private func handleUploadFile() {
        let documentTypes: [UTType] = [.zip, .commaSeparatedText, .html]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: documentTypes, asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }

    private func processFile(at url: URL, type: DataImportFileType) {
        switch type {
        case .zip:
            processZipFile(at: url)
        default:
            importSingleFile(at: url, type: type)
        }
    }

    private func processZipFile(at url: URL) {
        Task { @MainActor in
            do {
                let contents = try ImportArchiveReader().readContents(from: url, featureFlagger: AppDependencyProvider.shared.featureFlagger)
                let dataTypes = DataImportManager.preview(contents: contents, tld: tld)
                    .filter { $0.count > 0 }
                    .map(\.type)

                guard !dataTypes.isEmpty else {
                    ActionMessageView.present(message: String(format: UserText.dataImportFailedReadErrorMessage, UserText.dataImportFileTypeZip))
                    return
                }

                if dataTypes.count == 1, let singleType = dataTypes.first {
                    let summary = await importManager.importZipArchive(from: contents, for: [singleType])
                    presentSummary(summary)
                } else {
                    presentZipContentPicker(contents: contents, dataTypes: dataTypes)
                }
            } catch {
                Logger.general.error("Failed to read ZIP archive: \(error)")
                ActionMessageView.present(message: String(format: UserText.dataImportFailedReadErrorMessage, UserText.dataImportFileTypeZip))
            }
        }
    }

    private func importSingleFile(at url: URL, type: DataImportFileType) {
        Task { @MainActor in
            do {
                if let summary = try await importManager.importFile(at: url, for: type) {
                    presentSummary(summary)
                }
            } catch {
                Logger.general.error("Failed to import file: \(error)")
                let fileTypeName: String
                switch type {
                case .csv: fileTypeName = UserText.dataImportFileTypeCsv
                case .html: fileTypeName = UserText.dataImportFileTypeHtml
                case .zip: fileTypeName = UserText.dataImportFileTypeZip
                case .json: fileTypeName = UserText.dataImportFileTypeCsv
                }
                ActionMessageView.present(message: String(format: UserText.dataImportFailedReadErrorMessage, fileTypeName))
            }
        }
    }

    private func presentZipContentPicker(contents: ImportArchiveContents, dataTypes: [DataImport.DataType]) {
        let zipVC = ZipContentSelectionViewController(
            DataImportManager.preview(contents: contents, tld: tld),
            importScreen: .passwords
        ) { [weak self] selectedTypes in
            guard let self else { return }
            Task { @MainActor in
                let summary = await self.importManager.importZipArchive(from: contents, for: selectedTypes)
                self.presentSummary(summary)
            }
        }

        if let presentationController = zipVC.presentationController as? UISheetPresentationController {
            if #available(iOS 16.0, *) {
                presentationController.detents = [.custom(resolver: { _ in 360.0 })]
            } else {
                presentationController.detents = [.medium()]
            }
        }

        present(zipVC, animated: true)
    }

    // MARK: - Summary

    private func presentSummary(_ summary: DataImportSummary) {
        AutofillLoginImportState(keyValueStore: keyValueStore).hasImportedLogins = true

        let summaryVC = DataImportSummaryViewController(summary: summary, importScreen: .passwords, syncService: syncService) { [weak self] syncSource in
            guard let self else { return }
            let mainVC = self.navigationController?.presentingViewController as? MainViewController
                ?? self.presentingViewController as? MainViewController
            mainVC?.dismiss(animated: true) {
                mainVC?.segueToSettingsSync(with: syncSource)
            }
        } onCompletion: { [weak self] in
            self?.navigationController?.popToRootViewController(animated: true)
        }

        present(summaryVC, animated: true)
    }
}

// MARK: - UIDocumentPickerDelegate

extension ImportSourceDetailViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedFileURL = urls.first else { return }

        do {
            let resourceValues = try selectedFileURL.resourceValues(forKeys: [.typeIdentifierKey])
            guard let typeIdentifier = resourceValues.typeIdentifier,
                  let fileType = DataImportFileType(typeIdentifier: typeIdentifier) else {
                ActionMessageView.present(message: UserText.dataImportFailedUnsupportedFileErrorMessage)
                return
            }
            processFile(at: selectedFileURL, type: fileType)
        } catch {
            Logger.autofill.error("Failed to determine file type: \(error)")
            ActionMessageView.present(message: UserText.dataImportFailedUnsupportedFileErrorMessage)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // No-op; user dismissed the picker
    }
}
