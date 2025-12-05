//
//  DataImportView.swift
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
import SwiftUI
import BrowserServicesKit
import PixelKit
import DesignResourcesKitIcons
import UniformTypeIdentifiers
import SwiftUIExtensions

@MainActor
struct DataImportView: ModalView {
    @Environment(\.dismiss) private var dismiss

    @State var model: DataImportViewModel

    let importFlowLauncher: DataImportFlowRelaunching

    @State private var isInternalUser = false
    let internalUserDecider: InternalUserDecider = Application.appDelegate.internalUserDecider

    private let syncFeatureVisibility: SyncFeatureVisibility

    init(model: DataImportViewModel? = nil, importFlowLauncher: DataImportFlowRelaunching, syncFeatureVisibility: SyncFeatureVisibility) {
        let model = model ?? DataImportViewModel(syncFeatureVisibility: syncFeatureVisibility)
        self._model = State(initialValue: model)
        self.importFlowLauncher = importFlowLauncher
        self.syncFeatureVisibility = syncFeatureVisibility
    }

    struct ProgressState {
        let text: String?
        let fraction: Double?
        let updated: CFTimeInterval
    }
    @State private var progress: ProgressState?

#if DEBUG || REVIEW
    @State private var debugViewDisabled: Bool = true
#endif

