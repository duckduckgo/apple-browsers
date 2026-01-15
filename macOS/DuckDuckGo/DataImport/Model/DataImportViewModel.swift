//
//  DataImportViewModel.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import AppKit
import Common
import UniformTypeIdentifiers
import PixelKit
import os.log
import BrowserServicesKit

struct DataImportViewModel {

    typealias Source = DataImport.Source
    typealias BrowserProfileList = DataImport.BrowserProfileList
    typealias BrowserProfile = DataImport.BrowserProfile
    typealias DataType = DataImport.DataType
    typealias DataTypeSummary = DataImport.DataTypeSummary

    @UserDefaultsWrapper(key: .homePageContinueSetUpImport, defaultValue: nil)
    var successfulImportHappened: Bool?

    let availableImportSources: [DataImport.Source]

    let selectableImportTypes: Set<DataType>

    /// Browser to import data from
    let importSource: Source
    /// BrowserProfileList loader (factory method) - used
    private let loadProfiles: (ThirdPartyBrowser) -> BrowserProfileList
    /// Loaded BrowserProfileList
    let browserProfiles: BrowserProfileList?

    typealias DataImporterFactory = @MainActor (Source, DataType?, URL, /* primaryPassword: */ String?) -> DataImporter
    /// Factory for a DataImporter for importSource
    private let dataImporterFactory: DataImporterFactory

    /// Show a main password input dialog callback
    private let requestPrimaryPasswordCallback: @MainActor (Source) -> String?

    /// Show Open Panel to choose CSV/HTML file
    private let openPanelCallback: @MainActor ([UTType]) -> URL?

    private let syncFeatureVisibility: SyncFeatureVisibility

    typealias ReportSenderFactory = () -> (DataImportReportModel) -> Void
    /// Factory for a DataImporter for importSource
    private let reportSenderFactory: ReportSenderFactory

    private let onFinished: () -> Void

    private let onCancelled: () -> Void

    indirect enum Screen: Equatable {
        case sourceAndDataTypesPicker
        case profilePicker
        case moreInfo
        case passwordEntryHelp
        case getReadPermission(URL)
        case fileImport(dataType: DataType, summary: DataImportSummary = [:])
        case archiveImport(dataTypes: Set<DataType>, summary: DataImportSummary? = nil)
        case summary(DataImportSummary)
        case summaryDetail(DataImportSummary, DataImport.DataType)

        var isFileImport: Bool {
            if case .fileImport = self { true } else { false }
        }

        var isArchiveImport: Bool {
            if case .archiveImport = self { true } else { false }
        }

        var isProfilePicker: Bool {
            if case .profilePicker = self { true } else { false }
        }

        var fileImportDataType: DataType? {
            switch self {
            case .fileImport(dataType: let dataType, summary: _):
                return dataType
            default:
                return nil
            }
        }
    }
    /// Currently displayed screen
    private(set) var screen: Screen

    /// selected Browser Profile (if any)
    var selectedProfile: BrowserProfile?
    /// selected Data Types to import (bookmarks/passwords)
    var selectedDataTypes: Set<DataType> = []
    var isPickerExpanded: Bool = false

    enum DataTypeSelection: Equatable {
        case all
        case single(DataType)
        case none
    }

    var dataTypesSelection: DataTypeSelection {
        // Credit cards cannot be selected yet
        if selectedDataTypes.count == selectableImportTypes.count {
            return .all
        }
        guard let selectedDataType = selectedDataTypes.first else {
            return .none
        }
        return .single(selectedDataType)
    }

    /// data import concurrency Task launched in `initiateImport`
    /// used to cancel import and in `importProgress` to trace import progress and import completion
    private var importTask: DataImportTask?

    /// Unique identifier for the current import task, used to trigger task observation in the view
    private(set) var importTaskId: UUID?

    /// Wide Event
    private let wideEvent: WideEventManaging
    private var dataImportWideEventData: DataImportWideEventData?
    private var isDataImportWideEventMeasurementEnabled: Bool {
        Application.appDelegate.featureFlagger.isFeatureOn(.dataImportWideEventMeasurement)
    }

    struct DataTypeImportResult: Equatable {
        let dataType: DataImport.DataType
        let result: DataImportResult<DataTypeSummary>
        init(_ dataType: DataImport.DataType, _ result: DataImportResult<DataTypeSummary>) {
            self.dataType = dataType
            self.result = result
        }

        static func == (lhs: DataTypeImportResult, rhs: DataTypeImportResult) -> Bool {
            lhs.dataType == rhs.dataType &&
            lhs.result.description == rhs.result.description
        }
    }

    /// collected import summary for current import operation per selected import source
    private(set) var summary: [DataTypeImportResult]

    var errors: [[DataType: any DataImportError]] = []

    private var userReportText: String = ""

    var shouldHideProgress: Bool {
        switch screen {
        case .moreInfo, .passwordEntryHelp:
            return true
        default:
            return false
        }
    }

