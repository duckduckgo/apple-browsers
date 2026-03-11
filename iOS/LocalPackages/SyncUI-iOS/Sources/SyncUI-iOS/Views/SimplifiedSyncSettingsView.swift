//
//  SimplifiedSyncSettingsView.swift
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

import SwiftUI

public struct SimplifiedSyncSettingsView: View {

    @ObservedObject public var model: SyncSettingsViewModel

    public init(model: SyncSettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                if model.isSyncEnabled {
                    Text(verbatim: "Sync is enabled")
                } else {
                    Text(verbatim: "Sync is not enabled")
                }
            }
        }
        .navigationTitle(UserText.syncTitle)
        .applyListStyle()
        .environmentObject(model)
    }
}
