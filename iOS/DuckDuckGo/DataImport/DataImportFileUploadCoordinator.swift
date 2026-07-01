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
import FoundationExtensions
import Core
import UniformTypeIdentifiers
import DDGSync
import Persistence
import PrivacyConfig
import os.log

protocol DataImportFileUploadFlowOwner: AnyObject {
    func dataImportUploadDidCompleteSummary()
    func dataImportUploadDidRequestSync(source: String?)
    func dataImportUploadDidRequestContinueToSafariImport()
    func dataImportUploadDidCancel()
}

protocol DataImportFileUploadCoordinating: AnyObject {
    func startUploadFlow(from owner: UIViewController & DataImportFileUploadFlowOwner, source: ImportPasswordSource)
}

final class DataImportFileUploadCoordinator: NSObject {

    private weak var presentingViewController: UIViewController?
    private weak var flowOwner: DataImportFileUploadFlowOwner?
    private let viewModel: DataImportViewModel
    private let importScreen: DataImportViewModel.ImportScreen
    private let syncService: DDGSyncing
    private let keyValueStore: ThrowingKeyValueStoring
    private let featureFlagger: FeatureFlagger
    private var sessionImportedDataTypes: Set<DataImport.DataType> = []
    private var currentImportSource: ImportPasswordSource?

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
        self.viewModel.onFileError = { [weak self] error in
            self?.presentFileErrorSheet(error)
        }
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
        let viewModel = DataImportViewModel(importScreen: importScreen, importManager: importManager, shouldFireLegacyPixels: false)
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

    func startUploadFlow(from owner: UIViewController & DataImportFileUploadFlowOwner, source: ImportPasswordSource) {
        presentingViewController = owner
        flowOwner = owner
        currentImportSource = source
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
                Pixel.fire(pixel: .importHubFilePickerUnsupported, withAdditionalParameters: importHubFilePickerPixelParameters)
                presentFileErrorSheet(.unsupportedFile)
                return
            }

            validDocumentSelected = true
            viewModel.handleFileSelection(selectedFileURL, type: fileType)
            fireHubFilePickedPixelIfNeeded(for: fileType)
        } catch {
            Logger.autofill.debug("Failed to determine the file type: \(error)")
            Pixel.fire(pixel: .importHubFilePickerUnsupported, withAdditionalParameters: importHubFilePickerPixelParameters)
            presentFileErrorSheet(.unsupportedFile)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        viewModel.isLoading = false
        viewModel.documentPickerCancelled()
        Pixel.fire(pixel: .importHubFilePickerCancelled, withAdditionalParameters: importHubFilePickerPixelParameters)
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

        Pixel.fire(pixel: .importHubFilePickerDisplayed, withAdditionalParameters: importHubFilePickerPixelParameters)
    }

    func presentDataTypePicker(for viewModel: DataImportViewModel, contents: ImportArchiveContents) {
        let importPreview = viewModel.importDataTypes(for: contents)

        guard !importPreview.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                viewModel.isLoading = false
                self?.presentFileErrorSheet(.noDataInZip)
            }
            return
        }

        // Safari export already scopes the zip to selected data types, so
        // the new Import from Safari flow should skip the in-app type picker.
        if currentImportSource == .safari {
            let selectedDataTypes = importPreview.map(\.type)
            viewModel.importZipArchive(from: contents, for: selectedDataTypes)
            return
        }

        let zipContentSelectionViewController = ZipContentSelectionViewController(
            importPreview,
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

    func presentFileErrorSheet(_ error: DataImportFileError) {
        fireHubFileErrorPixelsIfNeeded(for: error)

        DispatchQueue.main.async { [weak self] in
            guard let presentingViewController = self?.presentingViewController else { return }
            let errorVC = FileCorruptErrorViewController(error: error)
            if let sheet = errorVC.sheetPresentationController {
                sheet.detents = [.medium()]
            }
            presentingViewController.present(errorVC, animated: true)
        }
    }

    func presentSummary(for summary: DataImportSummary) {
        guard let presentingViewController else {
            return
        }

        recordImportedDataTypes(from: summary)

        AutofillLoginImportState(keyValueStore: keyValueStore).hasImportedLogins = true

        let summaryViewController = DataImportSummaryViewController(
            summary: summary,
            importScreen: importScreen,
            syncService: syncService,
            sessionImportedDataTypes: sessionImportedDataTypes,
            isSafariImportFlow: currentImportSource == .safari,
            importHubPixelContext: importHubPixelContext
        ) { [weak self] source in
            self?.launchSync(source: source)
        } onCompletion: { [weak self] in
            self?.clearSessionImportedDataTypes()
            self?.flowOwner?.dataImportUploadDidCompleteSummary()
        } onContinueToSafariImport: { [weak self] in
            self?.flowOwner?.dataImportUploadDidRequestContinueToSafariImport()
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

    var importHubPixelContext: DataImportHubPixelContext {
        DataImportHubPixelContext(entryPoint: importScreen, source: currentImportSource?.id)
    }

    var importHubFilePickerPixelParameters: [String: String] {
        DataImportHubPixelContext(entryPoint: importScreen, source: nil).parameters
    }

    func recordImportedDataTypes(from summary: DataImportSummary) {
        for (dataType, result) in summary where (try? result.get()) != nil {
            sessionImportedDataTypes.insert(dataType)
        }
    }

    func clearSessionImportedDataTypes() {
        sessionImportedDataTypes.removeAll()
    }

    func launchSync(source: String?) {
        clearSessionImportedDataTypes()

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

    func fireHubFilePickedPixelIfNeeded(for fileType: DataImportFileType) {
        switch fileType {
        case .zip, .json:
            Pixel.fire(pixel: .importHubFilePickedZip, withAdditionalParameters: importHubFilePickerPixelParameters)
        case .csv:
            Pixel.fire(pixel: .importHubFilePickedCsv, withAdditionalParameters: importHubFilePickerPixelParameters)
        case .html:
            Pixel.fire(pixel: .importHubFilePickedHtml, withAdditionalParameters: importHubFilePickerPixelParameters)
        }
    }

    func fireHubFileErrorPixelsIfNeeded(for error: DataImportFileError) {
        var fileErrorParameters = importHubPixelContext.parameters
        fileErrorParameters[PixelParameters.reason] = error.importHubReason
        Pixel.fire(pixel: .importHubFileErrorDisplayed, withAdditionalParameters: fileErrorParameters)

        guard let failurePixel = error.importHubFailurePixel else {
            return
        }

        Pixel.fire(pixel: failurePixel, withAdditionalParameters: importHubPixelContext.parameters)
    }
}

extension DataImportFileError {
    var importHubReason: String {
        switch self {
        case .unsupportedFile:
            return "unsupported_file"
        case .noDataInZip:
            return "no_supported_data_in_zip"
        case .fileUnreadable:
            return "file_unreadable"
        }
    }

    var importHubFailurePixel: Pixel.Event? {
        switch self {
        case .unsupportedFile:
            return nil
        case .noDataInZip:
            return .importHubResultUnzipping
        case .fileUnreadable(let fileType):
            if fileType == UserText.dataImportFileTypeCsv {
                return .importHubResultPasswordsParsing
            }

            if fileType == UserText.dataImportFileTypeHtml {
                return .importHubResultBookmarksParsing
            }

            return .importHubResultUnzipping
        }
    }
}