    var shouldHideFooter: Bool {
        switch screen {
        case .moreInfo:
            return true
        default:
            return false
        }
    }

    var shouldHidePasswordExplainerView: Bool {
        switch screen {
        case .moreInfo, .profilePicker:
            return true
        default:
            return false
        }
    }

#if DEBUG || REVIEW

    // simulated test import failure
    struct TestImportError: DataImportError {
        enum OperationType: Int {
            case imp
        }
        var type: OperationType { .imp }
        var action: DataImportAction
        var underlyingError: Error? { CocoaError(.fileReadUnknown) }
        var errorType: DataImport.ErrorType
    }

    var testImportResults = [DataType: DataImportResult<DataTypeSummary>]()

#endif

    let isPasswordManagerAutolockEnabled: Bool

    init(importSource: Source? = nil,
         screen: Screen? = nil,
         availableImportSources: [DataImport.Source] = DataImport.Source.allCases.filter { $0.canImportData },
         preferredImportSources: [Source] = [.chrome, .firefox, .safari],
         summary: [DataTypeImportResult] = [],
         selectedDataTypes: Set<DataType>? = nil,
         isPickerExpanded: Bool = false,
         isPasswordManagerAutolockEnabled: Bool = AutofillPreferences().isAutoLockEnabled,
         syncFeatureVisibility: SyncFeatureVisibility = .hide,
         loadProfiles: @escaping (ThirdPartyBrowser) -> BrowserProfileList = { $0.browserProfiles() },
         dataImporterFactory: @escaping DataImporterFactory = dataImporter,
         requestPrimaryPasswordCallback: @escaping @MainActor (Source) -> String? = Self.requestPrimaryPasswordCallback,
         openPanelCallback: @escaping @MainActor ([UTType]) -> URL? = Self.openPanelCallback,
         reportSenderFactory: @escaping ReportSenderFactory = { FeedbackSender().sendDataImportReport },
         wideEvent: WideEventManaging = Application.appDelegate.wideEvent,
         onFinished: @escaping () -> Void = {},
         onCancelled: @escaping () -> Void = {}) {
        let filteredAvailableSources = availableImportSources.filter {
            // Filter out CSV and HTML as we're using the new combined file import option
             if $0 == .bookmarksHTML || $0 == .csv {
                 return false
             }

            let browser = ThirdPartyBrowser.browser(for: $0)
            guard browser?.isWebBrowser == true else {
                // Don't filter out password managers or file imports
                return true
            }
            let profiles = browser.map(loadProfiles)
            return profiles?.defaultProfile != nil
        }

        self.availableImportSources = filteredAvailableSources
        let importSource = importSource ?? preferredImportSources.first(where: { filteredAvailableSources.contains($0) }) ?? filteredAvailableSources.first ?? .csv

        self.importSource = importSource
        self.loadProfiles = loadProfiles
        self.dataImporterFactory = dataImporterFactory

        self.screen = screen ?? .sourceAndDataTypesPicker

        let browserProfiles = ThirdPartyBrowser.browser(for: importSource).map(loadProfiles)
        self.browserProfiles = browserProfiles
        let selectedProfile = browserProfiles?.defaultProfile
        self.selectedProfile = selectedProfile

        let availableImportTypes = importSource.supportedDataTypes.filter { dataType in
            guard let profiles = browserProfiles else { return true }

            // If we have valid profiles, check if any profile has valid data for this type.
            // If no valid profiles (Safari doesn't check profiles, password managers), return true (include all types).
            let validProfiles = profiles.validImportableProfiles
            guard !validProfiles.isEmpty else { return true }

            return validProfiles.contains { profile in
                profile.hasValidProfileData(for: dataType)
            }
        }
        self.selectableImportTypes = availableImportTypes
        self.selectedDataTypes = Self.determineSelectedDataTypes(
            previousSelectedTypes: selectedDataTypes,
            availableTypes: availableImportTypes
        )

        self.summary = summary
        self.isPickerExpanded = isPickerExpanded
        self.isPasswordManagerAutolockEnabled = isPasswordManagerAutolockEnabled
        self.syncFeatureVisibility = syncFeatureVisibility

        self.requestPrimaryPasswordCallback = requestPrimaryPasswordCallback
        self.openPanelCallback = openPanelCallback
        self.reportSenderFactory = reportSenderFactory
        self.wideEvent = wideEvent
        self.onFinished = onFinished
        self.onCancelled = onCancelled
    }

