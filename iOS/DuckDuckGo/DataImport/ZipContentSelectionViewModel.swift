//
//  ZipContentSelectionViewModel.swift
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
import BrowserServicesKit
import SwiftUI
import Core
import DesignResourcesKit
import DesignResourcesKitIcons

protocol ZipContentSelectionViewModelDelegate: AnyObject {
    func zipContentSelectionViewModelDidSelectOptions(_ viewModel: ZipContentSelectionViewModel, selectedTypes: [DataImport.DataType])
    func zipContentSelectionViewModelDidSelectCancel(_ viewModel: ZipContentSelectionViewModel)
    func zipContentSelectionViewModelDidResizeContent(_ viewModel: ZipContentSelectionViewModel, contentHeight: CGFloat)
}

extension DataImportPreview {
    var icon: Image {
        switch type {
        case .bookmarks:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.bookmarksOpen)
        case .passwords:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.key)
        case .creditCards:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.creditCard)
        }
    }

    var title: String {
        switch type {
        case .bookmarks:
            return UserText.zipContentSelectionBookmarks
        case .passwords:
            return UserText.zipContentSelectionPasswords
        case .creditCards:
            return UserText.zipContentSelectionCreditCards
        }
    }
}

final class ZipContentSelectionViewModel: ObservableObject {

    weak var delegate: ZipContentSelectionViewModelDelegate?

    var contentHeight: CGFloat = AutofillViews.zipImportPromptMinHeight {
        didSet {
            guard contentHeight != oldValue else { return }
            delegate?.zipContentSelectionViewModelDidResizeContent(self,
                                                                   contentHeight: max(contentHeight, AutofillViews.zipImportPromptMinHeight))
        }
    }

    var importPreview: [DataImportPreview]

    @Published var selectedTypes: Set<DataImport.DataType> = []

    init(importPreview: [DataImportPreview]) {
        self.importPreview = importPreview
        self.selectedTypes = Set(importPreview.map { $0.type })
    }

    func toggleSelection(_ type: DataImport.DataType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
    }

    func optionsSelected() {
        delegate?.zipContentSelectionViewModelDidSelectOptions(self, selectedTypes: Array(selectedTypes))
    }

    func closeButtonPressed() {
        delegate?.zipContentSelectionViewModelDidSelectCancel(self)
    }

}
