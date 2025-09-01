//
//  DataBrokerLogMonitorView.swift
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

struct DataBrokerLogMonitorView: View {
    @ObservedObject var viewModel: DataBrokerLogMonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            LogMonitorToolbarView(
                isMonitoring: viewModel.isMonitoring,
                logCount: viewModel.logCount,
                onStartStop: {
                    viewModel.isMonitoring ? viewModel.stopMonitoring() : viewModel.startMonitoring()
                },
                onClear: viewModel.clearLogs,
                retentionLimit: $viewModel.retentionLimitText
            )
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            LogFilterControlsView(
                filterSettings: $viewModel.filterSettings
            )
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            if viewModel.filteredLogs.isEmpty {
                LogEmptyStateView(isMonitoring: viewModel.isMonitoring)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LogListView(
                    logs: viewModel.filteredLogs,
                    autoScroll: viewModel.filterSettings.autoScroll
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let errorMessage = viewModel.errorMessage {
                ErrorBannerView(message: errorMessage) {
                    viewModel.errorMessage = nil
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .navigationTitle("DataBrokerProtection Log Monitor")
    }
}