    /// Import button press (starts browser data import)
    @MainActor
    mutating func initiateImport(primaryPassword: String? = nil, fileURL: URL? = nil) {
        setupAndStartWideEventIfNeeded()
        guard let url = fileURL ?? selectedProfile?.profileURL else {
            assertionFailure("URL not provided")
            return
        }

        // are we handling file import or browser selected data types import?
        let dataType: DataType? = self.screen.fileImportDataType
        let importer = dataImporterFactory(importSource, dataType, url, primaryPassword)

        let dataTypes = dataTypesForImport
        startDurationMeasurement(for: dataTypes)

        Logger.dataImportExport.debug("import \(dataTypes) at \"\(url.path)\" using \(type(of: importer))")

        // validate file access/encryption password requirement before starting import
        if let errors = importer.validateAccess(for: dataTypes),
           handleErrors(errors) == true {
            for (dataType, error) in errors {
                completeDurationMeasurement(for: dataType, with: .failure, error: WideEventErrorData(error: error, description: error.errorType.description))
            }
            return
        }

#if DEBUG || REVIEW
        // simulated test import failures
        guard dataTypes.compactMap({ testImportResults[$0] }).isEmpty else {
            importTask = .detachedWithProgress { [testImportResults] _ in
                var result = DataImportSummary()
                let selectedDataTypesWithoutFailureReasons = dataTypes.intersection(importer.importableTypes).subtracting(testImportResults.keys)
                var realSummary = DataImportSummary()
                if !selectedDataTypesWithoutFailureReasons.isEmpty {
                    realSummary = await importer.importData(types: selectedDataTypesWithoutFailureReasons).task.value
                }
                for dataType in dataTypes {
                    if let importResult = testImportResults[dataType] {
                        result[dataType] = importResult
                    } else {
                        result[dataType] = realSummary[dataType]
                    }
                }
                return result
            }
            importTaskId = UUID()
            return
        }
#endif
        importTask = importer.importData(types: dataTypes)
        importTaskId = UUID()
    }

    private var dataTypesForImport: Set<DataType> {
        if case .archiveImport(let dataTypes, _) = screen {
            return dataTypes
        }
        // are we handling file import or browser selected data types import?
        let dataType: DataType? = self.screen.fileImportDataType
        // either import only data type for file import
        let dataTypes = dataType.map { [$0] }
        // or all the selected data types subtracting the ones that are already imported
        ?? selectedDataTypes.subtracting(self.summary.filter { $0.result.isSuccess }.map(\.dataType))
        return Set(dataTypes)
    }

    /// Called with data import task result to update the state by merging the summary with an existing summary
    @MainActor
    private mutating func mergeImportSummary(with summary: DataImportSummary) {
        self.importTask = nil

        Logger.dataImportExport.debug("merging summary \(summary)")

        // append successful import results first keeping the original DataType sorting order
        self.summary.append(contentsOf: DataType.allCases.compactMap { dataType in
            (try? summary[dataType]?.get()).map {
                .init(dataType, .success($0))
            }
        })

        // if there‘s read permission/primary password requested - request it and reinitiate import
        if handleErrors(summary.compactMapValues { $0.error }) {
            completeDurationMeasurement(with: summary)
            return
        }

        var nextScreen: Screen?
        // merge new import results into the model import summary keeping the original DataType sorting order
        for (dataType, result) in DataType.allCases.compactMap({ dataType in summary[dataType].map { (dataType, $0) } }) {
            let sourceVersion = importSource.installedAppsMajorVersionDescription(selectedProfile: selectedProfile)
            switch result {
            case .success(let dataTypeSummary):
                if dataTypeSummary.isEmpty, nextScreen == nil {
                    switch screen {
                    case .archiveImport(let dataTypes, _):
                        nextScreen = .archiveImport(dataTypes: dataTypes, summary: summary)
                    default:
                        // if a data type can‘t be imported - switch to its file import displaying successful import results
                        nextScreen = .fileImport(dataType: dataType, summary: summary)
                    }
                }

                PixelKit.fire(GeneralPixel.dataImportSucceeded(action: .init(dataType), source: importSource.pixelSourceParameterName, sourceVersion: sourceVersion), frequency: .dailyAndStandard)
            case .failure(let error):
                // successful imports are appended above
                self.summary.append( .init(dataType, result) )

                if case .archiveImport(let dataTypes, _) = screen,
                    summary.first(where: { $0.value.isSuccess }) == nil {
                    nextScreen = .archiveImport(dataTypes: dataTypes, summary: summary)
                }

                // show file import screen when import fails or no bookmarks|passwords found
                if !((screen.isFileImport && screen.fileImportDataType == dataType) || screen.isArchiveImport), nextScreen == nil {
                    // switch to file import of the failed data type displaying successful import results
                    nextScreen = .fileImport(dataType: dataType, summary: summary)
                }
                PixelKit.fire(GeneralPixel.dataImportFailed(source: importSource.pixelSourceParameterName, sourceVersion: sourceVersion, error: error), frequency: .dailyAndStandard)
            }
        }

        if let nextScreen {
            Logger.dataImportExport.debug("mergeImportSummary: next screen: \(String(describing: nextScreen))")
            self.screen = nextScreen
        } else {
            Logger.dataImportExport.debug("mergeImportSummary: intermediary summary(\(Set(summary.keys)))")
            self.screen = .summary(summary)
            completeAndCleanupWideEvent(with: summary)
        }

        if self.areAllSelectedDataTypesSuccessfullyImported {
            successfulImportHappened = true
            NotificationCenter.default.post(name: .dataImportComplete, object: nil)
        }
    }

