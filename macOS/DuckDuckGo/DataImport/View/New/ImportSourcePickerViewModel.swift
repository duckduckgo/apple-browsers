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
import SwiftUI
import BrowserServicesKit

@MainActor
class ImportSourcePickerViewModel: ObservableObject {
    private enum Constants {
        static let minVisibleOptions: Int = 4
    }
    
    @Published var availableImportSources: [DataImport.Source]
    @Published var selectedImportSource: DataImport.Source
    @Published var isPickerExpanded: Bool = false
    
    let shouldShowSyncButton: Bool
    
    private let onSourceSelected: (DataImport.Source) -> Void
    private let onSyncSelected: () -> Void
    
    init(availableSources: [DataImport.Source], 
         selectedSource: DataImport.Source,
         shouldShowSyncButton: Bool = false,
         onSourceSelected: @escaping (DataImport.Source) -> Void,
         onSyncSelected: @escaping () -> Void = {}) {
        self.availableImportSources = availableSources
        self.selectedImportSource = selectedSource
        self.shouldShowSyncButton = shouldShowSyncButton
        self.onSourceSelected = onSourceSelected
        self.onSyncSelected = onSyncSelected
    }
    
    // MARK: - Business Logic
    
    var visibleOptions: [DataImport.Source] {
        isPickerExpanded ? availableImportSources : collapsedOptions
    }
    
    private var collapsedOptions: [DataImport.Source] {
        Array(availableImportSources[0..<min(availableImportSources.count, Constants.minVisibleOptions)])
    }
    
    var shouldShowExpandButton: Bool {
        !isPickerExpanded && availableImportSources.count > Constants.minVisibleOptions
    }
    
    // MARK: - Actions
    
    func selectSource(_ source: DataImport.Source) {
        selectedImportSource = source
        onSourceSelected(source)
    }
    
    func toggleExpansion() {
        isPickerExpanded.toggle()
    }
    
    func syncSelected() {
        onSyncSelected()
    }
}
