//
//  DataImportViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import SwiftUI
import UniformTypeIdentifiers
import Core
import BrowserServicesKit
import Common
import DesignResourcesKit
import PixelKit

protocol DataImportViewModelDelegate: AnyObject {
    func dataImportViewModelDidRequestImportFile(_ viewModel: DataImportViewModel)
    func dataImportViewModelDidRequestPresentDataPicker(_ viewModel: DataImportViewModel, contents: ImportArchiveContents)
    func dataImportViewModelDidRequestPresentSummary(_ viewModel: DataImportViewModel, summary: DataImportSummary)
}

final class DataImportViewModel: ObservableObject {

    enum ImportScreen: String {
        case passwords
        case bookmarks
        case settings
        case promo
        case inBrowserPromo = "in_browser_promo"
        case whatsNew

        var documentTypes: [UTType] {
            switch self {
            case .passwords, .settings, .promo, .inBrowserPromo, .whatsNew: return [.zip, .commaSeparatedText]
            case .bookmarks: return [.zip, .html]
            }
        }
    }

    enum BrowserInstructions: String, CaseIterable, Identifiable {
        case safari
        case chrome

        var id: String { rawValue }

        var icon: Image {
            switch self {
            case .safari:
                return Image(.safariMulticolor)
            case .chrome:
                return Image(.chromeMulticolor)
            }
        }

        var displayName: String {
            switch self {
            case .safari:
                return UserText.dataImportPasswordsInstructionSafari
            case .chrome:
                return UserText.dataImportPasswordsInstructionChrome
            }
        }

    }

    enum InstructionStep: Int, CaseIterable {
        case step1 = 1
        case step2

        func attributedInstructions(for state: BrowserImportState) -> AttributedString {
            switch (state.browser, state.importScreen) {
            case (.safari, .bookmarks):
                return attributedInstructionsForSafariBookmarks()
            case (.safari, _):
                return attributedInstructionsForSafariPasswords()
            case (.chrome, _):
                return attributedInstructionsForChrome()
            }
        }

        private func attributedInstructionsForSafariBookmarks() -> AttributedString {
            switch self {
            case .step1:
                do {
                    return try AttributedString(markdown: UserText.dataImportInstructionsSafariStep1)
                } catch {
                    return AttributedString(UserText.dataImportInstructionsSafariStep1)
                }
            case .step2:
                do {
                    return try AttributedString(markdown: UserText.dataImportInstructionsSafariStep2Bookmarks)
                } catch {
                    return AttributedString(UserText.dataImportInstructionsSafariStep2Bookmarks)
                }
            }
        }

        private func attributedInstructionsForSafariPasswords() -> AttributedString {
            switch self {
            case .step1:
                do {
                    return try AttributedString(markdown: UserText.dataImportInstructionsSafariStep1)
                } catch {
                    return AttributedString(UserText.dataImportInstructionsSafariStep1)
                }
            case .step2:
                do {
                    return try AttributedString(markdown: UserText.dataImportInstructionsSafariStep2Passwords)
                } catch {
                    return AttributedString(UserText.dataImportInstructionsSafariStep2Passwords)
                }
            }
        }

        private func attributedInstructionsForChrome() -> AttributedString {
            switch self {
            case .step1:
                do {
                    return try AttributedString(markdown: UserText.dataImportPasswordsInstructionsChromeStep1)
                } catch {
                    return AttributedString(UserText.dataImportPasswordsInstructionsChromeStep1)
                }
            case .step2:
                do {
                    return try AttributedString(markdown: UserText.dataImportPasswordsInstructionsChromeStep2)
                } catch {
                    return AttributedString(UserText.dataImportPasswordsInstructionsChromeStep2)
                }
            }
        }
    }

    struct BrowserImportState {
        var browser: BrowserInstructions {
            didSet {
                Pixel.fire(pixel: .importInstructionsToggled, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue])
            }
        }
        let importScreen: ImportScreen

        var image: Image {
            switch importScreen {
            case .bookmarks:
                return Image(.bookmarksImport96)
            default:
                return Image(.passwordsImport128)
            }
        }

        var title: String {
            switch importScreen {
            case .bookmarks:
                return UserText.dataImportBookmarksTitle
            default:
                return UserText.dataImportPasswordsTitle
            }
        }

        var subtitle: String {
            switch importScreen {
            case .bookmarks:
                return UserText.dataImportBookmarksSubtitle
            default:
                return UserText.dataImportPasswordsSubtitle
            }
        }

        var buttonTitle: String {
            switch importScreen {
            case .bookmarks:
                return UserText.dataImportBookmarksFileButton
            default:
                return UserText.dataImportPasswordsSelectFileButton
            }
        }

        var displayName: String { browser.displayName }

        var icon: Image { browser.icon }