    /// handle recoverable errors (request primary password or file permission)
    @MainActor
    private mutating func handleErrors(_ summary: [DataType: any DataImportError]) -> Bool {
        errors.append(summary)
        for error in summary.values {
            switch error {
                // chromium user denied keychain prompt error
            case let error as ChromiumLoginReader.ImportError where error.type == .userDeniedKeychainPrompt:
                PixelKit.fire(GeneralPixel.passwordImportKeychainPromptDenied)
                if screen == .passwordEntryHelp {
                    // User already saw help, go back to start
                    goBack()
                } else {
                    // First time seeing the error, show help
                    screen = .passwordEntryHelp
                }
                return true

                // firefox passwords db is main-password protected: request password
            case let error as FirefoxLoginReader.ImportError where error.type == .requiresPrimaryPassword:

                Logger.dataImportExport.debug("primary password required")
                // stay on the same screen but request password synchronously
                if let password = self.requestPrimaryPasswordCallback(importSource) {
                    self.initiateImport(primaryPassword: password)
                }
                return true

                // no file read permission error: user must grant permission
            case let importError where (importError.underlyingError as? CocoaError)?.code == .fileReadNoPermission:
                guard let error = importError.underlyingError as? CocoaError,
                      let url = error.filePath.map(URL.init(fileURLWithPath:)) ?? error.url else {
                    assertionFailure("No url")
                    break
                }
                Logger.dataImportExport.debug("file read no permission for \(url.path)")

                if url != selectedProfile?.profileURL.appendingPathComponent(SafariDataImporter.Constants.bookmarksFileName) {
                    PixelKit.fire(GeneralPixel.dataImportFailed(source: importSource.pixelSourceParameterName, sourceVersion: importSource.installedAppsMajorVersionDescription(selectedProfile: selectedProfile), error: importError), frequency: .dailyAndStandard)
                }

                // On macOS < 15.2, show permission request screen to let user grant access
                if #unavailable(macOS 15.2) {
                    screen = .getReadPermission(url)
                    return true
                }

            default: continue
            }
        }
        return false
    }

    /// Skip button press
    @MainActor mutating func skipImportOrDismiss(using dismiss: @escaping () -> Void) {
        if let screen = screenForNextDataTypeRemainingToImport(after: screen.fileImportDataType) {
            // skip to next non-imported data type
            self.screen = screen
        } else {
            let importSummary = summary.reduce(into: [:]) { result, element in
                result[element.dataType] = element.result
            }
            self.screen = .summary(importSummary)
            completeAndCleanupWideEvent(with: importSummary)
        }
    }

    /// Select CSV/HTML file for import button press
    @MainActor mutating func selectFile() {
        setupAndStartWideEventIfNeeded()
        let dataTypes: [UTType]
        switch screen {
        case .fileImport(dataType: let dataType, summary: _):
            dataTypes = dataType.allowedFileTypes
        case .archiveImport:
            dataTypes = Array(importSource.archiveImportSupportedFiles)
        case .sourceAndDataTypesPicker:
            dataTypes = importSource.supportedDataTypes.flatMap { $0.allowedFileTypes }
        default:
            assertionFailure("Expected File Import")
            return
        }

        guard let url = openPanelCallback(dataTypes) else { return }

        // If the source is .fileImport, detect the file type and switch to the appropriate source (.csv or .bookmarksHTML)
        guard switchFromFileImportToSpecificSourceIfNeeded(fileURL: url) else { return }

        self.initiateImport(fileURL: url)
    }

    /// Detects the data type (passwords or bookmarks) from a file URL
    private func detectDataType(from url: URL) -> DataType? {
        if let resourceValues = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
           let typeIdentifier = resourceValues.typeIdentifier,
           let fileType = UTType(typeIdentifier) {
            if fileType.conforms(to: .commaSeparatedText) {
                return .passwords
            } else if fileType.conforms(to: .html) {
                return .bookmarks
            }
        }

        // Fallback to file extension if UTType detection fails
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "csv" {
            return .passwords
        } else if pathExtension == "html" || pathExtension == "htm" {
            return .bookmarks
        }

        return nil
    }

    /// If using a source of `.fileImport`, this function detects the file type and switches to the appropriate specific source (.csv or .bookmarksHTML).
    /// - Parameter fileURL: The URL of the selected file
    /// - Returns: `true` if the operation succeeded or was not needed, `false` if detection failed
    /// - Note: This will reset the screen to .sourceAndDataTypesPicker, which matches the behavior
    ///   of the standalone CSV/HTML options so error handling works the same way.
    @MainActor
    private mutating func switchFromFileImportToSpecificSourceIfNeeded(fileURL: URL) -> Bool {
        guard importSource == .fileImport else {
            return true
        }

        // Detection should always succeed since the file picker filters to CSV/HTML files
        guard let detectedDataType = detectDataType(from: fileURL) else {
            assertionFailure("Failed to detect data type for file: \(fileURL.path). Expected only a CSV or HTML file.")
            return false
        }

        let newSource: Source = detectedDataType == .passwords ? .csv : .bookmarksHTML

        self.update(with: newSource)

        if !selectedDataTypes.contains(detectedDataType) {
            selectedDataTypes = [detectedDataType]
        }

        return true
    }

    mutating func goBack() {
        if case .summaryDetail(let summary, _) = screen {
            screen = .summary(summary)
            completeAndCleanupWideEvent(with: summary)
        } else {
            screen = .sourceAndDataTypesPicker
            summary.removeAll()
        }
    }

    func submitReport() {
        let sendReport = reportSenderFactory()
        sendReport(reportModel)
    }

    @MainActor
    mutating func launchSync(using dismiss: @escaping () -> Void, completion: (() -> Void)? = nil) {
        guard case .show(let syncLauncher) = syncFeatureVisibility else {
            return
        }
        let syncTouchpoint: SyncDeviceButtonTouchpoint = screen == .sourceAndDataTypesPicker ? .dataImportStart : .dataImportFinish
        syncLauncher.startDeviceSyncFlow(source: syncTouchpoint) {
            completion?()
        }
        self.dismiss(using: dismiss)
    }
}

