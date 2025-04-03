//
//  DuckPlayerDebugSettingsView.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Core
import DuckUI

/// A debug settings view for DuckPlayer that provides options to reset and manage DuckPlayer-specific settings.
struct DuckPlayerDebugSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let appSettings: AppSettings

    @State private var dismissCount: Int = 0
    
    init(appSettings: AppSettings = AppDependencyProvider.shared.appSettings) {
        self.appSettings = appSettings
    }
    
    var body: some View {
        List {
            Section(header: Text("Priming Modal")) {
                Button {
                    resetPrimingModalSettings()
                } label: {
                    Text("Reset Priming Modal State")
                }
            }

            Section(header: Text("Entry Pill")) {
                Text("Current Dismiss Count: \(dismissCount)")
                Button {
                    resetEntryPillSettings()
                } label: {
                    Text("Reset Pill Dismiss Count")
                }
            }
        }
        .navigationTitle("DuckPlayer")
        .onAppear {
            dismissCount = appSettings.duckPlayerPillDismissCount
        }
    }
    
    private func resetPrimingModalSettings() {
        appSettings.duckPlayerNativeUIPrimingModalPresentationEventCount = 0
        appSettings.duckPlayerNativeUIPrimingModalTimeSinceLastPresented = 0
    }

    private func resetEntryPillSettings() {
        dismissCount = 0
        appSettings.duckPlayerPillDismissCount = 0
    }
}