        var instructionSteps: [InstructionStep] {
            InstructionStep.allCases
        }
    }

    weak var delegate: DataImportViewModelDelegate?

    private let importManager: DataImportManaging

    @Published var state: BrowserImportState
    @Published var isLoading = false
    
    private var isDataImportWideEventMeasurementEnabled: Bool {
        AppDependencyProvider.shared.featureFlagger.isFeatureOn(.dataImportWideEventMeasurement)
    }
    private let wideEvent: WideEventManaging
    private var dataImportWideEventData: DataImportWideEventData?

    init(importScreen: ImportScreen, importManager: DataImportManaging, wideEvent: WideEventManaging = AppDependencyProvider.shared.wideEvent) {
        self.importManager = importManager
        self.state = BrowserImportState(browser: .safari, importScreen: importScreen)
        self.wideEvent = wideEvent
    }

    func selectFile() {
        setupAndStartWideEvent()
        delegate?.dataImportViewModelDidRequestImportFile(self)
    }

    func importDataTypes(for contents: ImportArchiveContents) -> [DataImportManager.ImportPreview] {
        DataImportManager.preview(contents: contents, tld: AppDependencyProvider.shared.storageCache.tld)
    }

    func handleFileSelection(_ url: URL, type: DataImportFileType) {
        switch type {
        case .zip:
            do {
                let contents = try ImportArchiveReader().readContents(from: url, featureFlagger: AppDependencyProvider.shared.featureFlagger)

                switch contents.type {
                case .passwordsOnly:
                    importZipArchive(from: contents, for: [.passwords])
                case .bookmarksOnly:
                    importZipArchive(from: contents, for: [.bookmarks])
                case .creditCardsOnly:
                    importZipArchive(from: contents, for: [.creditCards])
                case .none:
                    DispatchQueue.main.async { [weak self] in
                        self?.isLoading = false
                        ActionMessageView.present(message: UserText.dataImportFailedNoDataInZipErrorMessage)
                    }
                    completeAndCleanupWideEvent(with: .failure, description: "No supported data found in zip file.")
                    Pixel.fire(pixel: .importResultUnzipping, withAdditionalParameters: [PixelParameters.source: state.importScreen.rawValue])
                default:
                    delegate?.dataImportViewModelDidRequestPresentDataPicker(self, contents: contents)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.isLoading = false
                    ActionMessageView.present(message: String(format: UserText.dataImportFailedReadErrorMessage, UserText.dataImportFileTypeZip))
                }
                completeAndCleanupWideEvent(with: .failure, error: error, description: "The zip file could not be read.")
                Pixel.fire(pixel: .importResultUnzipping, withAdditionalParameters: [PixelParameters.source: state.importScreen.rawValue])
            }
        default:
            importFile(at: url, for: type)
        }
    }

    func importZipArchive(from contents: ImportArchiveContents,
                          for dataTypes: [DataImport.DataType]) {
        isLoading = true
        Task {
            startDurationMeasurement(for: dataTypes)
            let summary = await importManager.importZipArchive(from: contents, for: dataTypes)
            completeDurationMeasurement(for: dataTypes)
            Logger.autofill.debug("Imported \(summary.description)")
            completeAndCleanupWideEvent(with: summary)
            delegate?.dataImportViewModelDidRequestPresentSummary(self, summary: summary)
        }
    }

    // MARK: - Private

    private func importFile(at url: URL, for fileType: DataImportFileType) {
        isLoading = true

        Task {
            defer {
                Task { @MainActor in
                    self.isLoading = false
                }
            }

            do {
                startDurationMeasurement(for: fileType)
                guard let summary = try await importManager.importFile(at: url, for: fileType) else {
                    Logger.autofill.debug("Failed to import data")
                    presentErrorMessage(for: fileType)
                    completeAndCleanupWideEvent(with: .failure, description: "Failed to import data with \(fileType)")
                    return
                }
                completeDurationMeasurement(for: fileType)

                var hadAnySuccess = false
                var isAllSuccessful = true
                var failedImports: [(BrowserServicesKit.DataImport.DataType, Error)] = []

                for dataType in [BrowserServicesKit.DataImport.DataType.passwords, .bookmarks] {
                    if let result = summary[dataType] {
                        switch result {
                        case .success(let typeSummary):
                            hadAnySuccess = true
                            if typeSummary.isAllSuccessful {
                                dataImportWideEventData?[keyPath: dataType.statusPath] = .success
                            } else {
                                isAllSuccessful = false
                                dataImportWideEventData?[keyPath: dataType.statusPath] = .success(reason: DataImportWideEventData.StatusReason.partialData.rawValue)
                            }
                        case .failure(let error):
                            failedImports.append((dataType, error))
                            isAllSuccessful = false
                            dataImportWideEventData?[keyPath: dataType.statusPath] = .failure
                            dataImportWideEventData?[keyPath: dataType.errorPath] = WideEventErrorData(error: error, description: error.errorType.description)
                        }
                    }
                }

                for (type, _) in failedImports {
                    presentErrorMessage(for: type == .bookmarks ? .html : .csv)
                }

                // Only proceed to success screen if at least one type succeeded
                if hadAnySuccess {
                    Logger.autofill.debug("Imported \(summary.description)")
                    if isAllSuccessful {
                        completeAndCleanupWideEvent(with: .success)
                    } else {
                        completeAndCleanupWideEvent(with: .success(reason: DataImportWideEventData.StatusReason.partialData.rawValue))
                    }
                    delegate?.dataImportViewModelDidRequestPresentSummary(self, summary: summary)
                } else {
                    completeAndCleanupWideEvent(with: .failure)
                }
            } catch {
                Logger.autofill.debug("Failed to import data: \(error)")
                completeAndCleanupWideEvent(with: .failure, error: error, description: "Failed to import data")
                presentErrorMessage(for: fileType)
            }
        }
    }

    private func presentErrorMessage(for fileType: DataImportFileType) {
        var fileName = ""
        switch fileType {
        case .csv:
            fileName = UserText.dataImportFileTypeCsv
            Pixel.fire(pixel: .importResultPasswordsParsing, withAdditionalParameters: [PixelParameters.source: state.importScreen.rawValue])
        case .html:
            fileName = UserText.dataImportFileTypeHtml
            Pixel.fire(pixel: .importResultBookmarksParsing, withAdditionalParameters: [PixelParameters.source: state.importScreen.rawValue])
        case .zip:
            fileName = UserText.dataImportFileTypeZip
            Pixel.fire(pixel: .importResultUnzipping, withAdditionalParameters: [PixelParameters.source: state.importScreen.rawValue])
        case .json:
            // JSON files aren't supported for standalone import (only as part of a zip archive)
            return
        }

        DispatchQueue.main.async {
            ActionMessageView.present(message: String(format: UserText.dataImportFailedReadErrorMessage, fileName))
        }
     }

}