@MainActor
private func dataImporter(for source: DataImport.Source, fileDataType: DataImport.DataType?, url: URL, primaryPassword: String?) -> DataImporter {

    var profile: DataImport.BrowserProfile {
        let browser = ThirdPartyBrowser.browser(for: source) ?? {
            assertionFailure("Trying to get browser name for file import source \(source)")
            return .chrome
        }()
        return DataImport.BrowserProfile(browser: browser, profileURL: url)
    }
    return switch source {
    case .bookmarksHTML,
        /* any */_ where fileDataType == .bookmarks:

        BookmarkHTMLImporter(fileURL: url, bookmarkImporter: CoreDataBookmarkImporter(bookmarkManager: NSApp.delegateTyped.bookmarkManager))
    case .fileImport: {
        assertionFailure("Unexpected .fileImport source in dataImporter. Source should have been switched to .csv or .bookmarksHTML earlier.")

        // Fallback to CSV importer as a safety measure
        return CSVImporter(fileURL: url, loginImporter: SecureVaultLoginImporter(loginImportState: AutofillLoginImportState()), defaultColumnPositions: .init(source: .csv), reporter: SecureVaultReporter.shared, tld: Application.appDelegate.tld)
    }()
    case .onePassword8, .onePassword7, .bitwarden, .lastPass, .csv,
        /* any */_ where fileDataType == .passwords:
        CSVImporter(fileURL: url, loginImporter: SecureVaultLoginImporter(loginImportState: AutofillLoginImportState()), defaultColumnPositions: .init(source: source), reporter: SecureVaultReporter.shared, tld: Application.appDelegate.tld)

    case .brave, .chrome, .chromium, .coccoc, .edge, .opera, .operaGX, .vivaldi:
        ChromiumDataImporter(profile: profile,
                             loginImporter: SecureVaultLoginImporter(loginImportState: AutofillLoginImportState()),
                             bookmarkImporter: CoreDataBookmarkImporter(bookmarkManager: NSApp.delegateTyped.bookmarkManager))
    case .yandex:
        YandexDataImporter(profile: profile,
                           bookmarkImporter: CoreDataBookmarkImporter(bookmarkManager: NSApp.delegateTyped.bookmarkManager),
                           featureFlagger: Application.appDelegate.featureFlagger)
    case .firefox, .tor:
        FirefoxDataImporter(profile: profile,
                            primaryPassword: primaryPassword,
                            loginImporter: SecureVaultLoginImporter(loginImportState: AutofillLoginImportState()),
                            bookmarkImporter: CoreDataBookmarkImporter(bookmarkManager: NSApp.delegateTyped.bookmarkManager),
                            faviconManager: NSApp.delegateTyped.faviconManager)
    case .safari, .safariTechnologyPreview:
        if #available(macOS 15.2, *), !source.archiveImportSupportedFiles.isEmpty {
            SafariArchiveImporter(archiveURL: url,
                                  bookmarkImporter: CoreDataBookmarkImporter(bookmarkManager: NSApp.delegateTyped.bookmarkManager),
                                  loginImporter: SecureVaultLoginImporter(loginImportState: AutofillLoginImportState()),
                                  faviconManager: NSApp.delegateTyped.faviconManager,
                                  featureFlagger: Application.appDelegate.featureFlagger,
                                  secureVaultReporter: SecureVaultReporter.shared,
                                  tld: Application.appDelegate.tld)
        } else {
            SafariDataImporter(profile: profile,
                               bookmarkImporter: CoreDataBookmarkImporter(bookmarkManager: NSApp.delegateTyped.bookmarkManager))
        }
    }
}

private var isOpenPanelShownFirstTime = true
private var openPanelDirectoryURL: URL? {
    // only show Desktop once per launch, then open the last user-selected dir
    if isOpenPanelShownFirstTime {
        isOpenPanelShownFirstTime = false
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    } else {
        return nil
    }
}