    private var shouldShowDebugView: Bool {
#if DEBUG || REVIEW
        return !debugViewDisabled
#else
        return (!model.errors.isEmpty && isInternalUser)
#endif
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            switch model.screen {
            case .sourceAndDataTypesPicker:
                ImportSourcePickerView(
                    availableSources: model.availableImportSources,
                    selectedSource: model.importSource,
                    selectedImportTypes: Array(model.selectedDataTypes),
                    selectableImportTypes: Array(model.selectableImportTypes),
                    shouldShowSyncFeature: syncFeatureVisibility.shouldShowSyncFeature,
                    isPickerExpanded: model.isPickerExpanded,
                    onSourceSelected: { source in
                        model.update(with: source)
                    },
                    onTypeSelected: { type, isSelected in
                        model.setDataType(type, selected: isSelected)
                    },
                    onSyncSelected: {
                        model.launchSync(using: dismiss.callAsFunction) {
                            importFlowLauncher.relaunchDataImport(model: model)
                        }
                    },
                    onExpandedStateChanged: { isExpanded in
                        model.isPickerExpanded = isExpanded
                    }
                )
            case .profilePicker:
                NewProfilePickerView(
                    profiles: model.browserProfiles?.validImportableProfiles ?? [],
                    selectedProfile: model.selectedProfile
                ) { profile in
                    model.selectProfile(profile)
                }
            case .fileImport(let dataType, let summary):
                FileImportScreenView(
                    importSource: model.importSource,
                    kind: .individual(dataType: dataType),
                    summary: summary,
                    isSelectFileButtonDisabled: model.isSelectFileButtonDisabled,
                    selectFile: { model.selectFile() },
                    onFileDrop: { model.initiateImport(fileURL: $0) }
                )
            case .archiveImport(_, let summary):
                FileImportScreenView(
                    importSource: model.importSource,
                    kind: .archive,
                    summary: summary,
                    isSelectFileButtonDisabled: model.isSelectFileButtonDisabled,
                    selectFile: { model.selectFile() },
                    onFileDrop: { model.initiateImport(fileURL: $0) }
                )
            case .moreInfo:
                NewImportMoreInfoView()
            case .passwordEntryHelp:
                PasswordEntryRetryPromptView(
                    onRetry: {
                        model.initiateImport()
                    }
                )
            case .summary(let summary):
                NewImportSummaryView(
                    summary: summary,
                    sourceImage: model.importSource.importSourceImage ?? DesignSystemImages.Color.Size24.document,
                    reportModel: $model.reportModel
                ) { type in
                    model.showSummaryDetail(summary: summary, type: type)
                }
            case .summaryDetail(let summary, _):
                // This view is currently only used for passwords
                if let result = summary[.passwords] {
                    DataImportSummaryDetailView(result: result)
                } else {
                    EmptyView()
                }
            }

            // if import in progress…
            if let importProgress = model.importProgress, !model.shouldHideProgress {
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
        .onChange(of: model.importTaskId) { _ in
            Task {
                if let importProgress = model.importProgress {
                    await handleImportProgress(importProgress)
                }
            }
        }
    }

    private func progressView(_ progress: TaskProgress<DataImportViewModel, Never, DataImportProgressEvent>) -> some View {
        // Progress bar with label: Importing [bookmarks|passwords]…
        ProgressView(value: self.progress?.fraction) {
            Text(self.progress?.text ?? "")
        }
    }

    // under line buttons
    private func viewFooter() -> some View {
        HStack(spacing: 8) {
            if !model.shouldHidePasswordExplainerView {
                passwordsExplainerView()
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
        .opacity(model.shouldHideFooter ? 0 : 1)
    }

    @State private var showPasswordsExplainerPopover = false
    @State private var popoverCloseTask: Task<Void, Never>?

    private func passwordsExplainerView() -> some View {
        HStack(spacing: 8) {
            ZStack(alignment: .center) {
                // Invisible rectangle to push the popover away from the icon slightly
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16, height: 24)
                    .popover(isPresented: $showPasswordsExplainerPopover, arrowEdge: .bottom) {
                        Text(model.isPasswordManagerAutolockEnabled ? UserText.importLoginsPasswordsExplainer : UserText.importLoginsPasswordsExplainerAutolockOff)
                            .padding()
                            .frame(width: 280)
                    }

                Image(nsImage: DesignSystemImages.Glyphs.Size16.lock)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: showPasswordsExplainerPopover ? .iconsPrimary : .iconsTertiary))
            }
            Text(UserText.importLoginsPasswordsExplainerEncrypted)
                .font(.system(size: 11))
                .foregroundColor(Color(designSystemColor: showPasswordsExplainerPopover ? .iconsPrimary : .iconsTertiary))

        }
        .padding(8) // Increase the hit area of the view by 8px on all sides
        .contentShape(Rectangle())
        .padding(-8)
        .onHover { isHovering in
            popoverCloseTask?.cancel()

            if isHovering {
                showPasswordsExplainerPopover = true
            } else {
                popoverCloseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if !Task.isCancelled {
                        showPasswordsExplainerPopover = false
                    }
                }
            }
        }
    }

    private func handleImportProgress(_ progress: TaskProgress<DataImportViewModel, Never, DataImportProgressEvent>) async {
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
                let error = DataImportViewModel.TestImportError(action: dataType.importAction, errorType: errorType)
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

extension DataImportProgressEvent {

    var fraction: Double? {
        switch self {
        case .initial:
            nil
        case .importingBookmarks(numberOfBookmarks: _, fraction: let fraction):
            fraction
        case .importingPasswords(numberOfPasswords: _, fraction: let fraction):
            fraction
        case .importingCreditCards(numberOfCreditCards: _, fraction: let fraction):
            fraction
        case .done:
            nil
        }
    }

    var description: String? {
        switch self {
        case .initial:
            nil
        case .importingBookmarks(numberOfBookmarks: let num, fraction: _):
            UserText.importingBookmarks(num)
        case .importingPasswords(numberOfPasswords: let num, fraction: _):
            UserText.importingPasswords(num)
        case .importingCreditCards(numberOfCreditCards: let num, fraction: _):
            UserText.importingCreditCards(num)
        case .done:
            nil
        }
    }

}

extension DataImportViewModel.ButtonType {

    var shortcut: KeyboardShortcut? {
        switch self {
        case .initiateImport: .defaultAction
        case .selectFile: .defaultAction
        case .skip: .cancelAction
        case .cancel: .cancelAction
        case .back: .cancelAction
        case .close: .cancelAction
        case .done: .cancelAction
        case .submit: .defaultAction
        case .continue: .defaultAction
        case .sync: .defaultAction
        }
    }

}

extension DataImportViewModel.ButtonType {

    func title(dataType: DataImport.DataType?) -> String {
        switch self {
        case .initiateImport:
            UserText.importNowButtonTitle
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
        case .continue:
            UserText.continue
        case .selectFile:
            UserText.importDataSelectFileButtonTitle
        case .sync:
            UserText.importDataCompleteSyncButtonTitle
        case .close:
            UserText.close
        }
    }

}
