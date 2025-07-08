//
//  DataImportTypePicker.swift
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

import SwiftUI
import BrowserServicesKit

struct DataImportTypePicker: View {

    @Binding var viewModel: DataImportViewModel
    @State private var isDataTypePickerExpanded: Bool

    init(viewModel: Binding<DataImportViewModel>, isDataTypePickerExpanded: Bool) {
        _viewModel = viewModel
        _isDataTypePickerExpanded = State(initialValue: isDataTypePickerExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if isDataTypePickerExpanded {
                    Text(UserText.importDataImportTypeTitleSelected)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        if case .all = viewModel.dataTypesSelection {
                            Text(UserText.importDataImportTypeTitleCollapsedAll)
                        } else {
                            Text(UserText.importDataImportTypeTitleSelected)
                        }

                        subtitleText
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: {
                    isDataTypePickerExpanded.toggle()
                }) {
                    Image(.chevronCircleRight16)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(isDataTypePickerExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
            }
            if isDataTypePickerExpanded {
                pickerBody
            }
        }
    }

    private var subtitleText: Text {
        switch viewModel.dataTypesSelection {
        case .all:
            Text(UserText.importDataImportTypeSubtitleBookmarksAndPasswords)
        case .single(let type):
            Text(type.displayName)
        case .none:
            Text(UserText.importDataImportTypeSubtitleNone)
        }
    }

    @ViewBuilder
    private var pickerBody: some View {
        VStack(alignment: .leading) {
            ForEach(DataImport.DataType.allCases, id: \.self) { dataType in
                // display all types for a browser disabling unavailable options
                if viewModel.importSource.isBrowser
                    // display only supported types for a non-browser
                    || viewModel.importSource.supportedDataTypes.contains(dataType) {

                    Toggle(isOn: Binding {
                        viewModel.selectedDataTypes.contains(dataType)
                    } set: { isOn in
                        viewModel.setDataType(dataType, selected: isOn)
                    }) {
                        Text(dataType.displayName)
                    }
                    .disabled(!viewModel.importSource.supportedDataTypes.contains(dataType))

                    // subtitle
                    if case .passwords = dataType,
                       !viewModel.importSource.supportedDataTypes.contains(.passwords) {
                        Text("\(viewModel.importSource.importSourceName) does not support storing passwords",
                             comment: "Data Import disabled checkbox message about a browser (%@) not supporting storing passwords")
                        .foregroundColor(Color(.disabledControlTextColor))
                    }
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 0)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.blackWhite3)
        .cornerRadius(5)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.decorationTertiary, lineWidth: 1)
        )
    }
}

extension DataImportViewModel {

    mutating func setDataType(_ dataType: DataType, selected: Bool) {
        if selected {
            selectedDataTypes.insert(dataType)
        } else {
            selectedDataTypes.remove(dataType)
        }
    }

}