extension DataImport.DataType {

    static func dataTypes(before dataType: DataImport.DataType, inclusive: Bool) -> [Self].SubSequence {
        let index = Self.allCases.firstIndex(of: dataType)!
        if inclusive {
            return Self.allCases[...index]
        } else {
            return Self.allCases[..<index]
        }
    }

    static func dataTypes(after dataType: DataImport.DataType) -> [Self].SubSequence {
        let nextIndex = Self.allCases.firstIndex(of: dataType)! + 1
        return Self.allCases[nextIndex...]
    }

    var allowedFileTypes: [UTType] {
        switch self {
        case .bookmarks: [.html]
        case .passwords: [.commaSeparatedText]
        case .creditCards: [.json]
        }
    }
}

extension DataImportViewModel {

    /// Determines the selected data types when switching import sources.
    /// - Parameters:
    ///   - previousSelectedTypes: Types that were selected in the previous import source, if any
    ///   - availableTypes: Types available for the new import source
    /// - Returns: The newly selected data types based on the following logic:
    ///   - Preserve previous selections, filtered to available types in the new source.
    ///   - If none of the previously selected types are available, fallback to select all available types.
    ///   - If no previous selection exists, default to all available types.
    static func determineSelectedDataTypes(previousSelectedTypes: Set<DataType>?, availableTypes: Set<DataType>) -> Set<DataType> {
        guard let previousSelectedTypes else {
            return availableTypes
        }

        let availablePreviousTypes = Set(previousSelectedTypes.filter { availableTypes.contains($0) })

        return availablePreviousTypes.isEmpty ? availableTypes : availablePreviousTypes
    }

    private var areAllSelectedDataTypesSuccessfullyImported: Bool {
        selectedDataTypes.allSatisfy(isDataTypeSuccessfullyImported)
    }

    func summary(for dataType: DataType) -> DataTypeSummary? {
        if case .success(let summary) = self.summary.last(where: { $0.dataType == dataType })?.result {
            return summary
        }
        return nil
    }

    func isDataTypeSuccessfullyImported(_ dataType: DataType) -> Bool {
        summary(for: dataType) != nil
    }

    private func screenForNextDataTypeRemainingToImport(after currentDataType: DataType? = nil) -> Screen? {
        // keep the original sort order among all data types or only after current data type
        for dataType in (currentDataType.map { DataType.dataTypes(after: $0) } ?? DataType.allCases[0...]) where selectedDataTypes.contains(dataType) {
            // if some of selected data types failed to import or not imported yet
            switch summary.last(where: { $0.dataType == dataType })?.result {
            case .success(let summary) where summary.isEmpty:
                return .fileImport(dataType: dataType)
            case .failure(let error) where error.errorType == .noData:
                return .fileImport(dataType: dataType)
            case .failure, .none:
                return .fileImport(dataType: dataType)
            case .success:
                continue
            }
        }
        return nil
    }

    mutating func showSummaryDetail(summary: DataImportSummary, type: DataType) {
        self.screen = .summaryDetail(summary, type)
    }

    func error(for dataType: DataType) -> (any DataImportError)? {
        if case .failure(let error) = summary.last(where: { $0.dataType == dataType })?.result {
            return error
        }
        return nil
    }

    private struct DataImportViewSummarizedError: LocalizedError {
        let errors: [any DataImportError]

        var errorDescription: String? {
            errors.enumerated().map {
                "\($0.offset + 1): \($0.element.localizedDescription)"
            }.joined(separator: "\n")
        }
    }

    var summarizedError: LocalizedError {
        let errors = summary.compactMap { $0.result.error }
        if errors.count == 1 {
            return errors[0]
        }
        return DataImportViewSummarizedError(errors: errors)
    }

    var hasAnySummaryError: Bool {
        !summary.allSatisfy { $0.result.isSuccess }
    }

    private static func requestPrimaryPasswordCallback(_ source: DataImport.Source) -> String? {
        let alert = NSAlert.passwordRequiredAlert(source: source)
        let response = alert.runModal()

        guard case .alertFirstButtonReturn = response,
              let password = (alert.accessoryView as? NSSecureTextField)?.stringValue else { return nil }

        return password
    }

    private static func openPanelCallback(for allowedFileTypes: [UTType]) -> URL? {
        let panel = NSOpenPanel(allowedFileTypes: allowedFileTypes,
                                directoryURL: openPanelDirectoryURL)
        guard case .OK = panel.runModal(),
              let url = panel.url else { return nil }

        return url
    }

    var isImportSourcePickerDisabled: Bool {
        importTask != nil
    }

    // AsyncStream of Data Import task progress events
    var importProgress: TaskProgress<Self, Never, DataImportProgressEvent>? {
        guard let importTask else { return nil }
        return AsyncStream {
            for await event in importTask.progress {
                switch event {
                case .progress(let update):
                    Logger.dataImportExport.debug("progress: \(String(describing: update))")
                    return .progress(update)
                    // on completion returns new DataImportViewModel with merged import summary
                case .completed(.success(let summary)):
                    onFinished()
                    return await .completed(.success(self.mergingImportSummary(summary)))
                }
            }
            return nil
        }
    }

