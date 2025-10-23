//
//  FileImportScreenView.swift
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

import SwiftUI
import BrowserServicesKit

struct FileImportScreenView: View {
    @Binding var model: DataImportViewModel
    let kind: NewFileImportView.Kind
    let summaryTypes: Set<DataImport.DataType>
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            VStack(alignment: .center, spacing: 20) {
                if let importSourceImage = model.importSource.importSourceImage {
                    Image(nsImage: importSourceImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                }

                Text(UserText.importFromFileTitle(from: model.importSource))
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: 0) {
                    if !summaryTypes.isEmpty {
                        DataImportSummaryView(model, dataTypes: summaryTypes)
                            .padding(.bottom, 24)
                    }

                    if case .individual(let dataType) = kind {
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
                    }

                    // manual file import instructions for CSV/HTML
                    NewFileImportView(source: model.importSource,
                                      allowedFileTypes: kind.supportedFileTypes(for: model.importSource),
                                      isButtonDisabled: model.isSelectFileButtonDisabled,
                                      kind: kind) {
                        model.selectFile()
                    } onFileDrop: { url in
                        model.initiateImport(fileURL: url)
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            .padding(.top, 20)
        }
    }

    @ViewBuilder
    private var importSourcePicker: some View {
        DataImportSourcePicker(importSources: model.availableImportSources, selectedSource: model.importSource) { importSource in
            model.update(with: importSource)
        }
        .padding(.bottom, 8)
        .disabled(model.isImportSourcePickerDisabled)
    }

    private func importPickerPanel<Content: View>(_ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            importSourceDataTitle
            importSourcePicker
            content()
        }
        .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
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
}
