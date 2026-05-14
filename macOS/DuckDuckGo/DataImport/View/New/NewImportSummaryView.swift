//
//  NewImportSummaryView.swift
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
import DesignResourcesKitIcons
import DesignResourcesKit

struct NewImportSummaryView: View {

    @StateObject private var viewModel: NewImportSummaryViewModel
    @Binding var reportModel: DataImportReportModel
    private let sourceImage: NSImage
    let onShowDetail: ((DataImport.DataType) -> Void)?

    init(summary: DataImportSummary, sourceImage: NSImage, reportModel: Binding<DataImportReportModel>, pinningManager: PinningManager, onShowDetail: ((DataImport.DataType) -> Void)? = nil) {
        _viewModel = .init(wrappedValue: .init(summary: summary, pinningManager: pinningManager))
        _reportModel = reportModel
        self.sourceImage = sourceImage
        self.onShowDetail = onShowDetail
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: viewModel.shouldShowSuccessImage ? DesignSystemImages.Color.Size128.bringStuff : sourceImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: viewModel.shouldShowSuccessImage ? 96 : 72)
            Text(UserText.importDataSummaryTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            ForEach(viewModel.items) { item in
                VStack(alignment: .leading, spacing: 0) {
                    switch item {
                    case .success(let successItem):
                        importSuccessRow(item: successItem, in: item)
                    case .failure(let title):
                        NewImportErrorView(text: title)
                    }
                }
                .borderedBackground()
            }
            if viewModel.shouldShowFeedbackView {
                NewReportFeedbackView(model: $reportModel)
            }
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func importSuccessRow(item: NewImportSummaryViewModel.SuccessItem, in summaryItem: NewImportSummaryViewModel.SummaryItem) -> some View {
        importSuccessSummaryRow(item: item)
        if let shortcutItem = item.shortcut {
            lineSeparator
            importSuccessShortcutsRow(
                title: shortcutItem.title,
                isOn: Binding<Bool>(
                    get: { shortcutItem.isOn },
                    set: { viewModel.didTriggerShortcut(on: summaryItem, isOn: $0) }
                )
            )
        }
    }

    private func importSuccessSummaryRow(item: NewImportSummaryViewModel.SuccessItem) -> some View {
        HStack(spacing: 0) {
            Image(nsImage: item.image)
                .frame(width: 16, height: 16)
                .padding(.trailing, 14)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading) {
                    Text(item.primaryText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    if let duplicateText = item.duplicateText {
                        Text(duplicateText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if let failureText = item.failureText {
                        Text(failureText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()

                if item.type == .passwords {
                    Button(UserText.importSummaryViewDetails) {
                        onShowDetail?(item.type)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 41)
    }

    private func importSuccessShortcutsRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .padding(.top, 0)
                .padding(.bottom, 1)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .padding(.horizontal, 10)
    }

    private var lineSeparator: some View {
        Divider()
            .foregroundColor(.secondary).padding(.leading, 12)
    }
}