    enum ButtonType: Hashable {

        case initiateImport(disabled: Bool)
        case selectFile
        case skip
        case cancel
        case back
        case done
        case submit
        case `continue`
        case sync
        case close

        var isDisabled: Bool {
            switch self {
            case .initiateImport(disabled: let disabled):
                return disabled
            case .skip, .done, .cancel, .back, .submit, .continue, .selectFile, .sync, .close:
                return false
            }
        }
    }

    @MainActor var actionButton: ButtonType? {
        func initiateImport() -> ButtonType {
            .initiateImport(disabled: selectedDataTypes.isEmpty || importTask != nil)
        }

        switch screen {
        case .sourceAndDataTypesPicker:
            if importSource == .csv || importSource == .bookmarksHTML || importSource == .fileImport {
                return .selectFile
            } else {
                return initiateImport()
            }

        case .profilePicker:
            return .continue
        case .moreInfo:
            return initiateImport()
        case .getReadPermission:
            return nil
        case .passwordEntryHelp:
            return nil

        case .archiveImport:
            return nil
        case .fileImport(_, let summary):
            return summary.isEmpty ? nil : .skip
        case .summary(let summary):
            guard summary.values.filter({ !$0.isSuccess }).isEmpty else {
                return .submit
            }
            switch syncFeatureVisibility {
            case .hide:
                return nil
            case .show:
                return .sync
            }
        case .summaryDetail:
            return nil
        }
    }

    var secondaryButton: ButtonType? {
        if importTask == nil {
            switch screen {
            case .sourceAndDataTypesPicker:
                return .cancel
            case .archiveImport, .profilePicker, .moreInfo, .getReadPermission:
                return .back
            case .passwordEntryHelp:
                return .cancel
            case .fileImport(_, let summary):
                return summary.isEmpty ? .back : nil
            case .summary:
                return .done
            case .summaryDetail:
                return .back
            }
        } else {
            return .cancel
        }
    }

    var shouldShowSyncFooterButton: Bool {
        switch screen {
        case .summary:
            return true
        default:
            return false
        }
    }

    var isSelectFileButtonDisabled: Bool {
        importTask != nil
    }

    @MainActor var buttons: [ButtonType] {
        [secondaryButton, actionButton].compactMap { $0 }
    }

    mutating func update(with importSource: Source) {
        if let dataImportWideEventData {
            wideEvent.discardFlow(dataImportWideEventData)
            self.dataImportWideEventData = nil
        }
        self = .init(importSource: importSource,
                     selectedDataTypes: self.selectedDataTypes,
                     isPickerExpanded: self.isPickerExpanded,
                     isPasswordManagerAutolockEnabled: isPasswordManagerAutolockEnabled,
                     syncFeatureVisibility: syncFeatureVisibility,
                     loadProfiles: loadProfiles,
                     dataImporterFactory: dataImporterFactory,
                     requestPrimaryPasswordCallback: requestPrimaryPasswordCallback,
                     reportSenderFactory: reportSenderFactory,
                     onFinished: onFinished,
                     onCancelled: onCancelled)
    }

    /// Selects a profile and filters selected data types to only include types available for that profile.
    /// This should be called when the user selects a profile from the profile picker screen.
    /// - Parameter profile: The profile to select
    @MainActor
    mutating func selectProfile(_ profile: BrowserProfile) {
        self.selectedProfile = profile

        // Filter selected data types to only include types available for this specific profile
        let availableTypesForProfile = importSource.supportedDataTypes.filter { dataType in
            profile.hasValidProfileData(for: dataType)
        }
        selectedDataTypes = selectedDataTypes.intersection(availableTypesForProfile)
    }

    @MainActor
    mutating func performAction(for buttonType: ButtonType, dismiss: @escaping () -> Void) {
        switch buttonType {
        case .back, .close:
            goBack()

        case .initiateImport, .continue:
            importButtonPressed()

        case .selectFile:
            selectFile()

        case .skip:
            skipImportOrDismiss(using: dismiss)

        case .cancel:
            if screen == .passwordEntryHelp {
                goBack()
            } else {
                importTask?.cancel()
                onCancelled()
                self.dismiss(using: dismiss)
            }

        case .submit:
            submitReport()
            self.dismiss(using: dismiss)
        case .done:
            self.dismiss(using: dismiss)
        case .sync:
            launchSync(using: dismiss)
        }
    }

