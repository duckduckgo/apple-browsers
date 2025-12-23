//
//  LegacyDataImportView.swift
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
import BrowserServicesKit
import DesignResourcesKitIcons
import PixelKit
import PrivacyConfig
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LegacyDataImportView: ModalView {
    private let isDataTypePickerExpanded: Bool
    @Environment(\.dismiss) private var dismiss

    @State var model: LegacyDataImportViewModel
    let title: String

    let importFlowLauncher: LegacyDataImportFlowRelaunching

    @State private var isInternalUser = false
    let internalUserDecider: InternalUserDecider = Application.appDelegate.internalUserDecider

    private let syncFeatureVisibility: SyncFeatureVisibility

    init(model: LegacyDataImportViewModel = LegacyDataImportViewModel(), importFlowLauncher: LegacyDataImportFlowRelaunching, title: String = UserText.importDataTitle, isDataTypePickerExpanded: Bool, syncFeatureVisibility: SyncFeatureVisibility) {
        self._model = State(initialValue: model)
        self.importFlowLauncher = importFlowLauncher
        self.title = title
        self.isDataTypePickerExpanded = isDataTypePickerExpanded
        self.syncFeatureVisibility = syncFeatureVisibility
    }

    struct ProgressState {
        let text: String?
        let fraction: Double?
        let updated: CFTimeInterval
    }
    @State private var progress: ProgressState?

#if DEBUG || REVIEW
    @State private var debugViewDisabled: Bool = false
#endif

    private var shouldShowDebugView: Bool {
#if DEBUG || REVIEW
        return !debugViewDisabled
#else
        return (!model.errors.isEmpty && isInternalUser)
#endif
    }

    private var alignment: HorizontalAlignment {
        if case .summary = model.screen {
            return .leading
        } else {
            return .center
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            viewHeader()
                .padding(.top, 30)
                .padding(.leading, 20)
                .padding(.trailing, 20)
                .padding(.bottom, 0)

            viewBody()
                .padding(.leading, 20)
                .padding(.trailing, 20)
                .padding(.bottom, 26)
                .padding(.top, 0)

            // if import in progress…
            if let importProgress = model.importProgress {
                progressView(importProgress)
                    .padding(.leading, 20)
                    .padding(.trailing, 20)
                    .padding(.bottom, 8)
            }

            viewFooter()
                .padding(.bottom, 26)
                .padding(.horizontal, 20)

            if shouldShowDebugView {
                debugView()
            }
        }
        .font(.system(size: 13))
        .frame(width: 420)
        .fixedSize()
        .onReceive(internalUserDecider.isInternalUserPublisher.removeDuplicates()) {
            isInternalUser = $0
        }
    }

    @ViewBuilder
    private func viewHeader() -> some View {
        switch model.screen {
        case .summary where !model.hasAnySummaryError:
            summarySuccessHeader
        case .shortcuts:
            shortcutsHeader
        default:
            defaultHeader
        }
    }

    @ViewBuilder
    private var summarySuccessHeader: some View {
        VStack(alignment: .leading) {
            Image(.success96)
            Text(UserText.importDataSuccessTitle)
                .foregroundColor(.primary)
                .font(.system(size: 17, weight: .bold))
        }
        .padding(.bottom, 16)
    }

    private var shortcutsHeader: some View {
        Text(UserText.importDataShortcutsTitle)
            .font(.title2.weight(.semibold))
            .padding(.bottom, 20)
    }

    @ViewBuilder
    private var defaultHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            // If screen is not the first screen where the user choose the type of import they want to do show the generic title.
            // Otherwise show the injected title.
            let title = model.screen == .profileAndDataTypesPicker ? self.title : UserText.importDataTitle

            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.bottom, 20)
        }
    }

    @ViewBuilder var importSourcePicker: some View {
        // browser to import data from picker popup
        DataImportSourcePicker(importSources: model.availableImportSources, selectedSource: model.importSource) { importSource in
            model.update(with: importSource)
        }
        .padding(.bottom, 8)
        .disabled(model.isImportSourcePickerDisabled)
    }

    @ViewBuilder
    private func viewBody() -> some View {
        VStack(alignment: .center, spacing: 0) {
            // body
            switch model.screen {
            case .profileAndDataTypesPicker:
                profileAndDataTypesPickerBody
            case .moreInfo:
                // you will be asked for your keychain password blah blah...
                moreInfoBody
            case .getReadPermission(let url):
                // give request to Safari folder, select Bookmarks.plist using open panel
                getReadPermissionBody(url: url)
            case .fileImport(let dataType, let summaryTypes):
                fileImportBody(dataType: dataType, summaryTypes: summaryTypes)
            case .archiveImport:
                multifileImportBody(fileTypes: model.importSource.archiveImportSupportedFiles)
            case .summary(let dataTypes, let previousScreen):
                LegacyDataImportSummaryView(model, dataTypes: dataTypes, isFileImport: previousScreen.isFileImport)
            case .feedback:
                feedbackBody
            case .shortcuts(let dataTypes):
                DataImportShortcutsView(dataTypes: dataTypes)
            }
        }
    }

    @ViewBuilder
    private var profileAndDataTypesPickerBody: some View {
        passwordsExplainerView().padding(.bottom, 20).padding(.horizontal, 20).frame(alignment: .center)
        importPickerPanel {
            VStack(alignment: .leading, spacing: 8) {
                // Browser Profile picker
                if model.browserProfiles?.validImportableProfiles.count ?? 0 > 1 {
                    DataImportProfilePicker(profileList: model.browserProfiles,
                                            selectedProfile: $model.selectedProfile)
                    .padding(.bottom, 8)
                    .disabled(model.isImportSourcePickerDisabled)
                }

                LegacyDataImportTypePicker(viewModel: $model, isDataTypePickerExpanded: isDataTypePickerExpanded)
                    .disabled(model.isImportSourcePickerDisabled)
                .padding(.top, 8)
            }
        }

        if case .show(let syncLauncher) = syncFeatureVisibility {
            Button {
                dismiss.callAsFunction()
                let source = SyncDeviceButtonTouchpoint.dataImportStart
                PixelKit.fire(SyncPromoPixelKitEvent.syncPromoConfirmed, withAdditionalParameters: ["source": source.rawValue], doNotEnforcePrefix: true)
                syncLauncher.startDeviceSyncFlow(source: source) {
                    importFlowLauncher.relaunchDataImport(model: model, title: title, isDataTypePickerExpanded: isDataTypePickerExpanded)
                }
            } label: {
                Text(UserText.importDataSelectionSyncButtonTitle)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(.linkBlue))
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
    }

    @ViewBuilder
    private var moreInfoBody: some View {
        importPickerPanel {
            BrowserImportMoreInfoView(source: model.importSource)
        }
    }

    @ViewBuilder
    private var feedbackBody: some View {
        importSourceDataTitle
        VStack(alignment: .leading, spacing: 0) {
            LegacyDataImportSummaryView(model)
                .padding(.bottom, 20)
            ReportFeedbackView(model: $model.reportModel)
        }
    }

    @ViewBuilder
    private func getReadPermissionBody(url: URL) -> some View {
        importPickerPanel {
            RequestFilePermissionView(source: model.importSource, url: url, requestDataDirectoryPermission: SafariDataImporter.requestDataDirectoryPermission) { _ in
                model.initiateImport()
            }
        }
    }

    @ViewBuilder
    private func fileImportBody(dataType: DataImport.DataType, summaryTypes: Set<DataImport.DataType>) -> some View {
        importPickerPanel {
            VStack(alignment: .leading, spacing: 0) {
                if !summaryTypes.isEmpty {
                    LegacyDataImportSummaryView(model, dataTypes: summaryTypes)
                        .padding(.bottom, 24)
                }

                // if no data to import
                if model.summary(for: dataType)?.isEmpty == true
                    || model.error(for: dataType)?.errorType == .noData {
                    DataImportNoDataView(source: model.importSource, dataType: dataType)
                        .padding(.bottom, 24)
                // if browser importer failed - display error message
                } else if model.error(for: dataType) != nil {
                    DataImportErrorView(source: model.importSource, dataType: dataType)
                        .padding(.bottom, 24)
                }

                // manual file import instructions for CSV/HTML
                FileImportView(source: model.importSource, dataType: dataType, isButtonDisabled: model.isSelectFileButtonDisabled) {
                    model.selectFile()
                } onFileDrop: { url in
                    model.initiateImport(fileURL: url)
                }
            }
        }

    }

    @ViewBuilder
    private func multifileImportBody(fileTypes: Set<UTType>) -> some View {
        importPickerPanel(bottomPadding: 4) {
            EmptyView()
        }
        .padding(.bottom, 20)
        VStack(alignment: .leading) {
            // manual file import instructions for CSV/HTML
            NewFileImportView(source: model.importSource, allowedFileTypes: Array(fileTypes), isButtonDisabled: model.isSelectFileButtonDisabled, kind: .archive) {
                model.selectFile()
            } onFileDrop: { url in
                model.initiateImport(fileURL: url)
            }

            if case .failure(let error) = model.summary.last?.result,
               let error = error as? SafariArchiveImporter.ImportError,
               error.type == .unarchive || error.type == .importContents {
                HStack {
                    Image(nsImage: DesignSystemImages.Color.Size16.exclamationHigh)
                    Text("Incorrect file type or format. Please select a different file.")
                        .foregroundColor(Color(designSystemColor: .destructivePrimary))
                }
                .padding(.vertical, 20)
            }
        }
    }

    private func importPickerPanel<Content: View>(bottomPadding: CGFloat = 12, _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            importSourceDataTitle
            importSourcePicker
            content()
        }
        .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, bottomPadding)
        .padding(.top, 12)
        .padding(.horizontal, 12)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.decorationTertiary, lineWidth: 1)
        )
    }

    private var importSourceDataTitle: some View {
        Text(UserText.importDataSourceTitle)
    }

    private func progressView(_ progress: TaskProgress<LegacyDataImportViewModel, Never, DataImportProgressEvent>) -> some View {
        // Progress bar with label: Importing [bookmarks|passwords]…
        ProgressView(value: self.progress?.fraction) {
            Text(self.progress?.text ?? "")
        }
        .task {
            // when model.importProgress async sequence not nil
            // receive progress updates events and update model on completion
            await handleImportProgress(progress)
        }
    }

    // under line buttons
    private func viewFooter() -> some View {
        HStack(spacing: 8) {
            if case .show(let syncLauncher) = syncFeatureVisibility, model.shouldShowSyncFooterButton {
                Button(UserText.legacyImportDataCompleteSyncButtonTitle) {
                    dismiss.callAsFunction()
                    let source = SyncDeviceButtonTouchpoint.dataImportFinish
                    PixelKit.fire(SyncPromoPixelKitEvent.syncPromoConfirmed, withAdditionalParameters: ["source": SyncDeviceButtonTouchpoint.dataImportFinish.rawValue], doNotEnforcePrefix: true)
                    syncLauncher.startDeviceSyncFlow(source: source, completion: nil)
                }
            }
            Spacer()

            ForEach(model.buttons.indices, id: \.self) { idx in
                Button {
                    model.performAction(for: model.buttons[idx],
                                        dismiss: dismiss.callAsFunction)
                } label: {
                    Text(model.buttons[idx].title(dataType: model.screen.fileImportDataType))
                        .frame(minWidth: 80 - 16 - 1)
                }
                .keyboardShortcut(model.buttons[idx].shortcut)
                .disabled(model.buttons[idx].isDisabled)
            }
        }
    }

    private func passwordsExplainerView() -> some View {
        HStack(alignment: .top, spacing: 8) {
            (
                Text(Image(.lockSolid16)).baselineOffset(-1.0)
                +
                Text(verbatim: " ")
                +
                Text(model.isPasswordManagerAutolockEnabled ? UserText.importLoginsPasswordsExplainer : UserText.importLoginsPasswordsExplainerAutolockOff)
            )
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func handleImportProgress(_ progress: TaskProgress<LegacyDataImportViewModel, Never, DataImportProgressEvent>) async {
        // receive import progress update events
        // the loop is completed on the import task
        // cancellation/completion or on did disappear
        for await event in progress {
            switch event {
            case .progress(let progress):
                let currentTime = CACurrentMediaTime()
                // throttle progress updates
                if (self.progress?.updated ?? 0) < currentTime - 0.2 {
                    self.progress = .init(text: progress.description,
                                          fraction: progress.fraction,
                                          updated: currentTime)
                }

                // update view model on completion
            case .completed(.success(let newModel)):
                self.model = newModel
            }
        }
    }

    private func debugView() -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
#if DEBUG || REVIEW
                Text("REVIEW:" as String).bold()
                    .padding(.top, 10)
                    .padding(.leading, 20)

                ForEach(model.selectableImportTypes.filter(model.selectedDataTypes.contains), id: \.self) { selectedDataType in
                    failureReasonPicker(for: selectedDataType)
                        .padding(.leading, 20)
                        .padding(.trailing, 20)
                }

                if model.errors.count > 0 && isInternalUser {
                    Divider()
                }
#endif

                if model.errors.count > 0 && isInternalUser {
                    Text(verbatim: "ERRORS:" as String).bold()
                        .padding(.top, 10)
                        .padding(.leading, 20)

                    ForEach(model.errors.indices, id: \.self) { i in
                        ForEach(Array(model.errors[i].keys), id: \.self) { key in
                            if let value = model.errors[i][key] {
                                if #available(macOS 12.0, *) {
                                    Text(verbatim: "\(key.rawValue.uppercased()): \(value)").textSelection(.enabled)
                                } else {
                                    Text(verbatim: "\(key.rawValue.uppercased()): \(value)")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
            }
            Spacer()
            Button {
#if DEBUG || REVIEW
                debugViewDisabled = true
#endif
                model.errors.removeAll()
            } label: {
                Image(.closeLarge)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(NSColor(red: 1, green: 0, blue: 0, alpha: 0.2)))
    }

#if DEBUG || REVIEW
    private var noFailure: String { "No failure" }
    private var zeroSuccess: String { "Success (0 imported)" }
    private var allFailureReasons: [String?] {
        [noFailure, zeroSuccess, nil] + DataImport.ErrorType.allCases.map { $0.rawValue }
    }

    private func failureReasonPicker(for dataType: DataImport.DataType) -> some View {
        Picker(selection: Binding {
            allFailureReasons.firstIndex(where: { failureReason in
                model.testImportResults[dataType]?.error?.errorType.rawValue == failureReason
                || (failureReason == zeroSuccess && model.testImportResults[dataType] == .success(.empty))
                || (failureReason == noFailure && model.testImportResults[dataType] == nil)
            })!
        } set: { newValue in
            let reason = allFailureReasons[newValue]!
            switch reason {
            case noFailure: model.testImportResults[dataType] = nil
            case zeroSuccess: model.testImportResults[dataType] = .success(.empty)
            default:
                let errorType = DataImport.ErrorType(rawValue: reason)!
                let error = LegacyDataImportViewModel.TestImportError(action: dataType.importAction, errorType: errorType)
                model.testImportResults[dataType] = .failure(error)
            }
        }) {
            ForEach(allFailureReasons.indices, id: \.self) { idx in
                if let failureReason = allFailureReasons[idx] {
                    Text(failureReason)
                } else {
                    Divider()
                }
            }
        } label: {
            Text("\(dataType.displayName) import error:" as String)
                .frame(width: 150, alignment: .leading)
        }
    }
#endif

}

extension LegacyDataImportViewModel.ButtonType {

    var shortcut: KeyboardShortcut? {
        switch self {
        case .next: .defaultAction
        case .initiateImport: .defaultAction
        case .skip: .cancelAction
        case .cancel: .cancelAction
        case .back: nil
        case .done: .defaultAction
        case .submit: .defaultAction
        }
    }

}

extension LegacyDataImportViewModel.ButtonType {

    func title(dataType: DataImport.DataType?) -> String {
        switch self {
        case .next:
            UserText.next
        case .initiateImport:
            UserText.initiateImport
        case .skip:
            switch dataType {
            case .some(.bookmarks):
                UserText.skipBookmarksImport
            case .some(.passwords):
                UserText.skipPasswordsImport
            case .some(.creditCards), nil: // Shouldn't really happen
                UserText.cancel
            }
        case .cancel:
            UserText.cancel
        case .back:
            UserText.navigateBack
        case .done:
            UserText.done
        case .submit:
            UserText.submitReport
        }
    }

}
