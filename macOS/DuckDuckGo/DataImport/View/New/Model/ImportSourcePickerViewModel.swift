//
//  ImportSourcePickerViewModel.swift
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
import BrowserServicesKit

@MainActor
final class ImportSourcePickerViewModel: ObservableObject {
    private enum Constants {
        static let minVisibleOptions: Int = 4
    }

    var selectedImportTypes: [DataImport.DataType] {
        didSet {
            typeButtonTitle = Self.titleFor(selectedImportTypes: selectedImportTypes)
        }
    }

    var selectableImportTypes: [DataImport.DataType]

    @Published var availableImportSources: [DataImport.Source]
    @Published var selectedSource: DataImport.Source {
        didSet {
            updateImportTypeItems()
            ensurePickerExpandedIfNeeded()
        }
    }
    @Published var isPickerExpanded: Bool = false
    @Published var importTypeItems: [ImportTypeItem] {
        didSet {
            isDoneButtonDisabled = importTypeItems.filter { $0.isSelected }.isEmpty
        }
    }
    @Published var isTypePickerSheetVisible: Bool = false
    @Published var isDoneButtonDisabled = false
    @Published var typeButtonTitle: String = UserText.importTypeSelectionTitleAll

    let shouldShowSyncButton: Bool

    private let onSourceSelected: (DataImport.Source) -> Void
    private let onTypeSelected: (DataImport.DataType, Bool) -> Void
    private let onSyncSelected: () -> Void

    init(availableSources: [DataImport.Source],
         selectedSource: DataImport.Source,
         selectedImportTypes: [DataImport.DataType],
         selectableImportTypes: [DataImport.DataType],
         shouldShowSyncButton: Bool,
         initialPickerExpanded: Bool = false,
         onSourceSelected: @escaping (DataImport.Source) -> Void,
         onTypeSelected: @escaping (DataImport.DataType, Bool) -> Void,
         onSyncSelected: @escaping () -> Void) {
        self.availableImportSources = availableSources
        self.selectedSource = selectedSource
        self.selectedImportTypes = selectedImportTypes
        self.selectableImportTypes = selectableImportTypes
        self.shouldShowSyncButton = shouldShowSyncButton
        self.onSourceSelected = onSourceSelected
        self.onTypeSelected = onTypeSelected
        self.onSyncSelected = onSyncSelected
        self.isPickerExpanded = initialPickerExpanded
        typeButtonTitle = Self.titleFor(selectedImportTypes: selectedImportTypes)
        importTypeItems = Self.makeImportTypeItems(selectableTypes: selectableImportTypes, selectedTypes: selectedImportTypes)

        ensurePickerExpandedIfNeeded()
    }

    // MARK: - Business Logic

    private static func makeImportTypeItems(selectableTypes: [DataImport.DataType], selectedTypes: [DataImport.DataType]) -> [ImportTypeItem] {
        selectableTypes.sorted(by: { $0.displayName < $1.displayName }).map {
            .init(dataType: $0, isSelected: selectedTypes.contains($0))
        }
    }

    private func updateImportTypeItems() {
        importTypeItems = Self.makeImportTypeItems(selectableTypes: selectableImportTypes, selectedTypes: selectedImportTypes)
    }

    var visibleOptions: [DataImport.Source] {
        isPickerExpanded ? availableImportSources : collapsedOptions
    }

    private var collapsedOptions: [DataImport.Source] {
        Array(availableImportSources[0..<min(availableImportSources.count, Constants.minVisibleOptions)])
    }

    private func ensurePickerExpandedIfNeeded() {
        if visibleOptions.contains(selectedSource) == false {
            isPickerExpanded = true
        }
    }

    var shouldShowExpandButton: Bool {
        !isPickerExpanded && availableImportSources.count > Constants.minVisibleOptions
    }

    // MARK: - Actions

    func selectSource(_ source: DataImport.Source) {
        selectedSource = source
        onSourceSelected(source)
    }

    func toggleExpansion() {
        isPickerExpanded.toggle()
    }

    func showTypeSelectionSheet() {
        isTypePickerSheetVisible = true
    }

    func syncSelected() {
        onSyncSelected()
    }

    func typeSelectionCancelled() {
        updateImportTypeItems()
        isTypePickerSheetVisible = false
    }

    func typeSelectionDone() {
        importTypeItems.forEach { item in
            onTypeSelected(item.dataType, item.isSelected)
        }
        selectedImportTypes = importTypeItems.filter(\.isSelected).map(\.dataType)
        isTypePickerSheetVisible = false
    }

    func updateSelectableImportTypes(_ newSelectableImportTypes: [DataImport.DataType]) {
        selectableImportTypes = newSelectableImportTypes

        selectedImportTypes = selectedImportTypes.filter { newSelectableImportTypes.contains($0) }
        updateImportTypeItems()
    }

    func updateSelectedImportTypes(_ newSelectedImportTypes: [DataImport.DataType]) {
        selectedImportTypes = newSelectedImportTypes
        updateImportTypeItems()
    }
}

private extension ImportSourcePickerViewModel {
    static func titleFor(selectedImportTypes: [DataImport.DataType]) -> String {
        guard !selectedImportTypes.isEmpty else {
            // No types available - this shouldn't happen!
            return UserText.importDataImportTypeTitleSelected
        }

        if selectedImportTypes.count >= 2,
            selectedImportTypes.contains(.passwords),
            selectedImportTypes.contains(.bookmarks) {
            return UserText.importTypeSelectionTitleAll
        } else if selectedImportTypes.first == .bookmarks {
            return UserText.importTypeSelectionTitleBookmarks
        } else if selectedImportTypes.first == .passwords {
            return UserText.importTypeSelectionTitlePasswords
        } else {
            // Fallback for unexpected cases
            return UserText.importDataImportTypeTitleSelected
        }
    }
}

struct ImportTypeItem: Identifiable, Equatable {
    var dataType: DataImport.DataType
    var isSelected: Bool
    var id: String {
        dataType.rawValue
    }
}