    @MainActor
    mutating func importButtonPressed() {
        setupAndStartWideEventIfNeeded()
        guard let importer = selectedProfile.map({
            dataImporterFactory(/* importSource: */ importSource,
                                /* dataType: */ nil,
                                /* profileURL: */ $0.profileURL,
                                /* primaryPassword: */ nil)
        }), selectedDataTypes.intersects(importer.importableTypes) else {
            if #available(macOS 15.2, *), .safari == importSource {
                screen = .archiveImport(dataTypes: importSource.supportedDataTypes)
                return
            }

            if let browserProfiles, browserProfiles.validImportableProfiles.count > 1 {
                self.screen = .profilePicker
                return
            }

            // no profiles found
            // or selected data type not supported by selected browser data importer
            guard let type = DataType.allCases.filter(selectedDataTypes.contains).first else {
                // disabled Import button
                return initiateImport()
            }

            screen = .fileImport(dataType: type)
            return
        }
        if screen != .profilePicker, let browserProfiles, browserProfiles.validImportableProfiles.count > 1 {
            self.screen = .profilePicker
            return
        }
        if importer.requiresKeychainPassword(for: selectedDataTypes) {
            screen = .moreInfo
        }
        initiateImport()
    }

    private mutating func dismiss(using dismiss: @escaping () -> Void) {
        // send `bookmarkPromptShouldShow` notification after dismiss if at least one bookmark was imported
        if summary.reduce(into: 0, { $0 += $1.dataType == .bookmarks ? (try? $1.result.get().successful) ?? 0 : 0 }) > 0 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .bookmarkPromptShouldShow, object: nil)
            }
        }

        Logger.dataImportExport.debug("dismiss")
        dismiss()
        if case .xcPreviews = AppVersion.runType {
            self.update(with: importSource) // reset
        }
    }

    @MainActor
    private func mergingImportSummary(_ summary: DataImportSummary) -> Self {
        var newState = self
        newState.mergeImportSummary(with: summary)
        return newState
    }

    private var retryNumber: Int {
        summary.reduce(into: [:]) {
            // get maximum number of failures per data type
            $0[$1.dataType, default: 0] += $1.result.isSuccess ? 0 : 1
        }.values.max() ?? 0
    }

    var reportModel: DataImportReportModel {
        get {
            DataImportReportModel(importSource: importSource,
                                  importSourceVersion: importSource.installedAppsMajorVersionDescription(selectedProfile: selectedProfile),
                                  error: summarizedError,
                                  text: userReportText,
                                  retryNumber: retryNumber)
        }
        set {
            userReportText = newValue.text
        }
    }

}

// MARK: - Wide Event

private extension DataImportViewModel {
    mutating func setupAndStartWideEventIfNeeded() {
        guard isDataImportWideEventMeasurementEnabled, self.dataImportWideEventData == nil else { return }
        let data = DataImportWideEventData(
            source: importSource,
            contextData: WideEventContextData(name: "funnel_default_macos")
        )
        self.dataImportWideEventData = data
        self.dataImportWideEventData?.overallDuration = WideEvent.MeasuredInterval.startingNow()
        wideEvent.startFlow(data)
    }

    mutating func startDurationMeasurement(for types: Set<DataType>) {
        for type in types {
            dataImportWideEventData?[keyPath: type.importerDurationPath] = WideEvent.MeasuredInterval.startingNow()
        }
    }

    mutating func completeDurationMeasurement(for type: DataType, with status: WideEventStatus, error: WideEventErrorData? = nil) {
        guard isDataImportWideEventMeasurementEnabled else { return }
        dataImportWideEventData?[keyPath: type.importerDurationPath]?.complete()
        dataImportWideEventData?[keyPath: type.statusPath] = status
        if let error = error {
            dataImportWideEventData?[keyPath: type.errorPath] = error
        } else {
            dataImportWideEventData?[keyPath: type.errorPath] = nil
        }
    }

    mutating func completeDurationMeasurement(with importSummary: DataImportSummary) {
        guard isDataImportWideEventMeasurementEnabled else { return }

        for type in DataType.allCases {
            guard let result = importSummary[type] else { continue }

            switch result {
            case .success(let typeSummary):
                if typeSummary.isAllSuccessful {
                    completeDurationMeasurement(for: type, with: .success)
                } else {
                    completeDurationMeasurement(for: type, with: .success(
                        reason: DataImportWideEventData.StatusReason.partialData.rawValue
                    ))
                }
            case .failure(let error):
                completeDurationMeasurement(for: type, with: .failure, error: WideEventErrorData(
                                                error: error,
                    description: error.errorType.description
                ))
            }
        }
    }

    mutating func completeAndCleanupWideEvent(with importSummary: DataImportSummary) {
        guard isDataImportWideEventMeasurementEnabled, let data = dataImportWideEventData else { return }

        completeDurationMeasurement(with: importSummary)
        data.overallDuration?.complete()

        // Overall status
        if importSummary.allSatisfy({ !$1.isSuccess }) {
            wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
            self.dataImportWideEventData = nil
            return
        }

        if importSummary.allSatisfy({ ((try? $1.get().isAllSuccessful) ?? false) }) {
            wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
            self.dataImportWideEventData = nil
            return
        }

        wideEvent.completeFlow(data, status: .success(reason: DataImportWideEventData.StatusReason.partialData.rawValue), onComplete: { _, _ in })
        self.dataImportWideEventData = nil
    }
}
