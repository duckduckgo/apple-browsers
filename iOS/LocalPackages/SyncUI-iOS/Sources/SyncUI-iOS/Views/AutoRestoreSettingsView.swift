//
//  AutoRestoreSettingsView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import DesignResourcesKit
import DuckUI
import SwiftUI

struct AutoRestoreSettingsView: View {

    @ObservedObject var model: SyncSettingsViewModel

    private var autoRestoreBinding: Binding<Bool> {
        Binding {
            model.isAutoRestoreEnabled
        } set: { newValue in
            model.requestAutoRestoreUpdate(enabled: newValue)
        }
    }

    var body: some View {
        List {
            Section(footer: Text(UserText.autoRestoreScreenDescription)) {
                Toggle(UserText.autoRestoreSettingsRowLabel, isOn: autoRestoreBinding)
                    .toggleStyle(SwitchToggleStyle(tint: Color(designSystemColor: .accent)))
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .disabled(model.isAutoRestoreUpdating)
            }
            .listRowBackground(Color(designSystemColor: .surface))
        }
        .navigationTitle(UserText.autoRestoreScreenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .applyListStyle()
        .onAppear {
            model.autoRestoreSettingsPageShown()
        }
    }
}