// MARK: - Wide Event

private extension DataImportViewModel {
    func setupAndStartWideEvent() {
        guard isDataImportWideEventMeasurementEnabled else { return }
        let data = DataImportWideEventData(
            source: .init(browserInstructions: state.browser),
            contextData: WideEventContextData(name: funnel(for: state.importScreen))
        )
        self.dataImportWideEventData = data
        self.dataImportWideEventData?.overallDuration = WideEvent.MeasuredInterval.startingNow()
        wideEvent.startFlow(data)
    }

    func startDurationMeasurement(for types: [DataImport.DataType]) {
        guard isDataImportWideEventMeasurementEnabled else { return }
        for type in types {
            dataImportWideEventData?[keyPath: type.importerDurationPath] = WideEvent.MeasuredInterval.startingNow()
        }
    }

    func startDurationMeasurement(for fileType: DataImportFileType) {
        startDurationMeasurement(for: Array(fileType.matchingDataTypes))
    }

    func completeDurationMeasurement(for types: [DataImport.DataType]) {
        guard isDataImportWideEventMeasurementEnabled else { return }
        for type in types {
            dataImportWideEventData?[keyPath: type.importerDurationPath]?.complete()
        }
    }
    
    func completeDurationMeasurement(for fileType: DataImportFileType) {
        completeDurationMeasurement(for: Array(fileType.matchingDataTypes))
    }
    
    func completeAndCleanupWideEvent(with importSummery: DataImportSummary) {
        guard isDataImportWideEventMeasurementEnabled else { return }
        
        for type in DataImport.DataType.allCases {
            guard let result = importSummery[type] else { continue }

            switch result {
            case .success(let typeSummary):
                if typeSummary.isAllSuccessful {
                    dataImportWideEventData?[keyPath: type.statusPath] = .success
                } else {
                    dataImportWideEventData?[keyPath: type.statusPath] = .success(reason: DataImportWideEventData.StatusReason.partialData.rawValue)
                }
            case .failure(let error):
                dataImportWideEventData?[keyPath: type.statusPath] = .failure
                dataImportWideEventData?[keyPath: type.errorPath] = WideEventErrorData(error: error, description: error.errorType.description)
            }
        }
        // Complete Failure
        if importSummery.allSatisfy({ !$1.isSuccess }) {
            completeAndCleanupWideEvent(with: .failure)
            return
        }
        // Complete Success
        if importSummery.allSatisfy({ ((try? $1.get().isAllSuccessful) ?? false ) == true }) {
            completeAndCleanupWideEvent(with: .success)
            return
        }
        completeAndCleanupWideEvent(with: .success(reason: DataImportWideEventData.StatusReason.partialData.rawValue))
    }

    func completeAndCleanupWideEvent(with status: WideEventStatus, error: Error? = nil, description: String? = nil) {
        guard isDataImportWideEventMeasurementEnabled, let data = self.dataImportWideEventData else { return }
        data.overallDuration?.complete()
        if let error {
            data.errorData = .init(error: error, description: description)
        }
        wideEvent.completeFlow(data, status: status, onComplete: { _, _ in })
        self.dataImportWideEventData = nil
    }
    
    func funnel(for importScreen: DataImportViewModel.ImportScreen) -> String? {
        return "funnel_\(importScreen.rawValue)_ios"
    }
}

// MARK: - DataImport

private extension DataImport.Source {
    init(browserInstructions: DataImportViewModel.BrowserInstructions) {
        switch browserInstructions {
        case .safari:
            self = .safari
        case .chrome:
            self = .chrome
        }
    }
}
