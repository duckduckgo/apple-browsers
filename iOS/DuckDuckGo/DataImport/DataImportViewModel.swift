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

protocol DataImportViewModelDelegate: AnyObject {
    func dataImportViewModelDidRequestImportFile(_ viewModel: DataImportViewModel)
    func dataImportViewModelDidRequestPresentDataPicker(_ viewModel: DataImportViewModel, contents: ImportArchiveContents)
    func dataImportViewModelDidRequestPresentSummary(_ viewModel: DataImportViewModel, summary: DataImportSummary)
}

final class DataImportViewModel: ObservableObject {

    enum ImportScreen: String {
        case passwords
        case bookmarks

        var documentTypes: [UTType] {
            switch self {
            case .passwords: return [.zip, .commaSeparatedText]
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
            case (.safari, .passwords):
                return attributedInstructionsForSafariPasswords()
            case (.chrome, .passwords), (.chrome, .bookmarks):
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
            case .passwords:
                return Image(.passwordsImport128)
            case .bookmarks:
                return Image(.bookmarksImport96)
            }
        }

        var title: String {
            switch importScreen {
            case .passwords:
                return UserText.dataImportPasswordsTitle
            case .bookmarks:
                return UserText.dataImportBookmarksTitle
            }
        }

        var subtitle: String {
            switch importScreen {
            case .passwords:
                return UserText.dataImportPasswordsSubtitle
            case .bookmarks:
                return UserText.dataImportBookmarksSubtitle
            }
        }

        var buttonTitle: String {
            switch importScreen {
            case .passwords:
                return UserText.dataImportPasswordsFileButton
            case .bookmarks:
                return UserText.dataImportBookmarksFileButton
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

    init(importScreen: ImportScreen, importManager: DataImportManaging) {
        self.importManager = importManager
        self.state = BrowserImportState(browser: .safari, importScreen: importScreen)
    }

    func selectFile() {
        delegate?.dataImportViewModelDidRequestImportFile(self)
    }

    func importDataTypes(for contents: ImportArchiveContents) -> [DataImportManager.ImportPreview] {
        DataImportManager.preview(contents: contents, tld: AppDependencyProvider.shared.storageCache.tld)
    }

    func handleFileSelection(_ url: URL, type: DataImportFileType) {
        switch type {
        case .zip:
            do {
               let contents = try ImportArchiveReader().readContents(from: url)

                switch contents.type {
                case .both:
                    delegate?.dataImportViewModelDidRequestPresentDataPicker(self, contents: contents)
                case .passwordsOnly:
                    importZipArchive(from: contents, for: [.passwords])
                case .bookmarksOnly:
                    importZipArchive(from: contents, for: [.bookmarks])
                case .none:
                    DispatchQueue.main.async { [weak self] in
                        self?.isLoading = false
                        ActionMessageView.present(message: UserText.dataImportFailedNoDataInZipErrorMessage)
                    }
                    Pixel.fire(pixel: .importResultUnzipping, withAdditionalParameters: [PixelParameters.source: state.importScreen.rawValue])
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.isLoading = false
                    ActionMessageView.present(message: String(format: UserText.dataImportFailedReadErrorMessage, UserText.dataImportFileTypeZip))
                }
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
            let summary = await importManager.importZipArchive(from: contents, for: dataTypes)
            Logger.autofill.debug("Imported \(summary.description)")
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
                guard let summary = try await importManager.importFile(at: url, for: fileType) else {
                    Logger.autofill.debug("Failed to import data")
                    presentErrorMessage(for: fileType)
                    return
                }

                var hadAnySuccess = false
                var failedImports: [(BrowserServicesKit.DataImport.DataType, Error)] = []

                for dataType in [BrowserServicesKit.DataImport.DataType.passwords, .bookmarks] {
                    if let result = summary[dataType] {
                        switch result {
                        case .success:
                            hadAnySuccess = true
                        case .failure(let error):
                            failedImports.append((dataType, error))
                        }
                    }
                }

                for (type, _) in failedImports {
                    presentErrorMessage(for: type == .bookmarks ? .html : .csv)
                }

                // Only proceed to success screen if at least one type succeeded
                if hadAnySuccess {
                    Logger.autofill.debug("Imported \(summary.description)")
                    delegate?.dataImportViewModelDidRequestPresentSummary(self, summary: summary)
                }
            } catch {
                Logger.autofill.debug("Failed to import data: \(error)")
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
        }

        DispatchQueue.main.async {
            ActionMessageView.present(message: String(format: UserText.dataImportFailedReadErrorMessage, fileName))
        }
     }

}
