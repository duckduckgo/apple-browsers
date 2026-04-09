//
//  DataImportFileUploadCoordinator.swift
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
import Bookmarks
import BrowserServicesKit
import Common
import Core
import UniformTypeIdentifiers
import DDGSync
import Persistence
import PrivacyConfig
import os.log

protocol DataImportFileUploadFlowOwner: AnyObject {
    func dataImportUploadDidCompleteSummary()
    func dataImportUploadDidRequestSync(source: String?)
    func dataImportUploadDidCancel()
}

protocol DataImportFileUploadCoordinating: AnyObject {
    func startUploadFlow(from owner: UIViewController & DataImportFileUploadFlowOwner)
}

final class DataImportFileUploadCoordinator: NSObject {

    private weak var presentingViewController: UIViewController?
    private weak var flowOwner: DataImportFileUploadFlowOwner?
    private let viewModel: DataImportViewModel
    private let importScreen: DataImportViewModel.ImportScreen
    private let syncService: DDGSyncing
    private let keyValueStore: ThrowingKeyValueStoring
    private let featureFlagger: FeatureFlagger

    init(viewModel: DataImportViewModel,
         importScreen: DataImportViewModel.ImportScreen,
         syncService: DDGSyncing,
         keyValueStore: ThrowingKeyValueStoring,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.viewModel = viewModel
        self.importScreen = importScreen
        self.syncService = syncService
        self.keyValueStore = keyValueStore
        self.featureFlagger = featureFlagger
        super.init()
        self.viewModel.delegate = self
    }

    convenience init(bookmarksDatabase: CoreDataDatabase,
                     favoritesDisplayMode: FavoritesDisplayMode,
                     syncService: DDGSyncing,
                     keyValueStore: ThrowingKeyValueStoring,
                     tld: TLD = AppDependencyProvider.shared.storageCache.tld,
                     importScreen: DataImportViewModel.ImportScreen = .passwords,
                     featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        let importManager = DataImportManager(
            reporter: SecureVaultReporter(),
            bookmarksDatabase: bookmarksDatabase,
            favoritesDisplayMode: favoritesDisplayMode,
            tld: tld)
        let viewModel = DataImportViewModel(importScreen: importScreen, importManager: importManager)
        self.init(
            viewModel: viewModel,
            importScreen: importScreen,
            syncService: syncService,
            keyValueStore: keyValueStore,
            featureFlagger: featureFlagger
        )
    }
}

// MARK: - DataImportFileUploadCoordinating

extension DataImportFileUploadCoordinator: DataImportFileUploadCoordinating {

    func startUploadFlow(from owner: UIViewController & DataImportFileUploadFlowOwner) {
        presentingViewController = owner
        flowOwner = owner
        viewModel.selectFile()
    }
}

// MARK: - DataImportViewModelDelegate

extension DataImportFileUploadCoordinator: DataImportViewModelDelegate {

    func dataImportViewModelDidRequestImportFile(_ viewModel: DataImportViewModel) {
        viewModel.isLoading = true
        presentDocumentPicker(for: viewModel)
    }

    func dataImportViewModelDidRequestPresentDataPicker(_ viewModel: DataImportViewModel, contents: ImportArchiveContents) {
        presentDataTypePicker(for: viewModel, contents: contents)
    }

    func dataImportViewModelDidRequestPresentSummary(_ viewModel: DataImportViewModel, summary: DataImportSummary) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            viewModel.isLoading = false
            self.presentSummary(for: summary)
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension DataImportFileUploadCoordinator: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var validDocumentSelected = false

        defer {
            if !validDocumentSelected {
                viewModel.isLoading = false
            }
        }

        guard let selectedFileURL = urls.first else {
            return
        }

        do {
            let resourceValues = try selectedFileURL.resourceValues(forKeys: [.typeIdentifierKey])

            guard let typeIdentifier = resourceValues.typeIdentifier,
                  let fileType = DataImportFileType(typeIdentifier: typeIdentifier) else {
                ActionMessageView.present(message: UserText.dataImportFailedUnsupportedFileErrorMessage)
                return
            }

            validDocumentSelected = true
            viewModel.handleFileSelection(selectedFileURL, type: fileType)
            fireFileSelectedPixel(for: fileType, importScreen: viewModel.state.importScreen)
        } catch {
            Logger.autofill.debug("Failed to determine the file type: \(error)")
            ActionMessageView.present(message: UserText.dataImportFailedUnsupportedFileErrorMessage)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        viewModel.isLoading = false
        viewModel.documentPickerCancelled()
        flowOwner?.dataImportUploadDidCancel()
    }
}

