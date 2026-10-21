//
//  DuckAINativeDebugView.swift
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

struct DuckAINativeDebugView: View {

    @ObservedObject var settings: DuckAINativeSettings

    init(settings: DuckAINativeSettings = .shared) {
        self.settings = settings
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Feature flag", value: settings.isFeatureAvailable ? "On" : "Off, enable duckAINativeMode")
                Picker("New chats open in", selection: $settings.mode) {
                    Text("Web").tag(DuckAINativeSettings.Mode.web)
                    Text("Native").tag(DuckAINativeSettings.Mode.native)
                }
            } footer: {
                Text("Applies to new chats. Open chats keep their mode.")
            }
            Section("Provider") {
                Picker("Provider", selection: $settings.provider) {
                    Text("Automatic").tag(DuckAINativeSettings.ProviderChoice.automatic)
                    Text("Stub").tag(DuckAINativeSettings.ProviderChoice.stub)
                    Text("Apple Foundation Models").tag(DuckAINativeSettings.ProviderChoice.foundationModels)
                    Text("MLX").tag(DuckAINativeSettings.ProviderChoice.mlx)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle("Native Duck.ai (demo)")
    }
}