// MARK: - Presentation

private extension DataImportFileUploadCoordinator {

    func presentDocumentPicker(for viewModel: DataImportViewModel) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let presentingViewController else { return }

            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: viewModel.state.importScreen.documentTypes, asCopy: true)
            documentPicker.delegate = self
            documentPicker.allowsMultipleSelection = false
            presentingViewController.present(documentPicker, animated: true)
        }

        Pixel.fire(
            pixel: .importInstructionsFileButtonTapped,
            withAdditionalParameters: [PixelParameters.source: viewModel.state.importScreen.rawValue]
        )
    }

    func presentDataTypePicker(for viewModel: DataImportViewModel, contents: ImportArchiveContents) {
        let dataTypes = viewModel.importDataTypes(for: contents)

        guard !dataTypes.isEmpty else {
            DispatchQueue.main.async {
                ActionMessageView.present(message: String(format: UserText.dataImportFailedReadErrorMessage, UserText.dataImportFileTypeZip))
                viewModel.isLoading = false
            }
            return
        }

        let zipContentSelectionViewController = ZipContentSelectionViewController(
            dataTypes,
            importScreen: viewModel.state.importScreen
        ) { selectedDataTypes in
            viewModel.importZipArchive(from: contents, for: selectedDataTypes)
        }

        if let presentationController = zipContentSelectionViewController.presentationController as? UISheetPresentationController {
            if #available(iOS 16.0, *) {
                presentationController.detents = [.custom(resolver: { _ in
                    360.0
                })]
            } else {
                presentationController.detents = [.medium()]
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let presentingViewController else { return }
            viewModel.isLoading = false
            presentingViewController.present(zipContentSelectionViewController, animated: true)
        }
    }

    func presentSummary(for summary: DataImportSummary) {
        guard let presentingViewController else {
            return
        }

        AutofillLoginImportState(keyValueStore: keyValueStore).hasImportedLogins = true
        AutofillOnboardingExperimentPixelReporter().fireImportCompleted()

        let summaryViewController = DataImportSummaryViewController(
            summary: summary,
            importScreen: importScreen,
            syncService: syncService
        ) { [weak self] source in
            self?.launchSync(source: source)
        } onCompletion: { [weak self] in
            self?.flowOwner?.dataImportUploadDidCompleteSummary()
        }

        presentingViewController.present(summaryViewController, animated: true)

        if featureFlagger.isFeatureOn(.showSettingsCompleteSetupSection) {
            try? keyValueStore.set(true, forKey: SettingsViewModel.Constants.didDismissSetAsDefaultBrowserKey)
            try? keyValueStore.set(true, forKey: SettingsViewModel.Constants.didDismissImportPasswordsKey)
        }
    }
}

// MARK: - Helpers

private extension DataImportFileUploadCoordinator {

    func launchSync(source: String?) {
        if let flowOwner {
            flowOwner.dataImportUploadDidRequestSync(source: source)
            return
        }

        guard let presentingViewController else { return }

        let mainViewController = presentingViewController as? MainViewController
        ?? presentingViewController.presentingViewController as? MainViewController
        ?? presentingViewController.navigationController?.presentingViewController as? MainViewController

        mainViewController?.dismiss(animated: true) {
            mainViewController?.segueToSettingsSync(with: source)
        }
    }

    func fireFileSelectedPixel(for fileType: DataImportFileType, importScreen: DataImportViewModel.ImportScreen) {
        let parameters = [PixelParameters.source: importScreen.rawValue]
        switch fileType {
        case .zip, .json:
            Pixel.fire(pixel: .importInstructionsFileSelectedZip, withAdditionalParameters: parameters)
        case .csv:
            Pixel.fire(pixel: .importInstructionsFileSelectedCsv, withAdditionalParameters: parameters)
        case .html:
            Pixel.fire(pixel: .importInstructionsFileSelectedHtml, withAdditionalParameters: parameters)
        }
    }
}
